#!/usr/bin/env pwsh
<#
.SYNOPSIS
Settles whether a job on this runner can drive a WinUI 3 window through UI Automation and keys.

.DESCRIPTION
Prints the session and OS build the job runs in, starts the WinUI 3 window built from
probes/winui in its own process, finds it among the desktop's windows by its title and
process, and drives it through FlaUI's UIA3 client: finds the field by its control type, sets
it through the Value pattern, presses the button through the Invoke pattern and reads the
label, types into the field with synthesised keystrokes and reads the label again, then checks
keyboard completeness: Tab moves focus from the field to the Send button, Space activates it,
and the label shows the activation.

Synthesised keys reach only the foreground window. Before typing, the focused element is read;
when another process holds it, that element's top-level window is closed through UI
Automation's Window pattern and focus is asserted to be the application's, or the probe fails
naming the holding process and window.

Windows PowerShell 5.1, because FlaUI's net48 assemblies load into it on every image. FlaUI
5.0.0 and its interop come from nuget.org, each checked against the SHA-256 of the package
NuGet's catalogue hashes, and load from one directory with each dependency before its
dependants. Every wait is bounded; a failure prints the window's own log and its exit code if
it has exited.

One line, stage: <name>, is printed as each stage is entered, so the log shows the last stage
reached. The stages, in order: runtime and build (the workflow's steps), launch (this driver's
own machinery: the package fetch and load), start (printed immediately before the window's
process is started), uia-root, controls, patterns, keys and keyboard-completeness. An exited
window's exit code is printed as: window process exit code: 0x<hex>.

Reading a failure (the decision record's section 9; hosted/classify.sh applies it to the logs
of the two x64 legs). The matrix runs the x64 build on windows-2025, the arm64 build on
windows-11-arm, and the x64 build on windows-11-arm under Windows 11's x64 emulation with the
x64 runtime installed: the x64 control on an OS the Windows App SDK lists. Every leg builds
self-contained, so the legs differ only in architecture and OS.
  (i) A probe defect: any leg whose last stage is runtime, build or launch. That leg is fixed
      and run again before anything is classified.
  From start on, a failure is the application's outcome at its stage, whether the window's
  process is still running or has exited.
  windows-2025's own result decides the record. Its PASS keeps the record as written, whatever
  the other legs show; an emulated x64 failure with windows-2025 passing is an emulation
  finding, never a fork.
  When windows-2025 fails at stage S, from start on, the emulated x64 leg decides the
  attribution:
  (ii) An OS cause: the emulated leg passes S. This leads to the owner's fork as the record
      states it.
  (iii) A WinUI 3 cause: the emulated leg fails at S, its window running or exited. This is a
      fork for the owner as well. No hosted instrumented x64 run exists, and a self-hosted
      Windows 11 machine cures nothing.
  Unattributed: the emulated leg fails at an earlier stage, from start on. The record states
      windows-2025's failure at S with both logs, and the fork goes to the owner without an
      attribution.
  An emulated leg whose last stage is runtime, build or launch is (i) for that leg: run again.
The arm64 leg's role is unchanged: it settles the arm64 keyboard line.

.PARAMETER Application
The built S12WinUI.exe.

.OUTPUTS
One line per check; the last is PASS. Any failure is a terminating error.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateScript({ Test-Path -Path $_ -PathType Leaf })][string]$Application
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$process = Get-Process -Id $PID
$build = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
"session $($process.SessionId); interactive $([Environment]::UserInteractive); user $([Environment]::UserName)"
"OS $($build.ProductName) $($build.DisplayVersion) build $($build.CurrentBuild).$($build.UBR); $env:PROCESSOR_ARCHITECTURE"
'stage: launch'

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

function Wait-Focus {
  [CmdletBinding()]
  [OutputType([FlaUI.Core.AutomationElements.AutomationElement])]
  param(
    [Parameter(Mandatory)][FlaUI.UIA3.UIA3Automation]$Automation,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ButtonName,
    [Parameter(Mandatory)][int]$ProcessId,
    [ValidateRange(1, 300)][int]$Seconds = 30
  )
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $focused = $Automation.FocusedElement()
    if ($focused.ControlType -eq [FlaUI.Core.Definitions.ControlType]::Button -and $focused.Name -eq $ButtonName -and $focused.Properties.ProcessId.Value -eq $ProcessId) {
      return $focused
    }
    Start-Sleep -Milliseconds 200
  }
  throw "focus not on the '$ButtonName' button of process $ProcessId within $Seconds s: $(Get-Holder -Element $Automation.FocusedElement())"
}

function Get-Holder {
  [CmdletBinding()]
  [OutputType([string])]
  param([Parameter(Mandatory)][FlaUI.Core.AutomationElements.AutomationElement]$Element)
  $holder = $Element.Properties.ProcessId.Value
  $name = (Get-Process -Id $holder -ErrorAction Ignore).ProcessName # gone if it exited meanwhile
  "$($Element.ControlType) name '$($Element.Name)' process $holder ($name)"
}

$log = Join-Path -Path $work -ChildPath 'window.log'
'stage: start'
$app = Start-Process -FilePath $Application -ArgumentList @("`"$log`"") -PassThru
$automation = New-Object -TypeName FlaUI.UIA3.UIA3Automation
try {
  'stage: uia-root'
  $cf = $automation.ConditionFactory
  $desktop = $automation.GetDesktop()
  $titled = $cf.ByName('s12-winui').And($cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Window)).And($cf.ByProcessId($app.Id))
  $deadline = (Get-Date).AddSeconds(60)
  $form = $null
  while ($null -eq $form -and (Get-Date) -lt $deadline -and -not $app.HasExited) {
    $form = $desktop.FindFirstChild($titled)
    if ($null -eq $form) { Start-Sleep -Milliseconds 200 }
  }
  if ($app.HasExited) { throw ('the window process exited with 0x{0:X8} before its window appeared' -f $app.ExitCode) }
  if ($null -eq $form) { throw "no window titled s12-winui of process $($app.Id) within 60 s" }
  "window: found through UIA3; process $($form.Properties.ProcessId.Value) (the application's is $($app.Id)); class $($form.ClassName)"
  Get-Content -Path $log
  foreach ($element in $form.FindAllDescendants()) {
    "UIA3 element: $($element.ControlType) name '$($element.Name)' class $($element.ClassName)"
  }

  'stage: controls'
  $edit = Wait-Element -Root $form -Condition $cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Edit) -What 'Edit control'
  $send = Wait-Element -Root $form -Condition $cf.ByName('Send').And($cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Button)) -What 'Send button'

  'stage: patterns'
  $edit.Patterns.Value.Pattern.SetValue('viauia')
  $send.Patterns.Invoke.Pattern.Invoke()
  $null = Wait-Element -Root $form -Condition $cf.ByName('got: viauia').And($cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Text)) -What "Text reading 'got: viauia'"
  'label: got: viauia (Value and Invoke patterns)'

  'stage: keys'
  $edit.Patterns.Value.Pattern.SetValue('')
  $form.SetForeground()
  $edit.Focus()
  $focused = $automation.FocusedElement()
  "focus before keys: $(Get-Holder -Element $focused)"
  if ($focused.Properties.ProcessId.Value -ne $app.Id) {
    $walker = $automation.TreeWalkerFactory.GetControlViewWalker()
    $top = $focused
    for ($parent = $walker.GetParent($top); $null -ne $parent -and -not $parent.Equals($desktop); $parent = $walker.GetParent($top)) { $top = $parent }
    $foreign = "window '$($top.Name)' of $(Get-Holder -Element $top)"
    if (-not $top.Patterns.Window.IsSupported) { throw "foreground held by $foreign, which offers no Window pattern" }
    "closing $foreign through the Window pattern"
    $top.Patterns.Window.Pattern.Close()
    $deadline = (Get-Date).AddSeconds(30)
    do {
      Start-Sleep -Milliseconds 200
      $form.SetForeground()
      $edit.Focus()
      $focused = $automation.FocusedElement()
    } while ($focused.Properties.ProcessId.Value -ne $app.Id -and (Get-Date) -lt $deadline)
    "focus after closing: $(Get-Holder -Element $focused)"
    if ($focused.Properties.ProcessId.Value -ne $app.Id) { throw "foreground still not the application's within 30 s of closing $foreign" }
  }
  [FlaUI.Core.Input.Keyboard]::Type('keys')
  [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort[]]@([FlaUI.Core.WindowsAPI.VirtualKeyShort]::ENTER))
  try {
    $null = Wait-Element -Root $form -Condition $cf.ByName('got: keys').And($cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Text)) -What "Text reading 'got: keys'"
  }
  catch {
    "focus after keys: $(Get-Holder -Element $automation.FocusedElement())"
    "field holds: '$($edit.Patterns.Value.Pattern.Value.Value)'"
    throw
  }
  'label: got: keys (synthesised keystrokes)'

  'stage: keyboard-completeness'
  # The label still reads 'got: keys'; a different value tells this activation from the Enter above.
  $edit.Patterns.Value.Pattern.SetValue('tabbed')
  $edit.Focus()
  [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort[]]@([FlaUI.Core.WindowsAPI.VirtualKeyShort]::TAB))
  $focused = Wait-Focus -Automation $automation -ButtonName 'Send' -ProcessId $app.Id
  "focus after Tab: $(Get-Holder -Element $focused)"
  [FlaUI.Core.Input.Keyboard]::Type([FlaUI.Core.WindowsAPI.VirtualKeyShort[]]@([FlaUI.Core.WindowsAPI.VirtualKeyShort]::SPACE))
  $null = Wait-Element -Root $form -Condition $cf.ByName('got: tabbed').And($cf.ByControlType([FlaUI.Core.Definitions.ControlType]::Text)) -What "Text reading 'got: tabbed'"
  'label: got: tabbed (Tab to Send, Space)'
  'PASS windows-uia: UIA3 found the WinUI 3 controls by type and drove them, synthesised keys reached the window, and Tab and Space operated it'
}
catch {
  if ($app.HasExited) { 'window process exit code: 0x{0:X8}' -f $app.ExitCode }
  if (Test-Path -Path $log) { '--- window.log'; Get-Content -Path $log }
  throw
}
finally {
  $automation.Dispose()
  Stop-Process -Id $app.Id -ErrorAction Ignore # already gone if it exited
}
