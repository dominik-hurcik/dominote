# Installs the latest Hebdo release for the current Windows user. No admin rights needed.
# Usage (PowerShell): irm https://hebdo.app/install.ps1 | iex
#
# Files downloaded by PowerShell are not marked as coming from the internet,
# so SmartScreen does not stop this unsigned build. Run the same command again to update.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # the progress bar makes downloads much slower in Windows PowerShell

$url = 'https://github.com/dominik-hurcik/hebdo/releases/latest/download/Hebdo-setup.exe'
$setup = Join-Path $env:TEMP 'Hebdo-setup.exe'

Write-Host 'Downloading Hebdo...'
Invoke-WebRequest -Uri $url -OutFile $setup -UseBasicParsing

# Close a running copy so it can be replaced. Notes are saved to disk as you type.
Get-Process -Name 'Hebdo' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Host 'Installing...'
Start-Process -FilePath $setup -ArgumentList '/S' -Wait
Remove-Item $setup -ErrorAction SilentlyContinue

$dir = Join-Path $env:LOCALAPPDATA 'Hebdo'
$exe = Get-ChildItem -Path $dir -Filter '*.exe' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike 'uninstall*' } | Select-Object -First 1
if (-not $exe) {
  Write-Error "Install finished, but Hebdo.exe was not found in $dir."
}

Write-Host "Installed to $dir. Hebdo is also in the Start menu."
Start-Process -FilePath $exe.FullName
