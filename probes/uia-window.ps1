#!/usr/bin/env pwsh
<#
.SYNOPSIS
A window titled s12-uia whose label answers what is typed into its field.

.DESCRIPTION
WPF under Windows PowerShell 5.1, which ships it on every Windows edition the
probe runs on. WPF serves UI Automation from the window's own process through
its automation peers, as WinUI 3 does, rather than through the Win32 and MSAA
proxies a client builds for Windows Forms controls. The window is the
application under test of windows-uia.ps1, run in its own process as an
application would be.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework

$window = New-Object -TypeName System.Windows.Window -Property @{ Title = 's12-uia'; Width = 420; Height = 200 }
$panel = New-Object -TypeName System.Windows.Controls.StackPanel
$field = New-Object -TypeName System.Windows.Controls.TextBox
[System.Windows.Automation.AutomationProperties]::SetName($field, 'Name')
$button = New-Object -TypeName System.Windows.Controls.Button -Property @{ Content = 'Send' }
$label = New-Object -TypeName System.Windows.Controls.TextBlock -Property @{ Text = 'waiting' }
$answer = { $label.Text = 'got: ' + $field.Text }
$button.Add_Click($answer)
# In a WPF handler $_ is the event's arguments.
$field.Add_KeyDown({ if ($_.Key -eq [System.Windows.Input.Key]::Return) { & $answer } })
$null = $panel.Children.Add($field)
$null = $panel.Children.Add($button)
$null = $panel.Children.Add($label)
$window.Content = $panel
$window.Add_ContentRendered({ $null = $window.Activate(); $null = $field.Focus() })
$null = $window.ShowDialog()
