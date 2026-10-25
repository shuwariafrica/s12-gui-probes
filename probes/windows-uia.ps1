#!/usr/bin/env pwsh
<#
.SYNOPSIS
Settles whether a job on this runner has an interactive desktop that UI tests can drive.

.DESCRIPTION
Prints the session the job runs in, then starts uia-window.ps1 in its own
process and drives its window through FlaUI's UIA3 client, the COM UI
Automation client a .NET UI test uses: finds the field by its control type,
sets it through the Value pattern, presses the button through the Invoke
pattern and reads the label, then types into the field with synthesised
keystrokes, which reach only a foreground window on an input desktop, and
reads the label again. Before that it logs the window's children as the
managed System.Windows.Automation client reports them, which in Windows
PowerShell 5.1 gives every Windows Forms control as a Pane.

FlaUI 5.0.0 and its interop come from nuget.org, each checked against the
SHA-256 of the package NuGet's catalogue hashes, and load from one directory
with each dependency before its dependants: LoadFrom resolves a reference from
the referring assembly's directory, and Windows PowerShell 5.1's Add-Type -Path
enumerates an assembly's types as it loads it. Every wait is bounded; a failure
prints the window process's own output and any type that failed to load.

.OUTPUTS
One line per check; the last is PASS. Any failure is a terminating error.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$packages = @(
  @{ Id = 'flaui.core'; Version = '5.0.0'; Sha256 = '191cc65ea82036b77f1872e6d4ebf743d3d120895bba2fa5248d126cd6f568a7'; Dll = 'lib/net48/FlaUI.Core.dll' },
  @{ Id = 'flaui.uia3'; Version = '5.0.0'; Sha256 = 'd5d2e083539a04bf6c9053781dfd47332854a76faeb8e9c3c68cc82109f711f2'; Dll = 'lib/net48/FlaUI.UIA3.dll' },
  @{ Id = 'interop.uiautomationclient'; Version = '10.19041.0'; Sha256 = '0d2ed17db2cb13a262f0580ab992db87577651c25a9899053df4114b4d9ff3b1'; Dll = 'lib/net45/Interop.UIAutomationClient.dll' }
)
$work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 's12-uia'
$lib = Join-Path -Path $work -ChildPath 'lib'
$null = New-Item -ItemType Directory -Path $lib -Force
foreach ($package in $packages) {
  $archive = Join-Path -Path $work -ChildPath "$($package.Id).$($package.Version).zip"
  $uri = "https://api.nuget.org/v3-flatcontainer/$($package.Id)/$($package.Version)/$($package.Id).$($package.Version).nupkg"
  Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing -TimeoutSec 120
  $sum = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($sum -ne $package.Sha256) { throw "$($package.Id) $($package.Version): SHA-256 $sum, expected $($package.Sha256)" }
  $unpacked = Join-Path -Path $work -ChildPath $package.Id
  Expand-Archive -Path $archive -DestinationPath $unpacked -Force
  Copy-Item -Path (Join-Path -Path $unpacked -ChildPath $package.Dll) -Destination $lib
}
try {
  foreach ($name in @('Interop.UIAutomationClient.dll', 'FlaUI.Core.dll', 'FlaUI.UIA3.dll')) {
    $null = [System.Reflection.Assembly]::LoadFrom((Join-Path -Path $lib -ChildPath $name))
  }
  $null = [FlaUI.UIA3.UIA3Automation].Assembly.GetTypes()
}
catch {
  for ($e = $_.Exception; $null -ne $e; $e = $e.InnerException) {
    if ($e -is [System.Reflection.ReflectionTypeLoadException]) {
      $e.LoaderExceptions | ForEach-Object { "type load: $($_.Message)" }
    }
  }
  throw
}

function Wait-Element {
  [CmdletBinding()]
  [OutputType([FlaUI.Core.AutomationElements.AutomationElement])]
  param(
    [Parameter(Mandatory)][FlaUI.Core.AutomationElements.AutomationElement]$Root,
    [Parameter(Mandatory)][FlaUI.Core.Conditions.ConditionBase]$Condition,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$What,
    [ValidateRange(1, 300)][int]$Seconds = 30
  )
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $found = $Root.FindFirstDescendant($Condition)
    if ($null -ne $found) { return $found }
    Start-Sleep -Milliseconds 200
  }
  throw "no $What within $Seconds s"
}

$process = Get-Process -Id $PID
"session $($process.SessionId); interactive $([Environment]::UserInteractive); user $([Environment]::UserName)"

$window = Join-Path -Path $PSScriptRoot -ChildPath 'uia-window.ps1'
$out = Join-Path -Path $work -ChildPath 'window.out'
$err = Join-Path -Path $work -ChildPath 'window.err'
$app = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $window) `
  -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
$automation = New-Object -TypeName FlaUI.UIA3.UIA3Automation
try {
  $cf = $automation.ConditionFactory
  $form = [FlaUI.Core.Application]::Attach($app.Id).GetMainWindow($automation, [TimeSpan]::FromSeconds(30))
  if ($null -eq $form) { throw 'no main window within 30 s' }
  "window: found through UIA3; process $($form.Properties.ProcessId.Value) (the application's is $($app.Id)); class $($form.ClassName)"

  $managed = [System.Windows.Automation.AutomationElement]::FromHandle($form.Properties.NativeWindowHandle.Value)
  $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
  $child = $walker.GetFirstChild($managed)
  while ($null -ne $child) {
    "managed client child: $($child.Current.ControlType.ProgrammaticName) name '$($child.Current.Name)' class $($child.Current.ClassName)"
    $child = $walker.GetNextSibling($child)
  }
  foreach ($child in $form.FindAllChildren()) {
    "UIA3 child: $($child.ControlType) name '$($child.Name)' class $($child.ClassName)"
  }

  $edit = Wait-Element -Root $form -Condition $cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Edit) -What 'Edit control'
  $edit.Patterns.Value.Pattern.SetValue('viauia')
  $send = Wait-Element -Root $form -Condition $cf.ByName('Send').And($cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Button)) -What 'Send button'
  $send.Patterns.Invoke.Pattern.Invoke()
  $null = Wait-Element -Root $form -Condition $cf.ByName('got: viauia') -What "label reading 'got: viauia'"
  'label: got: viauia (Value and Invoke patterns)'

  $edit.Patterns.Value.Pattern.SetValue('')
  $edit.Focus()
  [FlaUI.Core.Input.Keyboard]::Type('keys')
  [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort[]]@([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER))
  $null = Wait-Element -Root $form -Condition $cf.ByName('got: keys') -What "label reading 'got: keys'"
  'label: got: keys (synthesised keystrokes)'
  'PASS windows-uia: UIA3 found the controls by type and drove them, and synthesised keys reached the window'
}
catch {
  foreach ($log in @($out, $err)) {
    if (Test-Path -Path $log) { "--- $(Split-Path -Path $log -Leaf)"; Get-Content -Path $log }
  }
  throw
}
finally {
  $automation.Dispose()
  Stop-Process -Id $app.Id -ErrorAction Ignore # already gone when the window closed itself
}
