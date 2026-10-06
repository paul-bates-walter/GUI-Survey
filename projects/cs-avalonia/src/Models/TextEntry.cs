using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AvaloniaPngEditor.Models;

/// A single editable PNG tEXt key/value pair, bound two-way in the metadata panel.
public sealed class TextEntry : INotifyPropertyChanged
{
    private string _key = "";
    private string _value = "";

    public string Key
    {
        get => _key;
        set { if (_key != value) { _key = value; OnChanged(); } }
    }

    public string Value
    {
        get => _value;
        set { if (_value != value) { _value = value; OnChanged(); } }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
