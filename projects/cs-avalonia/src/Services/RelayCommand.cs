using System;
using System.Threading.Tasks;
using System.Windows.Input;

namespace AvaloniaPngEditor.Services;

/// Minimal async ICommand used to wire menu items and key bindings to handlers.
public sealed class RelayCommand : ICommand
{
    private readonly Func<Task> _execute;

    public RelayCommand(Func<Task> execute) => _execute = execute;

    public event EventHandler? CanExecuteChanged;

    public bool CanExecute(object? parameter) => true;

    public async void Execute(object? parameter) => await _execute();

    // Present so the compiler doesn't warn about the unused event.
    public void RaiseCanExecuteChanged() =>
        CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
