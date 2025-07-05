# PowerShell Script to Install IIS, ASP.NET 4.8, and Configure SQL Server

# --- Install IIS and ASP.NET 4.8 ---
Write-Host "Installing IIS and required features for ASP.NET..."
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Asp-Net45 # Base for 4.x
Install-WindowsFeature -Name Web-Mgmt-Console
Install-WindowsFeature -Name Web-Scripting-Tools

Write-Host "IIS and base ASP.NET features installation complete."

# --- Install .NET Framework 4.8 ---
Write-Host "Checking for and installing .NET Framework 4.8 if needed..."
$dotnet48_url = "https://go.microsoft.com/fwlink/?linkid=2088631"
$dotnet48_installer = "$env:TEMP\ndp48-x86-x64-allos-enu.exe"

Invoke-WebRequest -Uri $dotnet48_url -OutFile $dotnet48_installer
Start-Process -FilePath $dotnet48_installer -ArgumentList "/q /norestart" -Wait
Write-Host ".NET Framework 4.8 installation check/update complete."

# --- Configure SQL Server for Mixed-Mode Authentication ---
Write-Host "Enabling SQL Server Mixed-Mode Authentication..."
# This registry key controls the authentication mode. 1 for Windows-only, 2 for Mixed-Mode.
$regKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer"
Set-ItemProperty -Path $regKey -Name LoginMode -Value 2 -Force
Write-Host "Registry updated for Mixed-Mode Authentication."

# --- Set SA Password and Restart SQL Service ---
Write-Host "Setting 'sa' password and restarting SQL Server service..."
$sqlInstance = "MSSQLSERVER"
$saPassword = "splendidcrm2005"

# Use Invoke-Sqlcmd to set the password. This is more reliable than other methods.
# The command needs to be run against the master database.
$query = "ALTER LOGIN sa WITH PASSWORD = '$saPassword'"

try {
    Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $query -ErrorAction Stop
    Write-Host "'sa' password has been set successfully."
} catch {
    Write-Error "Failed to set 'sa' password. Error: $_"
    # Even if it fails, we must restart for the LoginMode change to take effect.
}

# Restart the SQL Server service to apply the authentication mode change.
Restart-Service -Name "MSSQL`$$sqlInstance" -Force
Write-Host "SQL Server service has been restarted."

# --- Finalizing ---
Write-Host "Script finished. IIS, ASP.NET 4.8, and SQL Server configuration are complete."
