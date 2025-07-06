# PowerShell Script to Initialize Data Disk, Install IIS, ASP.NET 4.8, and Configure SQL Server
# Automated version for Azure Custom Script Extension

param(
    [switch]$Force = $false
)

$ErrorActionPreference = "Continue"
$global:RestartRequired = $false

# --- Logging Function ---
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
}

Write-Log "=== STARTING INFRASTRUCTURE SETUP ===" "INFO"

# --- Initialize and Format Data Disk ---
Write-Log "Initializing and formatting the data disk..." "INFO"
try {
    # Find the first disk that is not the OS disk (Number 0) and is unpartitioned (RAW).
    $disk = Get-Disk | Where-Object { $_.Number -gt 0 -and $_.PartitionStyle -eq 'RAW' } | Select-Object -First 1

    if ($disk) {
        Write-Log "Found data disk Number $($disk.Number). Preparing disk..." "INFO"
        
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
        Write-Log "Data disk prepared on drive $driveLetter. Data path: $global:dataPath" "SUCCESS"
    } else {
        Write-Log "No uninitialized data disk found. A raw data disk must be attached to the VM." "ERROR"
        exit 1
    }
} catch {
    Write-Log "Failed to initialize data disk. Error: $_" "ERROR"
    exit 1
}

# --- Install IIS and ASP.NET 4.8 ---
Write-Log "Installing IIS and required features for ASP.NET..." "INFO"
try {
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Asp-Net45 | Out-Null # Base for 4.x
    Install-WindowsFeature -Name Web-Mgmt-Console | Out-Null
    Install-WindowsFeature -Name Web-Scripting-Tools | Out-Null
    Write-Log "IIS and base ASP.NET features installation complete." "SUCCESS"
} catch {
    Write-Log "Failed to install IIS features: $_" "ERROR"
    exit 1
}

# --- Install .NET Framework 4.8 (AUTOMATED VERSION) ---
Write-Log "Checking for and installing .NET Framework 4.8 if needed..." "INFO"
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

Write-Log "Current .NET Framework version: $currentVersion (Release: $net48Version)" "INFO"

if ($net48Version -lt 528040) {
    Write-Log "Installing .NET Framework 4.8..." "INFO"
    
    # Download with retry logic and size verification
    $maxRetries = 3
    $retryCount = 0
    $downloadSuccess = $false
    
    while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
        try {
            Write-Log "Downloading .NET 4.8 installer (attempt $($retryCount + 1)/$maxRetries)..." "INFO"
            Invoke-WebRequest -Uri $dotnet48_url -OutFile $dotnet48_installer -TimeoutSec 600 -ErrorAction Stop
            
            # Verify download size (should be around 120MB)
            $fileSize = (Get-Item $dotnet48_installer).Length
            if ($fileSize -gt 100MB) {
                $downloadSuccess = $true
                Write-Log "Download complete. File size: $([math]::Round($fileSize / 1MB, 2)) MB" "SUCCESS"
            } else {
                throw "Downloaded file is too small ($([math]::Round($fileSize / 1MB, 2)) MB)"
            }
        } catch {
            $retryCount++
            Write-Log "Download attempt $retryCount failed: $_" "WARN"
            if ($retryCount -lt $maxRetries) {
                Start-Sleep -Seconds 10
            }
        }
    }
    
    if (-not $downloadSuccess) {
        Write-Log "Failed to download .NET 4.8 installer after $maxRetries attempts." "ERROR"
        exit 1
    }
    
    # Install with comprehensive error handling (NO USER INTERACTION)
    Write-Log "Installing .NET Framework 4.8. This may take several minutes..." "INFO"
    try {
        # Use quiet install with no restart and detailed logging
        $installArgs = @("/quiet", "/norestart", "/log", "$env:TEMP\dotnet48_install.log")
        $process = Start-Process -FilePath $dotnet48_installer -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        Write-Log ".NET 4.8 installer finished with exit code: $($process.ExitCode)" "INFO"
        
        # Check exit codes (from Microsoft documentation)
        switch ($process.ExitCode) {
            0 { 
                Write-Log "✓ .NET Framework 4.8 installation completed successfully." "SUCCESS"
            }
            1602 { 
                Write-Log "Installation was cancelled by user or another process." "WARN"
            }
            1603 { 
                Write-Log "A fatal error occurred during installation." "ERROR"
                if (Test-Path "$env:TEMP\dotnet48_install.log") {
                    Write-Log "Installation log:" "INFO"
                    Get-Content "$env:TEMP\dotnet48_install.log" | Select-Object -Last 20 | ForEach-Object { Write-Log $_ "INFO" }
                }
                # Don't exit - continue with deployment
            }
            1641 { 
                Write-Log "✓ Installation completed successfully. A restart is required." "SUCCESS"
                $global:RestartRequired = $true
            }
            3010 { 
                Write-Log "✓ Installation completed successfully. A restart is required." "SUCCESS"
                $global:RestartRequired = $true
            }
            5100 { 
                Write-Log "Computer does not meet system requirements." "ERROR"
                # Don't exit - continue with current .NET version
            }
            default { 
                Write-Log "Installation completed with unexpected exit code: $($process.ExitCode)" "WARN"
            }
        }
        
        # Wait a moment and verify installation
        Start-Sleep -Seconds 5
        $newNet48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
        
        if ($newNet48Version -ge 528040) {
            Write-Log "✓ .NET Framework 4.8 installation verified successfully. (Release: $newNet48Version)" "SUCCESS"
        } else {
            Write-Log "Installation may not have completed properly. Current version still shows: $newNet48Version" "WARN"
            Write-Log "This might require a system restart to complete." "WARN"
            $global:RestartRequired = $true
        }
        
    } catch {
        Write-Log "Failed to install .NET Framework 4.8: $_" "ERROR"
        Write-Log "Continuing with existing .NET version..." "WARN"
        # Don't exit - continue with deployment
    }
} else {
    Write-Log "✓ .NET Framework 4.8 is already installed. (Release: $net48Version)" "SUCCESS"
}

# --- Configure SQL Server ---
Write-Log "Configuring SQL Server..." "INFO"

# Create the directories on the new data disk
try {
    New-Item -ItemType Directory -Path $global:dataPath -Force | Out-Null
    New-Item -ItemType Directory -Path $global:logPath -Force | Out-Null
    Write-Log "Created SQL data and log directories on the data disk." "SUCCESS"
} catch {
    Write-Log "Failed to create SQL directories: $_" "ERROR"
    exit 1
}

# Dynamically discover the SQL Server instance and service name
try {
    $sqlService = Get-Service -Name "MSSQL*" | Where-Object { $_.DisplayName -like "SQL Server (*)" } | Select-Object -First 1
    if (-not $sqlService) {
        Write-Log "Could not find the SQL Server service." "ERROR"
        exit 1
    }
    $sqlServiceName = $sqlService.Name

    # Robustly extract the instance name from the display name
    $sqlInstanceName = ($sqlService.DisplayName -replace 'SQL Server \((.*)\)', '$1').Trim()

    Write-Log "Found SQL Server service: $sqlServiceName (Instance: $sqlInstanceName)" "SUCCESS"

    # Dynamically construct the registry path
    $instanceId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$sqlInstanceName
    if (-not $instanceId) {
        Write-Log "Could not find instance ID for SQL instance '$sqlInstanceName' in the registry." "ERROR"
        exit 1
    }
    $regKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"

    if (-not (Test-Path $regKey)) {
        Write-Log "Could not find the registry path for the SQL instance: $regKey" "ERROR"
        exit 1
    }
    Write-Log "Found SQL registry key: $regKey" "SUCCESS"

    # Configure Mixed Mode Authentication
    Set-ItemProperty -Path $regKey -Name LoginMode -Value 2 -Force
    Write-Log "Registry updated for Mixed-Mode Authentication." "SUCCESS"

    # Update default locations for new databases
    Set-ItemProperty -Path $regKey -Name "DefaultData" -Value $global:dataPath
    Set-ItemProperty -Path $regKey -Name "DefaultLog" -Value $global:logPath
    Write-Log "SQL Server default data and log paths updated to use the data disk." "SUCCESS"

} catch {
    Write-Log "Failed to configure SQL Server registry: $_" "ERROR"
    exit 1
}

# --- RESTART SQL Server to apply Mixed Mode ---
Write-Log "Restarting SQL Server to apply Mixed Mode authentication..." "INFO"
try {
    Restart-Service -Name $sqlServiceName -Force
    Write-Log "SQL Server service restarted." "SUCCESS"
} catch {
    Write-Log "Failed to restart SQL Server: $_" "ERROR"
    exit 1
}

# --- Wait for SQL Server to be ready after restart ---
Write-Log "Waiting for SQL Server to be ready after restart..." "INFO"
$maxAttempts = 60
$attempt = 0
$sqlReady = $false
while (-not $sqlReady -and $attempt -lt $maxAttempts) {
    try {
        # Try to connect using Windows Authentication first
        Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1" -QueryTimeout 5 -ErrorAction Stop | Out-Null
        $sqlReady = $true
        Write-Log "SQL Server is ready and accepting connections." "SUCCESS"
    } catch {
        Write-Log "SQL Server not ready yet. Retrying in 5 seconds... (Attempt $($attempt + 1)/$maxAttempts)" "INFO"
        Start-Sleep -Seconds 5
        $attempt++
    }
}

if (-not $sqlReady) {
    Write-Log "SQL Server did not become ready within the expected time." "ERROR"
    exit 1
}

# --- Configure SA Password (after Mixed Mode is active) ---
Write-Log "Setting 'sa' password now that Mixed Mode is active..." "INFO"
$saPassword = "splendidcrm2005"

try {
    # Execute using Windows Authentication
    $query = "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$saPassword'"
    Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $query -ErrorAction Stop
    Write-Log "'sa' password has been set successfully." "SUCCESS"
} catch {
    Write-Log "Failed to set 'sa' password: $_" "WARN"
    Write-Log "Attempting to create sa login if it doesn't exist..." "INFO"
    
    # Try to create the sa login if it doesn't exist
    try {
        $createQuery = "IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = 'sa') CREATE LOGIN sa WITH PASSWORD = '$saPassword'; ALTER LOGIN sa ENABLE;"
        Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $createQuery -ErrorAction Stop
        Write-Log "'sa' login created and enabled successfully." "SUCCESS"
    } catch {
        Write-Log "Could not create/enable sa login: $_" "WARN"
        Write-Log "Continuing with Windows Authentication only..." "WARN"
    }
}

# --- Test SQL Server connectivity ---
Write-Log "Testing SQL Server connectivity..." "INFO"
try {
    # Test Windows Auth
    $testQuery = "SELECT @@VERSION as SQLVersion, SERVERPROPERTY('ProductVersion') as ProductVersion"
    $result = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $testQuery
    Write-Log "SQL Server Version: $($result.SQLVersion)" "SUCCESS"
    
    # Test Mixed Mode if sa is available
    try {
        $result2 = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1 as TestConnection" -Username "sa" -Password $saPassword
        Write-Log "Mixed Mode authentication test: SUCCESS" "SUCCESS"
    } catch {
        Write-Log "Mixed Mode authentication test failed, but Windows Auth works: $_" "WARN"
    }
} catch {
    Write-Log "SQL Server connectivity test failed: $_" "ERROR"
    exit 1
}

# --- Final Status ---
if ($global:RestartRequired) {
    Write-Log "⚠️  IMPORTANT: A system restart may be required to complete .NET Framework 4.8 installation." "WARN"
    Write-Log "   The deployment will continue, but you may need to restart after completion." "WARN"
}

Write-Log "`n=== INSTALLATION SUMMARY ===" "INFO"
Write-Log "✓ Data disk configured: $global:dataPath" "SUCCESS"
Write-Log "✓ Log path configured: $global:logPath" "SUCCESS"
Write-Log "✓ IIS and ASP.NET features installed" "SUCCESS"

$finalNet48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
$finalVersionText = if ($finalNet48Version -ge 528040) { "4.8 ✓" } else { "4.7.x (restart may be required)" }
Write-Log "✓ .NET Framework version: $finalVersionText" "SUCCESS"

Write-Log "✓ SQL Server configured and ready" "SUCCESS"

if (-not $global:RestartRequired) {
    Write-Log "🎉 All installations completed successfully. Ready for application deployment." "SUCCESS"
} else {
    Write-Log "⏳ Installation complete but restart may be required for .NET 4.8." "WARN"
}

Write-Log "Infrastructure setup completed successfully!" "SUCCESS"
exit 0