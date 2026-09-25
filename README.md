# Windows Feature Selector

Keyboard-driven, two-pane menu for inspecting and selectively changing Windows virtualization and security settings. Windows 10/11 with Windows PowerShell 5.1.

## Run

Download both `Windows-Feature-Selector.bat` and `Windows-Feature-Selector.ps1` into the same folder, then open the `.bat` file. A normal console can inspect status; changes require administrator approval. The batch launcher sets execution policy only for its PowerShell process. No feature is changed merely by opening the menu.

- Up/Down: choose a feature; Space or Enter: check/uncheck it; A: check all/none; R: refresh status.
- E/D: propose enabling/disabling checked features (or the highlighted feature when none are checked). Confirm with Y; N cancels.
- U: request a new administrator menu. Select features again in that window.
- Type `quit` or press Esc to exit. Minimum console size: 80 columns by 24 rows.

## Features

1. Hyper-V
2. Virtual Machine Platform
3. Windows Hypervisor Platform
4. Windows Subsystem for Linux optional feature
5. Windows Sandbox
6. Virtualization-based security (VBS)
7. Memory integrity (HVCI)
8. System-wide Control Flow Guard (CFG)

Firmware virtualization and whether a hypervisor is running are read-only indicators; firmware settings are **not** changed. DEP and ASLR are not modified.

## Command line

From a terminal in the downloaded folder:

```powershell
./Windows-Feature-Selector.bat -Action Status -Selection 1-8
./Windows-Feature-Selector.bat -Action Status -Selection 1,3-5
./Windows-Feature-Selector.bat -Action Enable -Selection 1,2
```

`-Selection` accepts numbers, comma-separated ranges, or `all`. Enable/Disable require an elevated console and an explicit `APPLY` prompt. Status works without elevation, though some optional-feature states require elevation to query.

## Safety

Changing Windows optional features, VBS, HVCI, or CFG can affect security, compatibility, and virtualization workloads. The script refuses to override policy-managed or UEFI-locked VBS/HVCI, checks their dependency order, and never restarts Windows automatically. A restart may be needed for changes to take effect. Review the selection and current state before approving.
