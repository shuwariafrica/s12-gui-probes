#!/usr/bin/env pwsh
<#
.SYNOPSIS
A window titled s12-uia whose label answers what is typed into its field.

.DESCRIPTION
Windows Forms under Windows PowerShell 5.1, which ships it on every Windows
edition the probe runs on. The window is the application under test of
windows-uia.ps1, run in its own process as an application would be.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object -TypeName System.Windows.Forms.Form -Property @{ Text = 's12-uia'; Width = 420; Height = 180 }
$field = New-Object -TypeName System.Windows.Forms.TextBox -Property @{ Name = 'name'; AccessibleName = 'Name'; Top = 10; Left = 10; Width = 380 }
$button = New-Object -TypeName System.Windows.Forms.Button -Property @{ Text = 'Send'; Top = 45; Left = 10 }
$label = New-Object -TypeName System.Windows.Forms.Label -Property @{ Name = 'out'; Text = 'waiting'; Top = 85; Left = 10; Width = 380 }
$answer = { $label.Text = 'got: ' + $field.Text }
$button.Add_Click($answer)
# In a Windows Forms handler $_ is the event's arguments.
$field.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { & $answer } })
$form.Controls.AddRange(@($field, $button, $label))
$form.Add_Shown({ $form.Activate(); $field.Focus() })
[System.Windows.Forms.Application]::Run($form)
