#!/usr/bin/env pwsh
<#
.SYNOPSIS
Settles whether a job on this runner has an interactive desktop that UI tests can drive.

.DESCRIPTION
Prints the session the job runs in, then starts uia-window.ps1 in its own
process, finds its window through UI Automation, sets its field through the
Value pattern, presses its button through the Invoke pattern and reads its
label; then types into the field with synthesised keystrokes, which reach only
a foreground window on an input desktop, and reads the label again. Windows
PowerShell 5.1, because UIAutomationClient ships with the .NET Framework on
every Windows edition.

.OUTPUTS
One line per check; the last is PASS. Any failure is a terminating error.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

function Wait-AutomationElement {
  [CmdletBinding()]
  [OutputType([System.Windows.Automation.AutomationElement])]
  param(
    [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Root,
    [Parameter(Mandatory)][System.Windows.Automation.Condition]$Condition,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$What,
    [System.Windows.Automation.TreeScope]$Scope = [System.Windows.Automation.TreeScope]::Descendants,
    [ValidateRange(1, 300)][int]$Seconds = 30
  )
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $found = $Root.FindFirst($Scope, $Condition)
    if ($null -ne $found) { return $found }
    Start-Sleep -Milliseconds 200
  }
  throw "no $What within $Seconds s"
}

function Wait-LabelText {
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory)][System.Windows.Automation.AutomationElement]$Window,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Expected
  )
  $condition = New-Object -TypeName System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::NameProperty, $Expected)
  $null = Wait-AutomationElement -Root $Window -Condition $condition -What "label reading '$Expected'"
  "label: $Expected"
}

$process = Get-Process -Id $PID
"session $($process.SessionId); interactive $([Environment]::UserInteractive); user $([Environment]::UserName)"

$window = Join-Path -Path $PSScriptRoot -ChildPath 'uia-window.ps1'
$app = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $window) -PassThru
try {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  # The window is a child of the desktop; its title bar, a descendant, carries the same name.
  $titled = New-Object -TypeName System.Windows.Automation.AndCondition -ArgumentList @(
    (New-Object -TypeName System.Windows.Automation.PropertyCondition -ArgumentList @(
      [System.Windows.Automation.AutomationElement]::NameProperty, 's12-uia')),
    (New-Object -TypeName System.Windows.Automation.PropertyCondition -ArgumentList @(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)))
  $form = Wait-AutomationElement -Root $root -Condition $titled -Scope Children -What 'window titled s12-uia on this desktop'
  'window: found through UI Automation'
  "window: process $($form.Current.ProcessId) (the application's is $($app.Id)); class $($form.Current.ClassName)"
  # What UI Automation exposes under the window, in the raw view, before any control is sought.
  $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
  $child = $walker.GetFirstChild($form)
  while ($null -ne $child) {
    "raw child: $($child.Current.ControlType.ProgrammaticName) name '$($child.Current.Name)' class $($child.Current.ClassName) id '$($child.Current.AutomationId)'"
    $child = $walker.GetNextSibling($child)
  }

  $editCondition = New-Object -TypeName System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $edit = Wait-AutomationElement -Root $form -Condition $editCondition -What 'edit field'
  $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('viauia')
  $buttonCondition = New-Object -TypeName System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::NameProperty, 'Send')
  $send = Wait-AutomationElement -Root $form -Condition $buttonCondition -What 'Send button'
  $send.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  Wait-LabelText -Window $form -Expected 'got: viauia'

  $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('')
  $edit.SetFocus()
  [System.Windows.Forms.SendKeys]::SendWait('keys{ENTER}')
  Wait-LabelText -Window $form -Expected 'got: keys'
  'PASS windows-uia: UI Automation drove the window, and synthesised keys reached it'
}
finally {
  Stop-Process -Id $app.Id -ErrorAction Ignore # already gone when the window closed itself
}
