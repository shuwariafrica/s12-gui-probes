using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.XamlTypeInfo;
using Microsoft.Windows.ApplicationModel.WindowsAppRuntime;
using Windows.Graphics;
using Windows.System;

namespace S12WinUI;

/// <summary>
/// A WinUI 3 window titled s12-winui whose label answers what is typed into its field, built in
/// code as pamba's MVU runtime projects its views. Its one argument is the log file the driver
/// prints when a check fails.
/// </summary>
internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        string log = args.Length == 1 ? args[0] : throw new ArgumentException("usage: S12WinUI <log file>", nameof(args));
        WinRT.ComWrappersSupport.InitializeComWrappers();
        // Constructing the application registers it as Application.Current, which Start then runs.
        Application.Start(callback => _ = new ProbeApp(log));
    }
}

// With no XAML compiled, the application itself resolves the controls' types for XamlControlsResources.
internal sealed partial class ProbeApp : Application, IXamlMetadataProvider
{
    private readonly XamlControlsXamlMetaDataProvider _provider = new();
    private readonly string _log;
    private Window? _window;

    public ProbeApp(string log)
    {
        _log = log;
        UnhandledException += (_, e) => Write($"unhandled: {e.Exception}");
    }

    public IXamlType GetXamlType(Type type) => _provider.GetXamlType(type);

    public IXamlType GetXamlType(string fullName) => _provider.GetXamlType(fullName);

    public XmlnsDefinition[] GetXmlnsDefinitions() => _provider.GetXmlnsDefinitions();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());

        var field = new TextBox();
        AutomationProperties.SetName(field, "Name");
        var send = new Button { Content = "Send" };
        var label = new TextBlock { Text = "waiting" };
        void Answer() => label.Text = "got: " + field.Text;
        send.Click += (_, _) => Answer();
        // Registered for handled events too, so the TextBox's own key handling cannot hide Enter.
        field.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler((_, e) =>
        {
            if (e.Key == VirtualKey.Enter)
            {
                Answer();
            }
        }), handledEventsToo: true);

        var panel = new StackPanel { Spacing = 8, Padding = new Thickness(12) };
        panel.Children.Add(field);
        panel.Children.Add(send);
        panel.Children.Add(label);
        field.Loaded += (_, _) => field.Focus(FocusState.Programmatic);

        _window = new Window { Title = "s12-winui", Content = panel };
        _window.AppWindow.Resize(new SizeInt32(420, 200));
        // Written before the window can appear, so the driver reads it once it finds the window.
        Write(string.Create(CultureInfo.InvariantCulture, $"launched: process {Environment.ProcessId}; OS {Environment.OSVersion.Version}; process {RuntimeInformation.ProcessArchitecture}; Windows App SDK runtime {RuntimeInfo.AsString}"));
        _window.Activate();
    }

    private void Write(string line) => File.AppendAllText(_log, line + Environment.NewLine);
}
