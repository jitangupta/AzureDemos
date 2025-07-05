# PowerShell Script to Install IIS and ASP.NET 4.8

# --- Install IIS and ASP.NET 4.8 ---
Write-Host "Installing IIS and required features for ASP.NET..."
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Asp-Net45 # Base for 4.x
Install-WindowsFeature -Name Web-Mgmt-Console
Install-WindowsFeature -Name Web-Scripting-Tools

Write-Host "IIS and base ASP.NET features installation complete."

# --- Install .NET Framework 4.8 ---
# The Windows Server 2019 image with SQL Server should have a recent .NET Framework.
# This step ensures 4.8 is installed if it is not already present.
Write-Host "Checking for and installing .NET Framework 4.8 if needed..."
$dotnet48_url = "https://go.microsoft.com/fwlink/?linkid=2088631"
$dotnet48_installer = "$env:TEMP\ndp48-x86-x64-allos-enu.exe"

Invoke-WebRequest -Uri $dotnet48_url -OutFile $dotnet48_installer

Start-Process -FilePath $dotnet48_installer -ArgumentList "/q /norestart" -Wait

Write-Host ".NET Framework 4.8 installation check/update complete."

# --- Finalizing ---
Write-Host "Script finished. IIS and ASP.NET 4.8 should be configured."