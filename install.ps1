# Installs the latest Dominote release for the current Windows user. No admin rights needed.
# Usage (PowerShell): irm https://raw.githubusercontent.com/dominik-hurcik/dominote/main/install.ps1 | iex
#
# Files downloaded by PowerShell are not marked as coming from the internet,
# so SmartScreen does not stop this unsigned build. Run the same command again to update.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # the progress bar makes downloads much slower in Windows PowerShell

$url = 'https://github.com/dominik-hurcik/dominote/releases/latest/download/Dominote-setup.exe'
$setup = Join-Path $env:TEMP 'Dominote-setup.exe'

Write-Host 'Downloading Dominote...'
Invoke-WebRequest -Uri $url -OutFile $setup -UseBasicParsing

# Close a running copy so it can be replaced. Notes are saved to disk as you type.
Get-Process -Name 'Dominote' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Host 'Installing...'
Start-Process -FilePath $setup -ArgumentList '/S' -Wait
Remove-Item $setup -ErrorAction SilentlyContinue

$dir = Join-Path $env:LOCALAPPDATA 'Dominote'
$exe = Get-ChildItem -Path $dir -Filter '*.exe' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike 'uninstall*' } | Select-Object -First 1
if (-not $exe) {
  Write-Error "Install finished, but Dominote.exe was not found in $dir."
}

Write-Host "Installed to $dir. Dominote is also in the Start menu."
Start-Process -FilePath $exe.FullName
