# URL of the remote script
$remoteScriptUrl = "https://raw.githubusercontent.com/Jose-AE/auto-windows/main/setup.ps1"

# Install PowerShell silently
winget install -e --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

# Run the remote script in a new elevated PowerShell session
Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Invoke-Expression (Invoke-WebRequest -Uri '$remoteScriptUrl' -UseBasicParsing).Content`""