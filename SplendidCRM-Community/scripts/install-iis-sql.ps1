# PowerShell Script to Install IIS, ASP.NET 4.8, and SQL Server

# --- Install IIS and Base ASP.NET Features ---
Write-Host "Installing IIS and required features for ASP.NET..."
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Asp-Net45 # Base for 4.x
Install-WindowsFeature -Name Web-Mgmt-Console
Install-WindowsFeature -Name Web-Scripting-Tools

Write-Host "IIS and base ASP.NET features installation complete."

# --- Install .NET Framework 4.8 ---
Write-Host "Downloading and installing .NET Framework 4.8..."
$dotnet48_url = "https://go.microsoft.com/fwlink/?linkid=2088631"
$dotnet48_installer = "$env:TEMP\ndp48-x86-x64-allos-enu.exe"

Invoke-WebRequest -Uri $dotnet48_url -OutFile $dotnet48_installer

Start-Process -FilePath $dotnet48_installer -ArgumentList "/q /norestart" -Wait

Write-Host ".NET Framework 4.8 installation complete. A restart might be required for changes to take effect."

# --- Install SQL Server 2019 Developer Edition ---
Write-Host "Starting SQL Server 2019 Developer Edition installation..."

$sqlSetupPath = "$env:TEMP\SQLServerSetup"
if (-not (Test-Path -Path $sqlSetupPath)) {
    New-Item -ItemType Directory -Path $sqlSetupPath
}

$installerPath = "$sqlSetupPath\SQLServer2019-SSEI-Dev.exe"

# Download SQL Server Installer
Write-Host "Downloading SQL Server installer..."
$source = "https://go.microsoft.com/fwlink/?linkid=866662"
Invoke-WebRequest -Uri $source -OutFile $installerPath

# Run the installer to download the media
Write-Host "Downloading SQL Server installation media... This may take a while."
Start-Process -FilePath $installerPath -ArgumentList "/q /Action:Download /MediaType:CAB /MediaSource:`"$sqlSetupPath`"" -Wait

# Run the main setup for a quiet installation
Write-Host "Installing SQL Server instance..."
# The actual setup executable might be in a subfolder, let's find it
$setupExe = Get-ChildItem -Path $sqlSetupPath -Filter "SETUP.EXE" -Recurse | Select-Object -First 1 -ExpandProperty FullName

if ($null -eq $setupExe) {
    Write-Error "SQL Server SETUP.EXE not found after download. Halting installation."
    exit 1
}

$arguments = "/q /ACTION=Install /FEATURES=SQLENGINE /INSTANCENAME=MSSQLSERVER /SQLSVCACCOUNT=`"NT AUTHORITY\System`" /SQLSYSADMINACCOUNTS=`"BUILTIN\ADMINISTRATORS`" /TCPENABLED=1 /IACCEPTSQLSERVERLICENSETERMS"

Start-Process -FilePath $setupExe -ArgumentList $arguments -Wait

Write-Host "SQL Server installation complete."

# --- Finalizing ---
Write-Host "Script finished. IIS, ASP.NET 4.8, and SQL Server should be installed."
