using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform.Storage;
using AvaloniaPngEditor.Controls;
using AvaloniaPngEditor.Models;
using AvaloniaPngEditor.Services;

namespace AvaloniaPngEditor.Views;

public partial class MainWindow : Window
{
    private static readonly FilePickerFileType PngType = new("PNG Images")
    {
        Patterns = new[] { "*.png" },
        MimeTypes = new[] { "image/png" },
    };

    private IStorageFile? _currentFile;
    private bool _forceClose;

    public ObservableCollection<TextEntry> Entries { get; } = new();

    public RelayCommand NewCommand { get; }
    public RelayCommand OpenCommand { get; }
    public RelayCommand SaveCommand { get; }
    public RelayCommand SaveAsCommand { get; }
    public RelayCommand QuitCommand { get; }

    public MainWindow()
    {
        NewCommand = new RelayCommand(NewAsync);
        OpenCommand = new RelayCommand(OpenAsync);
        SaveCommand = new RelayCommand(async () => await SaveAsync());
        SaveAsCommand = new RelayCommand(async () => await SaveAsAsync());
        QuitCommand = new RelayCommand(() => { Close(); return Task.CompletedTask; });

        InitializeComponent();
        DataContext = this;

        PaintCanvas.ModifiedChanged += (_, _) => UpdateTitle();
        UpdateSwatch();
        UpdateTitle();
    }

    // --- Toolbar handlers ---------------------------------------------------

    private void OnModeChanged(object? sender, SelectionChangedEventArgs e)
    {
        if (PaintCanvas is not null)
            PaintCanvas.SetMode((DrawMode)ModeBox.SelectedIndex);
    }

    private void OnRadiusChanged(object? sender, NumericUpDownValueChangedEventArgs e)
    {
        if (PaintCanvas is not null && RadiusBox.Value is decimal d)
            PaintCanvas.PenRadius = (double)d;
    }

    private void OnColorSwatch(object? sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.Tag is string hex && Color.TryParse(hex, out var color))
        {
            PaintCanvas.PenColor = color;
            UpdateSwatch();
        }
    }

    // --- Metadata handlers --------------------------------------------------

    private void OnAddField(object? sender, RoutedEventArgs e) => Entries.Add(new TextEntry());

    private void OnRemoveField(object? sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.DataContext is TextEntry entry)
            Entries.Remove(entry);
    }

    // --- File commands ------------------------------------------------------

    private async Task NewAsync()
    {
        if (!await ConfirmDiscardAsync())
            return;
        PaintCanvas.NewImage(800, 600);
        Entries.Clear();
        _currentFile = null;
        UpdateTitle();
    }

    private async Task OpenAsync()
    {
        if (!await ConfirmDiscardAsync())
            return;

        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Open PNG",
            AllowMultiple = false,
            FileTypeFilter = new[] { PngType },
        });
        if (files.Count == 0)
            return;

        var file = files[0];
        byte[] bytes = await ReadAllBytesAsync(file);
        try
        {
            using var stream = new MemoryStream(bytes);
            PaintCanvas.SetImage(new Bitmap(stream));
        }
        catch
        {
            await MessageDialog.ShowAsync(this, "Open Failed", "Could not load the selected image.");
            return;
        }

        Entries.Clear();
        foreach (var kv in PngText.Read(bytes))
            Entries.Add(new TextEntry { Key = kv.Key, Value = kv.Value });

        _currentFile = file;
        UpdateTitle();
    }

    private async Task<bool> SaveAsync()
    {
        if (_currentFile is null)
            return await SaveAsAsync();
        await WriteToAsync(_currentFile);
        return true;
    }

    private async Task<bool> SaveAsAsync()
    {
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save PNG",
            SuggestedFileName = "untitled.png",
            DefaultExtension = "png",
            FileTypeChoices = new[] { PngType },
        });
        if (file is null)
            return false;

        _currentFile = file;
        await WriteToAsync(file);
        UpdateTitle();
        return true;
    }

    private async Task WriteToAsync(IStorageFile file)
    {
        byte[] png = PaintCanvas.ExportPng();
        byte[] withMeta = PngText.Write(png, EntriesToDict());

        string? local = file.TryGetLocalPath();
        if (local is not null)
        {
            await File.WriteAllBytesAsync(local, withMeta);
        }
        else
        {
            await using var stream = await file.OpenWriteAsync();
            stream.SetLength(0);
            await stream.WriteAsync(withMeta);
        }

        PaintCanvas.MarkSaved();
        UpdateTitle();
    }

    // --- Unsaved-changes guard ---------------------------------------------

    private async Task<bool> ConfirmDiscardAsync()
    {
        if (!PaintCanvas.IsModified)
            return true;

        return await ConfirmDialog.ShowAsync(this) switch
        {
            ConfirmResult.Save => await SaveAsync(),
            ConfirmResult.Discard => true,
            _ => false,
        };
    }

    protected override async void OnClosing(WindowClosingEventArgs e)
    {
        if (!_forceClose && PaintCanvas.IsModified)
        {
            e.Cancel = true;
            if (await ConfirmDiscardAsync())
            {
                _forceClose = true;
                Close();
            }
            return;
        }
        base.OnClosing(e);
    }

    // --- Helpers ------------------------------------------------------------

    private Dictionary<string, string> EntriesToDict()
    {
        var dict = new Dictionary<string, string>();
        foreach (var entry in Entries)
            if (!string.IsNullOrWhiteSpace(entry.Key))
                dict[entry.Key] = entry.Value ?? "";
        return dict;
    }

    private static async Task<byte[]> ReadAllBytesAsync(IStorageFile file)
    {
        await using var stream = await file.OpenReadAsync();
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms);
        return ms.ToArray();
    }

    private void UpdateSwatch() =>
        ColorSwatch.Background = new SolidColorBrush(PaintCanvas.PenColor);

    private void UpdateTitle()
    {
        string name = _currentFile?.Name ?? "Untitled";
        string mark = PaintCanvas.IsModified ? "*" : "";
        Title = $"{name}{mark} — PNG Editor (Avalonia)";
    }
}
