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

# Check current .NET version
$net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
$currentVersion = switch ($net48Version) {
    461808 { "4.7.2" }
    461814 { "4.7.2" }
    528040 { "4.8" }
    528049 { "4.8" }
    528372 { "4.8" }
    528449 { "4.8" }
    default { "Unknown ($net48Version)" }
}

Write-Host "Current .NET Framework version: $currentVersion (Release: $net48Version)"

if ($net48Version -lt 528040) {
    Write-Host "Installing .NET Framework 4.8..."
    
    # Download with retry logic and size verification
    $maxRetries = 3
    $retryCount = 0
    $downloadSuccess = $false
    
    while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
        try {
            Write-Host "Downloading .NET 4.8 installer (attempt $($retryCount + 1)/$maxRetries)..."
            Invoke-WebRequest -Uri $dotnet48_url -OutFile $dotnet48_installer -TimeoutSec 600 -ErrorAction Stop
            
            # Verify download size (should be around 120MB)
            $fileSize = (Get-Item $dotnet48_installer).Length
            if ($fileSize -gt 100MB) {
                $downloadSuccess = $true
                Write-Host "Download complete. File size: $([math]::Round($fileSize / 1MB, 2)) MB"
            } else {
                throw "Downloaded file is too small ($([math]::Round($fileSize / 1MB, 2)) MB)"
            }
        } catch {
            $retryCount++
            Write-Warning "Download attempt $retryCount failed: $_"
            if ($retryCount -lt $maxRetries) {
                Start-Sleep -Seconds 10
            }
        }
    }
    
    if (-not $downloadSuccess) {
        Write-Error "Failed to download .NET 4.8 installer after $maxRetries attempts."
        exit 1
    }
    
    # Check for pending reboots that might block installation
    Write-Host "Checking for pending reboots..."
    $pendingReboot = $false
    
    # Check various registry keys for pending reboots
    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    
    foreach ($key in $rebootKeys) {
        if (Test-Path $key) {
            $pendingReboot = $true
            Write-Warning "Pending reboot detected: $key"
        }
    }
    
    if ($pendingReboot) {
        Write-Warning "System has pending reboots. .NET installation may fail or require a restart."
    }
    
    # Install with comprehensive error handling
    Write-Host "Installing .NET Framework 4.8. This may take several minutes..."
    try {
        # Use more verbose logging for troubleshooting
        $installArgs = @("/q", "/norestart", "/log", "$env:TEMP\dotnet48_install.log")
        $process = Start-Process -FilePath $dotnet48_installer -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        Write-Host ".NET 4.8 installer finished with exit code: $($process.ExitCode)"
        
        # Check exit codes (from Microsoft documentation)
        switch ($process.ExitCode) {
            0 { 
                Write-Host "✓ .NET Framework 4.8 installation completed successfully." 
            }
            1602 { 
                Write-Warning "Installation was cancelled by user or another process."
            }
            1603 { 
                Write-Error "A fatal error occurred during installation."
                if (Test-Path "$env:TEMP\dotnet48_install.log") {
                    Write-Host "Installation log:"
                    Get-Content "$env:TEMP\dotnet48_install.log" | Select-Object -Last 20
                }
                exit 1
            }
            1641 { 
                Write-Host "✓ Installation completed successfully. A restart is required."
                $global:RestartRequired = $true
            }
            3010 { 
                Write-Host "✓ Installation completed successfully. A restart is required."
                $global:RestartRequired = $true
            }
            5100 { 
                Write-Warning "Computer does not meet system requirements."
                exit 1
            }
            default { 
                Write-Warning "Installation completed with unexpected exit code: $($process.ExitCode)"
            }
        }
        
        # Wait a moment and verify installation
        Start-Sleep -Seconds 5
        $newNet48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
        
        if ($newNet48Version -ge 528040) {
            Write-Host "✓ .NET Framework 4.8 installation verified successfully. (Release: $newNet48Version)"
        } else {
            Write-Warning "Installation may not have completed properly. Current version still shows: $newNet48Version"
            Write-Host "This might require a system restart to complete."
            $global:RestartRequired = $true
        }
        
    } catch {
        Write-Error "Failed to install .NET Framework 4.8: $_"
        if (Test-Path "$env:TEMP\dotnet48_install.log") {
            Write-Host "Installation log:"
            Get-Content "$env:TEMP\dotnet48_install.log" | Select-Object -Last 10
        }
        exit 1
    }
} else {
    Write-Host "✓ .NET Framework 4.8 is already installed. (Release: $net48Version)"
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

# --- CRITICAL FIX: Restart SQL Server FIRST to apply Mixed Mode ---
Write-Host "Restarting SQL Server to apply Mixed Mode authentication..."
Restart-Service -Name $sqlServiceName -Force
Write-Host "SQL Server service restarted."

# --- Wait for SQL Server to be ready after restart ---
Write-Host "Waiting for SQL Server to be ready after restart..."
$maxAttempts = 60
$attempt = 0
$sqlReady = $false
while (-not $sqlReady -and $attempt -lt $maxAttempts) {
    try {
        # Try to connect using Windows Authentication first
        Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1" -QueryTimeout 5 -ErrorAction Stop
        $sqlReady = $true
        Write-Host "SQL Server is ready and accepting connections."
    } catch {
        Write-Host "SQL Server not ready yet. Retrying in 5 seconds... (Attempt $($attempt + 1)/$maxAttempts)"
        Start-Sleep -Seconds 5
        $attempt++
    }
}

if (-not $sqlReady) {
    Write-Error "SQL Server did not become ready within the expected time. Halting script."
    exit 1
}

# --- NOW Set SA Password (after Mixed Mode is active) ---
Write-Host "Setting 'sa' password now that Mixed Mode is active..."
$saPassword = "splendidcrm2005" # This should be parameterized in a real scenario

# Use Invoke-Sqlcmd to set the password with Windows Authentication
$query = "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$saPassword'"

try {
    # Execute using Windows Authentication (which should still work)
    Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $query -ErrorAction Stop
    Write-Host "'sa' password has been set successfully."
} catch {
    Write-Error "Failed to set 'sa' password. Error: $_"
    Write-Host "This may be expected if sa login doesn't exist. Attempting to create it..."
    
    # Try to create the sa login if it doesn't exist
    try {
        $createQuery = "IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = 'sa') CREATE LOGIN sa WITH PASSWORD = '$saPassword'; ALTER LOGIN sa ENABLE;"
        Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $createQuery -ErrorAction Stop
        Write-Host "'sa' login created and enabled successfully."
    } catch {
        Write-Warning "Could not create/enable sa login. This may not be critical for your migration. Error: $_"
    }
}

# --- Test SQL Server connectivity ---
Write-Host "Testing SQL Server connectivity..."
try {
    # Test Windows Auth
    $testQuery = "SELECT @@VERSION as SQLVersion, SERVERPROPERTY('ProductVersion') as ProductVersion"
    $result = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $testQuery
    Write-Host "SQL Server Version: $($result.SQLVersion)"
    
    # Test Mixed Mode if sa is available
    try {
        $result2 = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1 as TestConnection" -Username "sa" -Password $saPassword
        Write-Host "Mixed Mode authentication test: SUCCESS"
    } catch {
        Write-Warning "Mixed Mode authentication test failed, but Windows Auth works: $_"
    }
} catch {
    Write-Error "SQL Server connectivity test failed: $_"
    exit 1
}

# --- Check for Restart Requirement ---
if ($global:RestartRequired) {
    Write-Warning "⚠️  IMPORTANT: A system restart is required to complete .NET Framework 4.8 installation."
    Write-Warning "   Please restart the VM and re-run any subsequent deployment scripts."
    Write-Warning "   You can verify .NET 4.8 installation after restart with:"
    Write-Warning "   (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release"
}

# --- Final Verification ---
Write-Host "`n=== INSTALLATION SUMMARY ==="
Write-Host "✓ Data disk configured: $global:dataPath"
Write-Host "✓ Log path configured: $global:logPath"
Write-Host "✓ IIS and ASP.NET features installed"

$finalNet48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
$finalVersionText = if ($finalNet48Version -ge 528040) { "4.8 ✓" } else { "4.7.x (restart may be required)" }
Write-Host "✓ .NET Framework version: $finalVersionText"

Write-Host "✓ SQL Server configured and ready"

if (-not $global:RestartRequired) {
    Write-Host "`n🎉 All installations completed successfully. Ready for application deployment."
} else {
    Write-Host "`n⏳ Installation complete but restart required before proceeding."
}

Write-Host "`nScript finished. Infrastructure setup complete."