param(
    [ValidateSet('Status', 'Enable', 'Disable')]
    [string]$Action,
    [string]$Selection
)

$ErrorActionPreference = 'Stop'
$features = @(
    @{ Label = 'Hyper-V'; Short = 'Hyper-V'; About = 'Microsoft VM platform and management tools.'; Feature = 'Microsoft-Hyper-V-All' },
    @{ Label = 'Virtual Machine Platform'; Short = 'Virtual Machine Platform'; About = 'Virtualization layer used by WSL 2.'; Feature = 'VirtualMachinePlatform' },
    @{ Label = 'Windows Hypervisor Platform'; Short = 'Hypervisor Platform'; About = 'Hypervisor API for compatible VM apps.'; Feature = 'HypervisorPlatform' },
    @{ Label = 'WSL optional feature'; Short = 'WSL'; About = 'Windows Subsystem for Linux optional feature.'; Feature = 'Microsoft-Windows-Subsystem-Linux' },
    @{ Label = 'Windows Sandbox'; Short = 'Windows Sandbox'; About = 'Disposable isolated Windows environment.'; Feature = 'Containers-DisposableClientVM' },
    @{ Label = 'Virtualization-based security (VBS)'; Short = 'VBS'; About = 'Isolates security services with a hypervisor.'; Key = 'VBS' },
    @{ Label = 'Memory integrity (HVCI)'; Short = 'Memory integrity'; About = 'Protects kernel code; depends on VBS.'; Key = 'HVCI' },
    @{ Label = 'System-wide Control Flow Guard (CFG)'; Short = 'Control Flow Guard'; About = 'Exploit protection; not a VM feature.'; Key = 'CFG' }
)
$vbsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$hvciPath = "$vbsPath\Scenarios\HypervisorEnforcedCodeIntegrity"

$script:Quit = $false
function Show-HardwareStatus {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $firmware = if ($null -eq $cpu.VirtualizationFirmwareEnabled) { 'Unknown' }
                    elseif ($cpu.VirtualizationFirmwareEnabled) { 'Enabled' }
                    else { 'Disabled' }
    } catch { $firmware = 'Unknown' }
    try {
        $machine = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $hypervisor = if ($null -eq $machine.HypervisorPresent) { 'Unknown' }
                      elseif ($machine.HypervisorPresent) { 'Yes' }
                      else { 'No' }
    } catch { $hypervisor = 'Unknown' }
    Write-Output "Firmware virtualization: $firmware"
    Write-Output "Hypervisor running: $hypervisor"
}
function Read-MenuInput {
    param([string]$Prompt)
    [Console]::Write("${Prompt}: ")
    if ([Console]::IsInputRedirected) {
        $text = [Console]::In.ReadLine()
    } else {
        $buffer = [System.Text.StringBuilder]::new()
        while ($true) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Escape) {
                [Console]::WriteLine()
                $script:Quit = $true
                return
            }
            if ($key.Key -eq [ConsoleKey]::Enter) {
                [Console]::WriteLine()
                break
            }
            if ($key.Key -eq [ConsoleKey]::Backspace -and $buffer.Length -gt 0) {
                [void]$buffer.Remove($buffer.Length - 1, 1)
                [Console]::Write("`b `b")
            } elseif (-not [char]::IsControl($key.KeyChar)) {
                [void]$buffer.Append($key.KeyChar)
                [Console]::Write($key.KeyChar)
            }
        }
        $text = $buffer.ToString()
    }
    if ($null -eq $text -or $text.Trim() -eq 'quit' -or $text -eq [string][char]27) {
        $script:Quit = $true
        return
    }
    return $text
}

function Invoke-Selection {
param([string]$Action, [string]$Selection, [switch]$Confirmed)
if (-not $Action -or -not $Selection) { throw 'Supply both -Action and -Selection.' }
$numbers = [Collections.Generic.SortedSet[int]]::new()
if ($Selection.Trim() -eq 'all') {
    for ($i = 1; $i -le $features.Count; $i++) { [void]$numbers.Add($i) }
} else {
    foreach ($part in ($Selection -split ',')) {
        if ($part -notmatch '^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$') {
            throw "Invalid selection: '$part'. Use numbers or ranges such as 1,3-5,8."
        }
        $first = [int]$Matches[1]
        $last = if ($Matches[2]) { [int]$Matches[2] } else { $first }
        if ($first -lt 1 -or $last -gt $features.Count -or $first -gt $last) {
            throw "Selection out of range: '$part'."
        }
        for ($i = $first; $i -le $last; $i++) { [void]$numbers.Add($i) }
    }
}


$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Action -ne 'Status' -and -not $isAdmin) {
    throw 'Enable/Disable requires an elevated (Run as administrator) console. No changes made.'
}

$selected = @(foreach ($number in $numbers) { $features[$number - 1] })
foreach ($item in $selected) {
    if ($item.Feature) {
        if (-not $isAdmin -and $Action -eq 'Status') {
            $state = 'Requires elevation to query'
        } else {
            try {
                $result = Get-WindowsOptionalFeature -Online -FeatureName $item.Feature -ErrorAction Stop
                if (-not $result) { throw 'Feature not present on this Windows edition' }
                $state = [string]$result.State
            } catch {
                if ($Action -ne 'Status') { throw "Cannot query $($item.Label): $_. No changes made." }
                $state = "Unavailable: $_"
            }
        }
    } elseif ($item.Key -eq 'CFG') {
        try {
            $cfg = (Get-ProcessMitigation -System -ErrorAction Stop).CFG
            $state = switch ($cfg.Enable.ToString()) {
                ON { 'On' }
                OFF { 'Off' }
                NOTSET { 'Default (On)' }
                default { "Unknown ($($cfg.Enable))" }
            }
        } catch {
            if ($Action -ne 'Status') { throw "Cannot query CFG: $_. No changes made." }
            $state = "Unavailable: $_"
        }
    } else {
        $path = if ($item.Key -eq 'VBS') { $vbsPath } else { $hvciPath }
        $name = if ($item.Key -eq 'VBS') { 'EnableVirtualizationBasedSecurity' } else { 'Enabled' }
        $value = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
        $state = if ($null -eq $value) { 'Not configured' }
                 elseif ($value -eq 1) { 'Configured On (restart may be needed)' }
                 else { 'Configured Off (restart may be needed)' }
    }
    Write-Output ("{0}: {1}" -f $item.Label, $state)
}

if ($Action -eq 'Status') { return }

$keys = @($selected | ForEach-Object { $_.Key })
$hvciOn = (Get-ItemProperty -Path $hvciPath -Name Enabled -ErrorAction SilentlyContinue).Enabled -eq 1
$vbsOn = (Get-ItemProperty -Path $vbsPath -Name EnableVirtualizationBasedSecurity -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity -eq 1
if ($Action -eq 'Enable' -and $keys -contains 'HVCI' -and -not $vbsOn -and $keys -notcontains 'VBS') {
    throw 'Memory integrity requires VBS. Select VBS too, or enable VBS first. No changes made.'
}
if ($Action -eq 'Disable' -and $keys -contains 'VBS' -and $hvciOn -and $keys -notcontains 'HVCI') {
    throw 'Memory integrity is enabled. Select it too before disabling VBS. No changes made.'
}
if ($keys -contains 'VBS' -or $keys -contains 'HVCI') {
    $policy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' -ErrorAction SilentlyContinue
    if ($policy -and ($null -ne $policy.EnableVirtualizationBasedSecurity -or $null -ne $policy.HypervisorEnforcedCodeIntegrity)) {
        throw 'VBS/HVCI is managed by policy; refusing to override it. No changes made.'
    }
    if ((Get-ItemProperty $vbsPath -Name Locked -ErrorAction SilentlyContinue).Locked -eq 1 -or
        (Get-ItemProperty $hvciPath -Name Locked -ErrorAction SilentlyContinue).Locked -eq 1) {
        throw 'VBS/HVCI has a UEFI lock; refusing to change it. No changes made.'
    }
}

Write-Output "Requested action: $Action"
if (-not $Confirmed) {
    $confirmation = Read-MenuInput "Type APPLY to $Action only the selected settings"
    if ($script:Quit) { return }
    if ($confirmation -cne 'APPLY') {
        Write-Output 'Cancelled; no changes made.'
        return
    }
}

# HVCI must be disabled before VBS; enabling VBS precedes HVCI.
if ($Action -eq 'Disable') { [array]::Reverse($selected) }
foreach ($item in $selected) {
    try {
        if ($item.Feature) {
            if ($Action -eq 'Enable') {
                Enable-WindowsOptionalFeature -Online -FeatureName $item.Feature -NoRestart -ErrorAction Stop | Out-Null
            } else {
                Disable-WindowsOptionalFeature -Online -FeatureName $item.Feature -NoRestart -ErrorAction Stop | Out-Null
            }
        } elseif ($item.Key -eq 'CFG') {
            if ($Action -eq 'Enable') { Set-ProcessMitigation -System -Enable CFG -ErrorAction Stop }
            else { Set-ProcessMitigation -System -Disable CFG -ErrorAction Stop }
        } else {
            $path = if ($item.Key -eq 'VBS') { $vbsPath } else { $hvciPath }
            $name = if ($item.Key -eq 'VBS') { 'EnableVirtualizationBasedSecurity' } else { 'Enabled' }
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $path -Name $name -Value ([int]($Action -eq 'Enable')) -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        }
        Write-Output "Requested $Action for $($item.Label)."
    } catch {
        throw "Failed on $($item.Label): $_. Remaining selections were not changed; earlier changes may require restart."
    }
}
Write-Output 'Restart Windows to apply feature/VBS/HVCI changes. CFG changes may require restarting affected apps.'
}

function Draw-Tui {
    param([int]$Cursor, $Chosen, [string]$State, [string[]]$Hardware, [string]$Notice, [string]$ConfirmAction)
    $left = 31
    $right = [Math]::Min(60, [Console]::WindowWidth - 38)
    $h = [string][char]0x2500; $v = [string][char]0x2502
    $tl = [string][char]0x250c; $tr = [string][char]0x2510
    $bl = [string][char]0x2514; $br = [string][char]0x2518
    $tm = [string][char]0x252c
    $lm = [string][char]0x251c; $rm = [string][char]0x2524
    $bottomMid = [string][char]0x2534
if ($ConfirmAction -eq 'Admin') {
        $details = @('OPEN ADMINISTRATOR MENU', 'Windows will request UAC approval.', '',
                     'Recheck features in the new window.', '', 'Y open / N cancel / Esc quit')
    } elseif ($ConfirmAction) {
        $targets = if ($Chosen.Count) { @($Chosen) } else { @($Cursor) }
        $details = @("CONFIRM $($ConfirmAction.ToUpperInvariant())", "Target state: $ConfirmAction", '', 'Selected features:')
        $details += @($targets | ForEach-Object { "  $($features[$_].Short)" })
        $details += '', 'Y apply / N cancel / Esc quit'
    } else {
        $target = if ($Chosen.Count) { "$($Chosen.Count) checked" } else { 'highlighted feature' }
        $details = @($features[$Cursor].Label, "State: $State", '', $features[$Cursor].About, '',
                     $Hardware[0], $Hardware[1], '', "Action target: $target", 'U: administrator menu')
    }
    [Console]::Clear()
    [Console]::WriteLine($tl + ($h * ($left + 2)) + $tm + ($h * ($right + 2)) + $tr)
    $rows = [Math]::Max($features.Count, $details.Count)
    for ($i = -1; $i -lt $rows; $i++) {
        if ($i -eq -1) {
            $leftText = 'FEATURES'
            $rightText = 'DETAILS'
        } else {
            $leftText = if ($i -lt $features.Count) {
                $mark = if ($Chosen.Contains($i)) { 'x' } else { ' ' }
                $pointer = if ($i -eq $Cursor) { '>' } else { ' ' }
                "$pointer [$mark] $($features[$i].Short)"
            } else { '' }
            $rightText = if ($i -lt $details.Count) { [string]$details[$i] } else { '' }
        }
        if ($leftText.Length -gt $left) { $leftText = $leftText.Substring(0, $left) }
        if ($rightText.Length -gt $right) { $rightText = $rightText.Substring(0, $right) }
        [Console]::WriteLine($v + ' ' + $leftText.PadRight($left) + ' ' + $v + ' ' + $rightText.PadRight($right) + ' ' + $v)
    }
    [Console]::WriteLine($lm + ($h * ($left + 2)) + $bottomMid + ($h * ($right + 2)) + $rm)
    $footWidth = $left + $right + 3
    $noticeText = $Notice -replace '[\r\n]+', ' '
    $foot = @('Up/Down Navigate  Space/Enter Check  A All  R Refresh',
              'E Enable  D Disable  U Admin  Type quit / Esc Exit',
              $noticeText.Substring(0, [Math]::Min($footWidth, $noticeText.Length)),
              $(if ($noticeText.Length -gt $footWidth) { $noticeText.Substring($footWidth, [Math]::Min($footWidth, $noticeText.Length - $footWidth)) } else { '' }))
    foreach ($line in $foot) {
        $line = [string]$line
        if ($line.Length -gt $footWidth) { $line = $line.Substring(0, $footWidth) }
        [Console]::WriteLine($v + ' ' + $line.PadRight($footWidth) + ' ' + $v)
    }
    [Console]::WriteLine($bl + ($h * ($left + $right + 5)) + $br)
}
function Invoke-Tui {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive mode requires a console. For read-only automation use -Action Status -Selection 1-8.'
    }
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $cursor = 0
    $chosen = [Collections.Generic.SortedSet[int]]::new()
    $states = @{}
    $hardware = @(Show-HardwareStatus)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $notice = 'Check features with Space, then press E or D; no checks means highlighted feature.'
    $quitText = ''
    try {
        while ($true) {
            if ([Console]::WindowWidth -lt 80 -or [Console]::WindowHeight -lt 24) {
                [Console]::Clear()
                [Console]::WriteLine('Resize the console to at least 80 columns by 24 rows. Press Esc to quit.')
                if ([Console]::ReadKey($true).Key -eq [ConsoleKey]::Escape) { break }
                continue
            }
            if (-not $states.ContainsKey($cursor)) {
                try {
                    $line = @(Invoke-Selection -Action Status -Selection ([string]($cursor + 1)))[0]
                    $states[$cursor] = $line.Substring($features[$cursor].Label.Length + 2)
                } catch { $states[$cursor] = "Unavailable: $_" }
            }
            Draw-Tui -Cursor $cursor -Chosen $chosen -State $states[$cursor] -Hardware $hardware -Notice $notice
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Escape) { break }
            if ($key.Key -eq [ConsoleKey]::UpArrow) {
                $cursor = ($cursor + $features.Count - 1) % $features.Count
                $quitText = ''
                continue
            }
            if ($key.Key -eq [ConsoleKey]::DownArrow) {
                $cursor = ($cursor + 1) % $features.Count
                $quitText = ''
                continue
            }
            if ($key.Key -eq [ConsoleKey]::Spacebar -or $key.Key -eq [ConsoleKey]::Enter) {
                if (-not $chosen.Remove($cursor)) { [void]$chosen.Add($cursor) }
                $quitText = ''
                continue
            }
            $letter = $key.KeyChar.ToString().ToUpperInvariant()
            if ($quitText) {
                $candidate = $quitText + $letter.ToLowerInvariant()
                if ('quit'.StartsWith($candidate)) {
                    $quitText = $candidate
                    if ($quitText -eq 'quit') { break }
                    $notice = "Type quit to exit: $quitText"
                    continue
                }
                $quitText = ''
            }
            if ($letter -eq 'Q') { $quitText = 'q'; $notice = 'Type quit to exit: q'; continue }
            if ($letter -eq 'A') {
                if ($chosen.Count -eq $features.Count) { $chosen.Clear() }
                else {
                    $chosen.Clear()
                    for ($i = 0; $i -lt $features.Count; $i++) { [void]$chosen.Add($i) }
                }
                $notice = "$($chosen.Count) checked. E/D targets checked features; none targets the highlighted feature."
                continue
            }
            if ($letter -eq 'R') {
                $states.Clear()
                $hardware = @(Show-HardwareStatus)
                $notice = 'Status refreshed.'
                continue
            }
            if ($letter -ne 'U' -and $letter -ne 'E' -and $letter -ne 'D') { continue }
            if ($letter -eq 'U' -or -not $isAdmin) {
                if ($isAdmin) { $notice = 'Already running as administrator.'; continue }
                Draw-Tui -Cursor $cursor -Chosen $chosen -State $states[$cursor] -Hardware $hardware -Notice 'Opening a new elevated menu requires Windows approval.' -ConfirmAction Admin
                $answer = [Console]::ReadKey($true)
                if ($answer.Key -eq [ConsoleKey]::Escape) { break }
                if ($answer.KeyChar.ToString().ToUpperInvariant() -ne 'Y') { $notice = 'Cancelled; no changes made.'; continue }
                try {
                    [Console]::Clear()
                    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
                    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList $arguments -Wait -ErrorAction Stop
                    break
                } catch { $notice = "Elevation cancelled or unavailable: $_"; continue }
            }
            $mode = if ($letter -eq 'E') { 'Enable' } else { 'Disable' }
            $targets = [Collections.Generic.List[int]]::new()
            if ($chosen.Count) { foreach ($index in $chosen) { $targets.Add($index + 1) } }
            else { $targets.Add($cursor + 1) }
            $selection = $targets -join ','
            Draw-Tui -Cursor $cursor -Chosen $chosen -State $states[$cursor] -Hardware $hardware -Notice "Confirm $mode for $($targets.Count) shown feature(s)." -ConfirmAction $mode
            $answer = [Console]::ReadKey($true)
            if ($answer.Key -eq [ConsoleKey]::Escape) { break }
            if ($answer.KeyChar.ToString().ToUpperInvariant() -ne 'Y') { $notice = 'Cancelled; no changes made.'; continue }
            $notice = "Applying $mode..."
            Draw-Tui -Cursor $cursor -Chosen $chosen -State $states[$cursor] -Hardware $hardware -Notice $notice
            try {
                $result = @(Invoke-Selection -Action $mode -Selection $selection -Confirmed)
                $notice = if ($result.Count) { [string]$result[-1] } else { 'No changes made.' }
            } catch { $notice = "Error: $_" }
            $states.Clear()
            $hardware = @(Show-HardwareStatus)
        }
    } finally {
        [Console]::OutputEncoding = $oldEncoding
        [Console]::Clear()
    }
}

if ($PSBoundParameters.Count) {
    Show-HardwareStatus
    Invoke-Selection -Action $Action -Selection $Selection
} else {
    Invoke-Tui
}
