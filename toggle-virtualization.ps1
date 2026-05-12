﻿#Requires -RunAsAdministrator

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

function Get-SecurityStatus {
    $vbs = Get-VBSStatus
    
    $cfgStatus = "Unknown"
    $depStatus = "Unknown"
    $aslrStatus = "Unknown"

    try {
        $mitigation = Get-ProcessMitigation -System
        $cfgStatus = $mitigation.CFG.Enable
        $depStatus = $mitigation.DEP.Enable
        $aslrStatus = $mitigation.ASLR.BottomUp
    } catch {
        Write-Debug "Failed to get process mitigations: $_"
    }

    return @{
        VBSEnabled  = $vbs.VBSEnabled
        HVCIEnabled = $vbs.HVCIEnabled
        CFGStatus   = $cfgStatus
        DEPStatus   = $depStatus
        ASLRStatus  = $aslrStatus
    }
}

function Get-HardwareStatus {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $sys = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1

    return @{
        BIOSVirtualizationEnabled = $cpu.VirtualizationFirmwareEnabled
        HypervisorPresent = $sys.HypervisorPresent
    }
}

function Show-Status {
    Write-Host "`n--- System Status ---" -ForegroundColor Cyan
    $hw = Get-HardwareStatus
    $sec = Get-SecurityStatus

    $biosColor = if ($hw.BIOSVirtualizationEnabled) { "Green" } else { "Red" }
    $hypColor = if ($hw.HypervisorPresent) { "Green" } else { "Gray" }
    $vbsColor = if ($sec.VBSEnabled) { "Yellow" } else { "Gray" }
    $hvciColor = if ($sec.HVCIEnabled) { "Yellow" } else { "Gray" }
    $cfgColor = if ($sec.CFGStatus -eq "ON") { "Yellow" } else { "Gray" }
    $depColor = if ($sec.DEPStatus -eq "ON") { "Yellow" } else { "Gray" }
    
    Write-Host "BIOS Virtualization: $(if($hw.BIOSVirtualizationEnabled){'Enabled'}else{'Disabled/Unsupported'})" -ForegroundColor $biosColor
    Write-Host "Hypervisor Present:  $(if($hw.HypervisorPresent){'Yes'}else{'No'})" -ForegroundColor $hypColor
    Write-Host "VBS (Security):      $(if($sec.VBSEnabled){'Enabled'}else{'Disabled'})" -ForegroundColor $vbsColor
    Write-Host "HVCI (Mem Integrity):$(if($sec.HVCIEnabled){'Enabled'}else{'Disabled'})" -ForegroundColor $hvciColor
    Write-Host "CFG (Control Flow):  $($sec.CFGStatus)" -ForegroundColor $cfgColor
    Write-Host "DEP (Exploit Prot):  $($sec.DEPStatus)" -ForegroundColor $depColor
    
    if ($sec.VBSEnabled -or $sec.HVCIEnabled -or $sec.CFGStatus -eq "ON" -or $sec.DEPStatus -eq "ON" -or $sec.ASLRStatus -eq "ON") {
        Write-Host "Note: Security features are active and may affect performance or compatibility." -ForegroundColor Yellow
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

    return $restartRequired
}

function Request-Restart {
    Write-Host "`nA system restart is required to apply changes." -ForegroundColor Yellow
    $choice = Read-Host "Would you like to restart now? (Y/N)"
    if ($choice -match "^[Yy]") {
        Write-Host "Restarting system..." -ForegroundColor Cyan
        Restart-Computer -Force
    } else {
        Write-Host "Please remember to restart your computer later to apply changes." -ForegroundColor Gray
    }
}

function Show-GranularMenu {
    $anyChanges = $false
    while ($true) {
        Clear-Host
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "      Granular Feature Toggle" -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan
        
        $feats = @('Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'WindowsHypervisorPlatform')
        $featureStates = @()

        Write-Host "`n--- Current Status ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $feats.Count; $i++) {
            $f = $feats[$i]
            $r = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
            $state = if ($r) { $r.State } else { "Not Found" }
            $color = if ($state -eq 'Enabled') { 'Green' } else { 'Gray' }
            
            Write-Host "$($i + 1). $($f.PadRight(30)): $state" -ForegroundColor $color
            $featureStates += [PSCustomObject]@{
                Index = $i + 1
                Name = $f
                State = $state
            }
        }
        
        Write-Host "$($feats.Count + 1). Back to Main Menu"
        
        $choice = Read-Host "`nSelect a feature to toggle (1-$($feats.Count + 1))"
        
        if ($choice -eq ($feats.Count + 1).ToString() -or $choice -eq "") {
            if ($anyChanges) {
                Request-Restart
            }
            return
        }
        
        $selected = $featureStates | Where-Object { $_.Index -eq $choice }
        if ($selected) {
            $targetAction = if ($selected.State -eq 'Enabled') { "Disable" } else { "Enable" }
            Write-Host "`nChanging $($selected.Name) to $targetAction state..." -ForegroundColor Yellow
            
            if ($targetAction -eq "Enable") {
                Enable-WindowsOptionalFeature -Online -FeatureName $selected.Name -NoRestart -ErrorAction SilentlyContinue | Out-Null
            } else {
                Disable-WindowsOptionalFeature -Online -FeatureName $selected.Name -NoRestart -ErrorAction SilentlyContinue | Out-Null
            }
            
            $anyChanges = $true
            Write-Host "Done. A restart is required to apply changes." -ForegroundColor Green
            Start-Sleep -Seconds 2
        } else {
            Write-Host "Invalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

function Show-SecurityMenu {
    $anyChanges = $false
    while ($true) {
        Clear-Host
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "      Security Optimizations" -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan
        
        $sec = Get-SecurityStatus
        
        $hvciColor = if ($sec.HVCIEnabled) { "Green" } else { "Gray" }
        $cfgColor = if ($sec.CFGStatus -eq "ON") { "Green" } else { "Gray" }
        $depColor = if ($sec.DEPStatus -eq "ON") { "Green" } else { "Gray" }
        $aslrColor = if ($sec.ASLRStatus -eq "ON") { "Green" } else { "Gray" }
        
        Write-Host "`n--- Current Status ---" -ForegroundColor Cyan
        Write-Host "1. Memory Integrity (HVCI): $(if($sec.HVCIEnabled){'Enabled'}else{'Disabled'})" -ForegroundColor $hvciColor
        Write-Host "2. Control Flow Guard (CFG): $($sec.CFGStatus)" -ForegroundColor $cfgColor
        Write-Host "3. Data Execution Prev (DEP): $($sec.DEPStatus)" -ForegroundColor $depColor
        Write-Host "4. Bottom-up ASLR:           $($sec.ASLRStatus)" -ForegroundColor $aslrColor
        Write-Host "5. Back to Main Menu"
        
        $choice = Read-Host "`nSelect an option to toggle (1-5)"
        
        switch ($choice) {
            "1" {
                $target = if ($sec.HVCIEnabled) { 0 } else { 1 }
                $vbsKey = "HKLM:\System\CurrentControlSet\Control\DeviceGuard"
                $hvciKey = "HKLM:\System\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
                
                # Ensure VBS is enabled if enabling HVCI
                if ($target -eq 1) {
                    Set-ItemProperty -Path $vbsKey -Name "EnableVirtualizationBasedSecurity" -Value 1 -Type DWord -ErrorAction SilentlyContinue
                }
                
                if (-not (Test-Path $hvciKey)) {
                    New-Item -Path $hvciKey -Force | Out-Null
                }
                Set-ItemProperty -Path $hvciKey -Name "Enabled" -Value $target -Type DWord
                $anyChanges = $true
                Write-Host "Memory Integrity updated. A restart is required." -ForegroundColor Green
                Start-Sleep -Seconds 2
            }
            "2" {
                try {
                    if ($sec.CFGStatus -eq "ON") {
                        Set-ProcessMitigation -System -Disable CFG
                    } else {
                        Set-ProcessMitigation -System -Enable CFG
                    }
                    $anyChanges = $true
                    Write-Host "CFG updated. A restart is required." -ForegroundColor Green
                } catch {
                    Write-Host "Failed to update CFG: $_" -ForegroundColor Red
                }
                Start-Sleep -Seconds 2
            }
            "3" {
                try {
                    if ($sec.DEPStatus -eq "ON") {
                        Set-ProcessMitigation -System -Disable DEP
                    } else {
                        Set-ProcessMitigation -System -Enable DEP
                    }
                    $anyChanges = $true
                    Write-Host "DEP updated. A restart is required." -ForegroundColor Green
                } catch {
                    Write-Host "Failed to update DEP: $_" -ForegroundColor Red
                }
                Start-Sleep -Seconds 2
            }
            "4" {
                try {
                    if ($sec.ASLRStatus -eq "ON") {
                        Set-ProcessMitigation -System -Disable BottomUpASLR
                    } else {
                        Set-ProcessMitigation -System -Enable BottomUpASLR
                    }
                    $anyChanges = $true
                    Write-Host "ASLR updated. A restart is required." -ForegroundColor Green
                } catch {
                    Write-Host "Failed to update ASLR: $_" -ForegroundColor Red
                }
                Start-Sleep -Seconds 2
            }
            "5" {
                if ($anyChanges) {
                    Request-Restart
                }
                return
            }
            "" {
                if ($anyChanges) {
                    Request-Restart
                }
                return
            }
            default {
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
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

if (-not $Action) {
    while ($true) {
        Clear-Host
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "   Windows Virtualization Manager" -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan

        Show-Status

        Write-Host "`n--- Interactive Menu ---" -ForegroundColor Cyan
        Write-Host "1. Enable all features"
        Write-Host "2. Disable all features"
        Write-Host "3. Granular Toggle (Individual features)"
        Write-Host "4. Security Optimizations"
        Write-Host "5. Exit"
        
        $choice = Read-Host "`nSelect an option (1-5)"
        switch ($choice) {
            "1" { $Action = "Enable"; break }
            "2" { $Action = "Disable"; break }
            "3" { Show-GranularMenu; continue }
            "4" { Show-SecurityMenu; continue }
            "5" { Exit-WithCountdown }
            default { 
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 1
                continue
            }
        }
        if ($Action) { break }
    }
}
else {
    # If Action was passed as parameter, just show status once
    Clear-Host
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "   Windows Virtualization Manager" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Show-Status
}

if ($Action) {
    $needsRestart = Invoke-Toggle -TargetAction $Action
    if ($needsRestart) {
        Request-Restart
    }
}
Exit-WithCountdown
