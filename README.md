# Windows Virtualization Toggle

A simple, effective tool to toggle Windows virtualization features (Hyper-V, Virtual Machine Platform, etc.) with a single click.

## Features

- **One-Click Toggle**: Use the `.bat` wrapper for easy execution.
- **PowerShell Core**: Robust logic handled by PowerShell.
- **VBS/HVCI Detection**: Automatically detects Virtualization-Based Security and Memory Integrity status.
- **Visual Feedback**: Color-coded status updates and progress tracking.
- **Auto-Exit**: 3-second countdown before closing the terminal.

## Usage

1. **Right-click `toggle-virtualization.bat`** and select **Run as administrator**.
2. Follow the interactive menu in the PowerShell window.
3. Restart your computer if prompted to apply changes.

## Scripts

- `toggle-virtualization.ps1`: The core logic script.
- `toggle-virtualization.bat`: A lightweight wrapper for easy execution.

## Requirements

- Windows 10/11
- Administrator privileges
