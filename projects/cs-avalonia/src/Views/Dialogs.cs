using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace AvaloniaPngEditor.Views;

public enum ConfirmResult { Save, Discard, Cancel }

/// Small code-built modal dialogs (core Avalonia has no built-in message box).
public sealed class ConfirmDialog : Window
{
    private ConfirmResult _result = ConfirmResult.Cancel;

    private ConfirmDialog()
    {
        Title = "Unsaved Changes";
        Width = 380;
        SizeToContent = SizeToContent.Height;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var save = MakeButton("Save", ConfirmResult.Save);
        var discard = MakeButton("Discard", ConfirmResult.Discard);
        var cancel = MakeButton("Cancel", ConfirmResult.Cancel);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        buttons.Children.Add(save);
        buttons.Children.Add(discard);
        buttons.Children.Add(cancel);

        var root = new StackPanel { Margin = new Thickness(16), Spacing = 16 };
        root.Children.Add(new TextBlock
        {
            Text = "The image has unsaved changes. Save them?",
            TextWrapping = TextWrapping.Wrap,
        });
        root.Children.Add(buttons);
        Content = root;
    }

    private Button MakeButton(string text, ConfirmResult result)
    {
        var b = new Button { Content = text };
        b.Click += (_, _) => { _result = result; Close(); };
        return b;
    }

    public static async Task<ConfirmResult> ShowAsync(Window owner)
    {
        var dialog = new ConfirmDialog();
        await dialog.ShowDialog(owner);
        return dialog._result;
    }
}

/// Single-button informational dialog.
public sealed class MessageDialog : Window
{
    private MessageDialog(string title, string message)
    {
        Title = title;
        Width = 380;
        SizeToContent = SizeToContent.Height;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var ok = new Button { Content = "OK", HorizontalAlignment = HorizontalAlignment.Right };
        ok.Click += (_, _) => Close();

        var root = new StackPanel { Margin = new Thickness(16), Spacing = 16 };
        root.Children.Add(new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap });
        root.Children.Add(ok);
        Content = root;
    }

    public static Task ShowAsync(Window owner, string title, string message) =>
        new MessageDialog(title, message).ShowDialog(owner);
}
