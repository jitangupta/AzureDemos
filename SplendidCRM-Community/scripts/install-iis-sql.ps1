# PowerShell Script to Initialize Data Disk, Install IIS, ASP.NET 4.8, and Configure SQL Server

# --- Initialize and Format Data Disk ---
Write-Host "Initializing and formatting the data disk..."
try {
    # Find the first disk that is not the OS disk (Number 0) and is unpartitioned (RAW).
    $disk = Get-Disk | Where-Object { $_.Number -gt 0 -and $_.PartitionStyle -eq 'RAW' } | Select-Object -First 1

    if ($disk) {
        Write-Host "Found data disk Number $($disk.Number). Preparing disk..."
        
        # Execute commands sequentially for clarity and robustness. This avoids pipeline issues.
        Set-Disk -Number $disk.Number -IsOffline $false
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT
        
        # Create the partition and get the resulting object
        $partition = New-Partition -DiskNumber $disk.Number -AssignDriveLetter -UseMaximumSize
        
        # Format the volume using the drive letter, which is more robust
        Format-Volume -DriveLetter $partition.DriveLetter -FileSystem NTFS -NewFileSystemLabel "SQLData" -Confirm:$false
        
        # Get the drive letter from the partition object
        $driveLetter = $partition.DriveLetter
        
        $global:dataPath = "${driveLetter}:\SQLData"
        $global:logPath = "${driveLetter}:\SQLLogs"
        Write-Host "Data disk prepared on drive $driveLetter. Data path: $global:dataPath"
    } else {
        Write-Error "No uninitialized data disk found. A raw data disk must be attached to the VM. Halting script."
        exit 1
    }
} catch {
    Write-Error "Failed to initialize data disk. Error: $_"
    exit 1
}

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

# Check if .NET 4.8 is already installed to avoid unnecessary download/install
$net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
if ($net48Version -lt 528040) {
    Invoke-WebRequest -Uri $dotnet48_url -OutFile $dotnet48_installer
    Start-Process -FilePath $dotnet48_installer -ArgumentList "/q /norestart" -Wait
    Write-Host ".NET Framework 4.8 installation complete."
} else {
    Write-Host ".NET Framework 4.8 is already installed."
}

# --- Configure SQL Server ---
Write-Host "Configuring SQL Server..."

# Create the directories on the new data disk
New-Item -ItemType Directory -Path $global:dataPath -Force
New-Item -ItemType Directory -Path $global:logPath -Force
Write-Host "Created SQL data and log directories on the data disk."

# Dynamically discover the SQL Server instance and service name
$sqlService = Get-Service -Name "MSSQL*" | Where-Object { $_.DisplayName -like "SQL Server (*)" } | Select-Object -First 1
if (-not $sqlService) {
    Write-Error "Could not find the SQL Server service. Halting script."
    exit 1
}
$sqlServiceName = $sqlService.Name

# Robustly extract the instance name from the display name, e.g., "SQL Server (MSSQLSERVER)"
$sqlInstanceName = ($sqlService.DisplayName -replace 'SQL Server \((.*)\)', '$1').Trim()

Write-Host "Found SQL Server service: $sqlServiceName (Instance: $sqlInstanceName)"

# Dynamically construct the registry path
$instanceId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$sqlInstanceName
if (-not $instanceId) {
    Write-Error "Could not find instance ID for SQL instance '$sqlInstanceName' in the registry."
    exit 1
}
$regKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"

if (-not (Test-Path $regKey)) {
    Write-Error "Could not find the registry path for the SQL instance: $regKey. Halting script."
    exit 1
}
Write-Host "Found SQL registry key: $regKey"

# This registry key controls the authentication mode. 1 for Windows-only, 2 for Mixed-Mode.
Set-ItemProperty -Path $regKey -Name LoginMode -Value 2 -Force
Write-Host "Registry updated for Mixed-Mode Authentication."

# Update default locations for new databases
Set-ItemProperty -Path $regKey -Name "DefaultData" -Value $global:dataPath
Set-ItemProperty -Path $regKey -Name "DefaultLog" -Value $global:logPath
Write-Host "SQL Server default data and log paths updated to use the data disk."

# --- Set SA Password and Restart SQL Service ---
Write-Host "Setting 'sa' password and restarting SQL Server service..."
$saPassword = "splendidcrm2005" # This should be parameterized in a real scenario

# Use Invoke-Sqlcmd to set the password.
$query = "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$saPassword'"

try {
    # Ensure the SQL service is running
    Start-Service -Name $sqlServiceName -ErrorAction Stop

    # Wait for SQL Server to be ready to accept connections
    Write-Host "Waiting for SQL Server to be ready..."
    $maxAttempts = 60
    $attempt = 0
    $sqlReady = $false
    while (-not $sqlReady -and $attempt -lt $maxAttempts) {
        try {
            Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1" -QueryTimeout 5 -ErrorAction Stop
            $sqlReady = $true
            Write-Host "SQL Server is ready."
        } catch {
            Write-Host "SQL Server not ready yet. Retrying in 5 seconds..."
            Start-Sleep -Seconds 5
            $attempt++
        }
    }

    if (-not $sqlReady) {
        Write-Error "SQL Server did not become ready within the expected time. Halting script."
        exit 1
    }

    # Now set the 'sa' password
    Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $query -ErrorAction Stop
    Write-Host "'sa' password has been set successfully."
} catch {
    Write-Error "Failed to set 'sa' password. Error: $_"
    # Even if it fails, we must restart for the changes to take effect.
}

# Restart the SQL Server service to apply all changes.
Restart-Service -Name $sqlServiceName -Force
Write-Host "SQL Server service has been restarted to apply all configuration changes."

# --- Finalizing ---
Write-Host "Script finished. Data disk, IIS, ASP.NET 4.8, and SQL Server configuration are complete."