#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory=$false, Position=0)]
    [ValidateSet("Enable", "Disable")]
    [string]$Action
)

# --- Functions ---

function Get-VBSStatus {
    $vbsKey = "HKLM:\System\CurrentControlSet\Control\DeviceGuard"
    $hvciKey = "HKLM:\System\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    
    $vbsEnabled = 0
    $hvciEnabled = 0

    if (Test-Path $vbsKey) {
        $val = Get-ItemProperty -Path $vbsKey -Name "EnableVirtualizationBasedSecurity" -ErrorAction SilentlyContinue
        if ($null -ne $val) { $vbsEnabled = $val.EnableVirtualizationBasedSecurity }
    }
    if (Test-Path $hvciKey) {
        $val = Get-ItemProperty -Path $hvciKey -Name "Enabled" -ErrorAction SilentlyContinue
        if ($null -ne $val) { $hvciEnabled = $val.Enabled }
    }

    return @{
        VBSEnabled = ($vbsEnabled -eq 1)
        HVCIEnabled = ($hvciEnabled -eq 1)
    }
}

function Show-Status {
    Write-Host "`n--- System Status ---" -ForegroundColor Cyan
    $vbs = Get-VBSStatus
    $vbsColor = if ($vbs.VBSEnabled) { "Yellow" } else { "Gray" }
    $hvciColor = if ($vbs.HVCIEnabled) { "Yellow" } else { "Gray" }
    
    Write-Host "VBS (Virtualization-Based Security): $(if($vbs.VBSEnabled){'Enabled'}else{'Disabled'})" -ForegroundColor $vbsColor
    Write-Host "HVCI (Memory Integrity): $(if($vbs.HVCIEnabled){'Enabled'}else{'Disabled'})" -ForegroundColor $hvciColor
    
    if ($vbs.VBSEnabled -or $vbs.HVCIEnabled) {
        Write-Host "Note: VBS/HVCI is active and may block some virtualization software." -ForegroundColor Yellow
    }

    $feats = @('Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'WindowsHypervisorPlatform')
    Write-Host "`n--- Windows Features ---" -ForegroundColor Cyan
    foreach ($f in $feats) {
        $r = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if ($r) {
            $color = if ($r.State -eq 'Enabled') { 'Green' } else { 'Gray' }
            Write-Host "$($f.PadRight(30)): $($r.State)" -ForegroundColor $color
        }
    }
}

function Invoke-Toggle {
    param([string]$TargetAction)
    
    $feats = @('Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'WindowsHypervisorPlatform')
    $restartRequired = $false

    Write-Host "`nUpdating features to $TargetAction state..." -ForegroundColor Yellow
    
    foreach ($f in $feats) {
        $r = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if (-not $r) { continue }

        if ($TargetAction -eq "Enable" -and $r.State -ne "Enabled") {
            Write-Host "Enabling $f..." -NoNewline
            Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Host " Done." -ForegroundColor Green
            $restartRequired = $true
        }
        elseif ($TargetAction -eq "Disable" -and $r.State -eq "Enabled") {
            Write-Host "Disabling $f..." -NoNewline
            Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Host " Done." -ForegroundColor Green
            $restartRequired = $true
        }
    }

    if ($restartRequired) {
        Write-Host "`n[!] Features updated. A restart is required to apply changes." -ForegroundColor Cyan
    } else {
        Write-Host "`n[+] No changes were necessary." -ForegroundColor Green
    }
}

function Exit-WithCountdown {
    Write-Host ""
    for ($i = 3; $i -gt 0; $i--) {
        Write-Host "`rExiting in $i seconds... " -NoNewline -ForegroundColor Gray
        Start-Sleep -Seconds 1
    }
    Write-Host "`rExiting now.           " -ForegroundColor Gray
    exit
}

# --- Main Logic ---

Clear-Host
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "   Windows Virtualization Manager" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

Show-Status

if (-not $Action) {
    Write-Host "`n--- Interactive Menu ---" -ForegroundColor Cyan
    Write-Host "1. Enable all features"
    Write-Host "2. Disable all features"
    Write-Host "3. Exit"
    
    $choice = Read-Host "`nSelect an option (1-3)"
    switch ($choice) {
        "1" { $Action = "Enable" }
        "2" { $Action = "Disable" }
        "3" { Exit-WithCountdown }
        default { 
            Write-Host "Invalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 1
            # Re-run logic without recursion if possible, or just exit
            Write-Host "Restarting script..."
            Start-Process powershell.exe -ArgumentList "-File `"$PSCommandPath`"" -Verb RunAs
            exit
        }
    }
}

Invoke-Toggle -TargetAction $Action
Exit-WithCountdown
