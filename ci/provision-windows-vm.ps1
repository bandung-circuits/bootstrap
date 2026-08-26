# provision-windows-vm.ps1 — run INSIDE the Windows 11 ARM template VM.
# Readies it for CI: OpenSSH server, winget, PowerShell policy, VMware Tools check.
# Run once before snapshotting 'clean-base'.

$ErrorActionPreference = 'Stop'
function Note($m){ Write-Host "==> $m" -ForegroundColor Green }

Note 'Setting PowerShell execution policy (RemoteSigned, CurrentUser)'
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force

Note 'Enabling OpenSSH Server'
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' }
Start-Service sshd
Set-Service sshd -StartupType Automatic

Note 'Ensuring winget is available'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'winget missing. Install "App Installer" from Microsoft Store, then re-run.' -ForegroundColor Yellow
}

Note 'Provisioning complete. Snapshot this VM as clean-base from the host:
  vmrun -T fusion snapshot "<vmx>" clean-base'
