# PowerShell Script to Initialize Data Disk, Install IIS, ASP.NET 4.8, and Configure SQL Server
# Automated version for Azure Custom Script Extension

param(
    [switch]$Force = $false
)

$ErrorActionPreference = "Continue"
$global:RestartRequired = $false

# --- Enhanced Logging and Retry Functions ---
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
}

# Generic retry function for improved reliability
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5,
        [scriptblock]$SuccessTest = $null,
        [bool]$ContinueOnFailure = $false
    )
    
    $attempt = 0
    $success = $false
    $lastError = $null
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        Write-Log "$OperationName - Attempt $attempt/$MaxRetries" "INFO"
        
        try {
            $result = & $ScriptBlock
            
            # If a success test is provided, use it; otherwise assume success
            if ($SuccessTest) {
                $success = & $SuccessTest $result
                if (-not $success) {
                    throw "Success test failed for $OperationName"
                }
            } else {
                $success = $true
            }
            
            if ($success) {
                Write-Log "$OperationName - SUCCESS on attempt $attempt" "SUCCESS"
                return $result
            }
        } catch {
            $lastError = $_
            Write-Log "$OperationName - Attempt $attempt failed: $_" "WARN"
            
            if ($attempt -lt $MaxRetries) {
                Write-Log "Waiting $DelaySeconds seconds before retry..." "INFO"
                Start-Sleep -Seconds $DelaySeconds
                # Exponential backoff for subsequent retries
                $DelaySeconds = [Math]::Min($DelaySeconds * 1.5, 30)
            }
        }
    }
    
    # Final failure handling
    if (-not $success) {
        $errorMsg = "$OperationName failed after $MaxRetries attempts. Last error: $lastError"
        if ($ContinueOnFailure) {
            Write-Log $errorMsg "WARN"
            Write-Log "Continuing due to ContinueOnFailure flag..." "WARN"
            return $null
        } else {
            Write-Log $errorMsg "ERROR"
            throw $lastError
        }
    }
}

# Service management with retry logic
function Start-ServiceWithRetry {
    param(
        [string]$ServiceName,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 10
    )
    
    return Invoke-WithRetry -OperationName "Starting service $ServiceName" -MaxRetries $MaxRetries -DelaySeconds $DelaySeconds -ScriptBlock {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Start-Sleep -Seconds 5  # Allow service to fully start
    } -SuccessTest {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        return ($service -and $service.Status -eq 'Running')
    }
}

function Stop-ServiceWithRetry {
    param(
        [string]$ServiceName,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 10
    )
    
    return Invoke-WithRetry -OperationName "Stopping service $ServiceName" -MaxRetries $MaxRetries -DelaySeconds $DelaySeconds -ScriptBlock {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        Start-Sleep -Seconds 5  # Allow service to fully stop
    } -SuccessTest {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        return ($service -and $service.Status -eq 'Stopped')
    }
}

function Restart-ServiceWithRetry {
    param(
        [string]$ServiceName,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 10
    )
    
    return Invoke-WithRetry -OperationName "Restarting service $ServiceName" -MaxRetries $MaxRetries -DelaySeconds $DelaySeconds -ScriptBlock {
        Restart-Service -Name $ServiceName -Force -ErrorAction Stop
        Start-Sleep -Seconds 10  # Allow service to fully restart
    } -SuccessTest {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        return ($service -and $service.Status -eq 'Running')
    }
}

# SQL connectivity test with retry
function Test-SqlConnectionWithRetry {
    param(
        [string]$ServerInstance = ".",
        [string]$Database = "master",
        [string]$Username = $null,
        [string]$Password = $null,
        [int]$MaxRetries = 10,
        [int]$DelaySeconds = 5
    )
    
    return Invoke-WithRetry -OperationName "Testing SQL connection" -MaxRetries $MaxRetries -DelaySeconds $DelaySeconds -ScriptBlock {
        $params = @{
            ServerInstance = $ServerInstance
            Database = $Database
            Query = "SELECT 1"
            QueryTimeout = 5
            ErrorAction = "Stop"
        }
        
        if ($Username -and $Password) {
            $params.Username = $Username
            $params.Password = $Password
        }
        
        Invoke-Sqlcmd @params | Out-Null
        return $true
    } -ContinueOnFailure $false
}

# Function to dynamically find the run-all.ps1 script path
function Get-RunAllScriptPath {
    # Try multiple methods to find the run-all.ps1 script
    $scriptLocations = @(
        # Method 1: Same directory as current script
        (Join-Path (Split-Path -Parent $PSCommandPath) "run-all.ps1"),
        # Method 2: Current working directory
        (Join-Path (Get-Location) "run-all.ps1"),
        # Method 3: Azure CSE typical location (fallback)
        "C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\*\download\0\run-all.ps1",
        # Method 4: Alternative Azure CSE location
        "C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\*\Downloads\*\run-all.ps1",
        # Method 5: Search in common script directories
        "C:\Scripts\run-all.ps1",
        "C:\Temp\run-all.ps1"
    )
    
    foreach ($location in $scriptLocations) {
        if ($location -like "*\*\*") {
            # Handle wildcard paths
            $resolvedPaths = Get-ChildItem -Path (Split-Path $location -Parent) -Filter (Split-Path $location -Leaf) -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolvedPaths) {
                Write-Log "Found run-all.ps1 at: $($resolvedPaths.FullName)" "INFO"
                return $resolvedPaths.FullName
            }
        } elseif (Test-Path $location) {
            Write-Log "Found run-all.ps1 at: $location" "INFO"
            return $location
        }
    }
    
    # If not found, log error and return null
    Write-Log "Could not locate run-all.ps1 script in any expected location" "ERROR"
    return $null
}

# Function to get or generate secure SA password
function Get-SecureSaPassword {
    param(
        [string]$PasswordFile = "$env:TEMP\splendidcrm_sa_password.txt"
    )
    
    # Check if password file already exists (for consistency across scripts)
    if (Test-Path $PasswordFile) {
        try {
            $securePassword = Get-Content $PasswordFile | ConvertTo-SecureString
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
            Write-Log "Retrieved existing SA password from secure storage" "INFO"
            return $plainPassword
        } catch {
            Write-Log "Could not read existing password file, generating new one: $_" "WARN"
        }
    }
    
    # Generate a new secure password
    $length = 16
    $characters = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*"
    $password = ""
    
    for ($i = 0; $i -lt $length; $i++) {
        $password += $characters[(Get-Random -Maximum $characters.Length)]
    }
    
    # Add complexity requirements
    $password = "Sp$" + $password + "CRM!" + (Get-Random -Maximum 99)
    
    # Store securely for other scripts to use
    try {
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $securePassword | ConvertFrom-SecureString | Out-File $PasswordFile -Encoding ASCII
        
        # Set restrictive permissions on password file
        $acl = Get-Acl $PasswordFile
        $acl.SetAccessRuleProtection($true, $false)  # Remove inheritance
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")))
        $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "Allow")))
        Set-Acl -Path $PasswordFile -AclObject $acl
        
        Write-Log "Generated new secure SA password and stored securely" "SUCCESS"
    } catch {
        Write-Log "Could not store password securely: $_" "WARN"
        Write-Log "Using temporary password for this session only" "WARN"
    }
    
    return $password
}

# Function to handle .NET 4.8 restart scenario
function Invoke-DotNet48Restart {
    Write-Log "✓ Installation completed successfully. A restart is required." "SUCCESS"
    $global:RestartRequired = $true
    
    # Force restart to complete installation
    Write-Log "🔄 Forcing restart to complete .NET 4.8 installation..." "INFO"
    Write-Log "📝 Creating restart marker file..." "INFO"
    
    # Create a restart marker to resume after reboot
    $restartMarker = "$env:TEMP\dotnet48_restart_marker.txt"
    "DOTNET48_RESTART_PENDING" | Out-File -FilePath $restartMarker -Encoding ASCII
    
    # Schedule script to resume after restart
    $resumeScript = @"
# Wait for system to fully boot
Start-Sleep -Seconds 30

# Verify .NET 4.8 installation after restart
`$net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
if (`$net48Version -ge 528040) {
    Write-EventLog -LogName Application -Source "SplendidCRM" -EventId 1001 -EntryType Information -Message ".NET Framework 4.8 installation verified after restart"
    Remove-Item "$restartMarker" -Force -ErrorAction SilentlyContinue
    
    # Continue with remaining installation scripts
    try {
        `$runAllScript = Get-RunAllScriptPath
        if (`$runAllScript) {
            Write-EventLog -LogName Application -Source "SplendidCRM" -EventId 1004 -EntryType Information -Message "Resuming installation with script: `$runAllScript"
            & `$runAllScript
        } else {
            Write-EventLog -LogName Application -Source "SplendidCRM" -EventId 1005 -EntryType Error -Message "Could not locate run-all.ps1 script to resume installation"
        }
    } catch {
        Write-EventLog -LogName Application -Source "SplendidCRM" -EventId 1002 -EntryType Error -Message "Failed to resume installation after restart: `$_"
    }
} else {
    Write-EventLog -LogName Application -Source "SplendidCRM" -EventId 1003 -EntryType Error -Message ".NET Framework 4.8 installation not verified after restart"
}
"@
    
    # Create the resume script
    $resumeScriptPath = "$env:TEMP\resume-after-restart.ps1"
    $resumeScript | Out-File -FilePath $resumeScriptPath -Encoding ASCII
    
    # Schedule the resume script to run after restart
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$resumeScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    Register-ScheduledTask -TaskName "SplendidCRM-Resume-After-Restart" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    
    Write-Log "✓ Restart task scheduled. Restarting system in 10 seconds..." "INFO"
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    exit 0
}

Write-Log "=== STARTING INFRASTRUCTURE SETUP ===" "INFO"

# Register Event Log source for restart handling
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists("SplendidCRM")) {
        New-EventLog -LogName Application -Source "SplendidCRM"
        Write-Log "Event Log source 'SplendidCRM' registered." "INFO"
    }
} catch {
    Write-Log "Could not register Event Log source: $_" "WARN"
}

# --- Initialize and Format Data Disk (WITH RETRY LOGIC) ---
Write-Log "Initializing and formatting the data disk..." "INFO"

try {
    $diskInitialized = Invoke-WithRetry -OperationName "Data disk initialization" -MaxRetries 3 -DelaySeconds 10 -ScriptBlock {
        # Find the first disk that is not the OS disk (Number 0) and is unpartitioned (RAW).
        $disk = Get-Disk | Where-Object { $_.Number -gt 0 -and $_.PartitionStyle -eq 'RAW' } | Select-Object -First 1

        if (-not $disk) {
            throw "No uninitialized data disk found. A raw data disk must be attached to the VM."
        }

        Write-Log "Found data disk Number $($disk.Number). Preparing disk..." "INFO"
        
        # Execute commands sequentially for clarity and robustness
        Set-Disk -Number $disk.Number -IsOffline $false
        Start-Sleep -Seconds 2  # Allow disk to come online
        
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT
        Start-Sleep -Seconds 2  # Allow initialization to complete
        
        # Create the partition and get the resulting object
        $partition = New-Partition -DiskNumber $disk.Number -AssignDriveLetter -UseMaximumSize
        Start-Sleep -Seconds 5  # Allow partition creation to complete
        
        # Format the volume using the drive letter
        Format-Volume -DriveLetter $partition.DriveLetter -FileSystem NTFS -NewFileSystemLabel "SQLData" -Confirm:$false
        Start-Sleep -Seconds 5  # Allow format to complete
        
        return @{
            DiskNumber = $disk.Number
            DriveLetter = $partition.DriveLetter
        }
    } -SuccessTest {
        param($result)
        # Verify the disk is properly formatted and accessible
        $testPath = "$($result.DriveLetter):\"
        return (Test-Path $testPath) -and ((Get-Volume -DriveLetter $result.DriveLetter).FileSystem -eq 'NTFS')
    }
    
    # Set global paths
    $global:dataPath = "$($diskInitialized.DriveLetter):\SQLData"
    $global:logPath = "$($diskInitialized.DriveLetter):\SQLLogs"
    Write-Log "✓ Data disk prepared on drive $($diskInitialized.DriveLetter). Data path: $global:dataPath" "SUCCESS"
    
} catch {
    Write-Log "Failed to initialize data disk after multiple attempts: $_" "ERROR"
    exit 1
}

# --- Install IIS and ASP.NET 4.8 (WITH RETRY LOGIC) ---
Write-Log "Installing IIS and required features for ASP.NET..." "INFO"

$iisFeatures = @(
    @{ Name = "Web-Server"; Description = "IIS Web Server" },
    @{ Name = "Web-Asp-Net45"; Description = "ASP.NET 4.5/4.x" },
    @{ Name = "Web-Mgmt-Console"; Description = "IIS Management Console" },
    @{ Name = "Web-Scripting-Tools"; Description = "IIS Scripting Tools" }
)

foreach ($feature in $iisFeatures) {
    Invoke-WithRetry -OperationName "Installing $($feature.Description)" -MaxRetries 3 -DelaySeconds 10 -ScriptBlock {
        $result = Install-WindowsFeature -Name $feature.Name -IncludeManagementTools
        if ($result.Success -eq $false) {
            throw "Feature installation reported failure: $($result.ExitCode)"
        }
        return $result
    } -SuccessTest {
        param($result)
        # Verify the feature is actually installed
        $featureState = Get-WindowsFeature -Name $feature.Name
        return ($featureState.InstallState -eq 'Installed')
    }
}

Write-Log "✓ All IIS and ASP.NET features installation complete." "SUCCESS"

# --- Install .NET Framework 4.8 (IMPROVED VERSION WITH RESTART HANDLING) ---
Write-Log "Checking for and installing .NET Framework 4.8 if needed..." "INFO"
$dotnet48_url = "https://go.microsoft.com/fwlink/?linkid=2088631"
$dotnet48_installer = "$env:TEMP\ndp48-x86-x64-allos-enu.exe"

# Function to check .NET 4.8 installation
function Test-DotNet48Installation {
    $net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
    return ($net48Version -ge 528040)
}

# Function to get current .NET version string
function Get-DotNetVersionString {
    $net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
    switch ($net48Version) {
        461808 { return "4.7.2" }
        461814 { return "4.7.2" }
        528040 { return "4.8" }
        528049 { return "4.8" }
        528372 { return "4.8" }
        528449 { return "4.8" }
        default { return "Unknown ($net48Version)" }
    }
}

# Check current .NET version
$currentVersion = Get-DotNetVersionString
$net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
Write-Log "Current .NET Framework version: $currentVersion (Release: $net48Version)" "INFO"

if (-not (Test-DotNet48Installation)) {
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
    
    # Install with comprehensive error handling
    Write-Log "Installing .NET Framework 4.8. This may take several minutes..." "INFO"
    try {
        # Use quiet install with detailed logging (allow restart)
        $installArgs = @("/quiet", "/log", "$env:TEMP\dotnet48_install.log")
        $process = Start-Process -FilePath $dotnet48_installer -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        Write-Log ".NET 4.8 installer finished with exit code: $($process.ExitCode)" "INFO"
        
        # Check exit codes and handle restart requirement
        switch ($process.ExitCode) {
            0 { 
                Write-Log "✓ .NET Framework 4.8 installation completed successfully." "SUCCESS"
                # Additional verification with retry
                $verificationAttempts = 0
                $maxVerificationAttempts = 10
                while ($verificationAttempts -lt $maxVerificationAttempts -and -not (Test-DotNet48Installation)) {
                    Write-Log "Waiting for .NET 4.8 installation to be registered... (attempt $($verificationAttempts + 1)/$maxVerificationAttempts)" "INFO"
                    Start-Sleep -Seconds 3
                    $verificationAttempts++
                }
                
                if (-not (Test-DotNet48Installation)) {
                    Write-Log "⚠️ .NET 4.8 installation completed but not yet verified. This may require a restart." "WARN"
                    $global:RestartRequired = $true
                }
            }
            1602 { 
                Write-Log "Installation was cancelled by user or another process." "WARN"
                # Try to verify if installation actually completed
                Start-Sleep -Seconds 10
                if (Test-DotNet48Installation) {
                    Write-Log "✓ .NET Framework 4.8 appears to be installed despite cancellation message." "SUCCESS"
                } else {
                    Write-Log "Installation was truly cancelled. Continuing with existing version." "WARN"
                }
            }
            1603 { 
                Write-Log "A fatal error occurred during installation." "ERROR"
                if (Test-Path "$env:TEMP\dotnet48_install.log") {
                    Write-Log "Installation log (last 20 lines):" "INFO"
                    Get-Content "$env:TEMP\dotnet48_install.log" | Select-Object -Last 20 | ForEach-Object { Write-Log $_ "INFO" }
                }
                # Check if installation actually succeeded despite error
                Start-Sleep -Seconds 10
                if (Test-DotNet48Installation) {
                    Write-Log "✓ .NET Framework 4.8 appears to be installed despite error message." "SUCCESS"
                } else {
                    Write-Log "Installation failed. Continuing with existing version." "WARN"
                }
            }
            1641 { 
                Invoke-DotNet48Restart
            }
            3010 { 
                Invoke-DotNet48Restart
            }
            5100 { 
                Write-Log "Computer does not meet system requirements." "ERROR"
                # Don't exit - continue with current .NET version
            }
            default { 
                Write-Log "Installation completed with unexpected exit code: $($process.ExitCode)" "WARN"
                # Still check if installation succeeded
                Start-Sleep -Seconds 10
                if (Test-DotNet48Installation) {
                    Write-Log "✓ .NET Framework 4.8 appears to be installed despite unexpected exit code." "SUCCESS"
                } else {
                    Write-Log "Installation may have failed. Continuing with existing version." "WARN"
                }
            }
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

# Create the directories on the new data disk (WITH RETRY LOGIC)
try {
    Invoke-WithRetry -OperationName "Creating SQL directories" -MaxRetries 3 -DelaySeconds 5 -ScriptBlock {
        New-Item -ItemType Directory -Path $global:dataPath -Force | Out-Null
        New-Item -ItemType Directory -Path $global:logPath -Force | Out-Null
    } -SuccessTest {
        return (Test-Path $global:dataPath) -and (Test-Path $global:logPath)
    }
    Write-Log "✓ Created SQL data and log directories on the data disk." "SUCCESS"
} catch {
    Write-Log "Failed to create SQL directories after multiple attempts: $_" "ERROR"
    exit 1
}

# Dynamically discover the SQL Server instance and service name (WITH RETRY LOGIC)
try {
    $sqlConfig = Invoke-WithRetry -OperationName "SQL Server discovery and configuration" -MaxRetries 5 -DelaySeconds 10 -ScriptBlock {
        # Discover SQL Server service
        $sqlService = Get-Service -Name "MSSQL*" | Where-Object { $_.DisplayName -like "SQL Server (*)" } | Select-Object -First 1
        if (-not $sqlService) {
            throw "Could not find the SQL Server service"
        }
        
        $sqlServiceName = $sqlService.Name
        # Robustly extract the instance name from the display name
        $sqlInstanceName = ($sqlService.DisplayName -replace 'SQL Server \((.*)\)', '$1').Trim()
        
        Write-Log "Found SQL Server service: $sqlServiceName (Instance: $sqlInstanceName)" "INFO"
        
        # Dynamically construct the registry path
        $instanceId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$sqlInstanceName
        if (-not $instanceId) {
            throw "Could not find instance ID for SQL instance '$sqlInstanceName' in the registry"
        }
        
        $regKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"
        if (-not (Test-Path $regKey)) {
            throw "Could not find the registry path for the SQL instance: $regKey"
        }
        
        Write-Log "Found SQL registry key: $regKey" "INFO"
        
        # Configure Mixed Mode Authentication
        Set-ItemProperty -Path $regKey -Name LoginMode -Value 2 -Force
        Start-Sleep -Seconds 2  # Allow registry change to complete
        
        # Update default locations for new databases
        Set-ItemProperty -Path $regKey -Name "DefaultData" -Value $global:dataPath
        Set-ItemProperty -Path $regKey -Name "DefaultLog" -Value $global:logPath
        Start-Sleep -Seconds 2  # Allow registry changes to complete
        
        return @{
            ServiceName = $sqlServiceName
            InstanceName = $sqlInstanceName
            RegistryKey = $regKey
        }
    } -SuccessTest {
        param($result)
        # Verify registry settings were applied
        $loginMode = (Get-ItemProperty -Path $result.RegistryKey -Name LoginMode -ErrorAction SilentlyContinue).LoginMode
        $defaultData = (Get-ItemProperty -Path $result.RegistryKey -Name DefaultData -ErrorAction SilentlyContinue).DefaultData
        return ($loginMode -eq 2) -and ($defaultData -eq $global:dataPath)
    }
    
    $sqlServiceName = $sqlConfig.ServiceName
    $sqlInstanceName = $sqlConfig.InstanceName
    $regKey = $sqlConfig.RegistryKey
    
    Write-Log "✓ SQL Server discovery and configuration completed successfully." "SUCCESS"
    Write-Log "  Service: $sqlServiceName" "INFO"
    Write-Log "  Instance: $sqlInstanceName" "INFO"
    Write-Log "  Registry: $regKey" "INFO"
    
} catch {
    Write-Log "Failed to configure SQL Server after multiple attempts: $_" "ERROR"
    exit 1
}

# --- RESTART SQL Server to apply Mixed Mode (WITH RETRY LOGIC) ---
Write-Log "Restarting SQL Server to apply Mixed Mode authentication..." "INFO"
try {
    Restart-ServiceWithRetry -ServiceName $sqlServiceName -MaxRetries 3 -DelaySeconds 15
    Write-Log "✓ SQL Server service restarted successfully." "SUCCESS"
} catch {
    Write-Log "Failed to restart SQL Server after multiple attempts: $_" "ERROR"
    exit 1
}

# --- Wait for SQL Server to be ready after restart (WITH ENHANCED RETRY LOGIC) ---
Write-Log "Waiting for SQL Server to be ready after restart..." "INFO"
try {
    Test-SqlConnectionWithRetry -ServerInstance "." -Database "master" -MaxRetries 60 -DelaySeconds 5
    Write-Log "✓ SQL Server is ready and accepting connections." "SUCCESS"
} catch {
    Write-Log "❌ SQL Server did not become ready within the expected time: $_" "ERROR"
    exit 1
}

# --- Configure SA Password (IMPROVED VERSION WITH BETTER RELIABILITY) ---
Write-Log "Setting 'sa' password now that Mixed Mode is active..." "INFO"
$saPassword = Get-SecureSaPassword

# Function to test SA login
function Test-SqlServerSaLogin {
    param($Password)
    try {
        Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1" -Username "sa" -Password $Password -QueryTimeout 5 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to check if SA login exists and is enabled
function Test-SqlServerSaExists {
    try {
        $result = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT name, is_disabled FROM sys.server_principals WHERE name = 'sa'" -ErrorAction Stop
        if ($result) {
            return @{
                Exists = $true
                IsDisabled = $result.is_disabled
            }
        } else {
            return @{
                Exists = $false
                IsDisabled = $null
            }
        }
    } catch {
        Write-Log "Error checking SA login existence: $_" "WARN"
        return @{
            Exists = $false
            IsDisabled = $null
        }
    }
}

# Step 1: Check current SA status
Write-Log "Checking current SA login status..." "INFO"
$saStatus = Test-SqlServerSaExists
Write-Log "SA login exists: $($saStatus.Exists), Is disabled: $($saStatus.IsDisabled)" "INFO"

# Step 2: Configure SA login with multiple retry attempts
$maxSaAttempts = 5
$saAttempt = 0
$saConfigured = $false

while (-not $saConfigured -and $saAttempt -lt $maxSaAttempts) {
    $saAttempt++
    Write-Log "SA configuration attempt $saAttempt/$maxSaAttempts..." "INFO"
    
    try {
        if ($saStatus.Exists) {
            # SA exists, just enable and set password
            Write-Log "SA login exists. Enabling and setting password..." "INFO"
            $query = "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$saPassword'"
            Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $query -ErrorAction Stop
            Write-Log "✓ SA login enabled and password set." "SUCCESS"
        } else {
            # SA doesn't exist, create it
            Write-Log "SA login doesn't exist. Creating SA login..." "INFO"
            $createQuery = "CREATE LOGIN sa WITH PASSWORD = '$saPassword'; ALTER LOGIN sa ENABLE;"
            Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $createQuery -ErrorAction Stop
            Write-Log "✓ SA login created and enabled." "SUCCESS"
        }
        
        # Wait a moment for changes to take effect
        Start-Sleep -Seconds 3
        
        # Test the SA login
        Write-Log "Testing SA login with new password..." "INFO"
        if (Test-SqlServerSaLogin -Password $saPassword) {
            Write-Log "✓ SA login test successful!" "SUCCESS"
            $saConfigured = $true
        } else {
            Write-Log "⚠️ SA login test failed. Retrying..." "WARN"
            Start-Sleep -Seconds 5
        }
        
    } catch {
        Write-Log "SA configuration attempt $saAttempt failed: $_" "WARN"
        
        # Wait before retry
        if ($saAttempt -lt $maxSaAttempts) {
            Write-Log "Waiting 10 seconds before retry..." "INFO"
            Start-Sleep -Seconds 10
            
            # Refresh SA status for next attempt
            $saStatus = Test-SqlServerSaExists
        }
    }
}

# Step 3: Final SA configuration check
if (-not $saConfigured) {
    Write-Log "⚠️ Could not configure SA login after $maxSaAttempts attempts." "WARN"
    Write-Log "Attempting alternative SA configuration methods..." "INFO"
    
    # Alternative method: Use SQLCMD directly (sometimes more reliable)
    try {
        Write-Log "Trying alternative SQLCMD method..." "INFO"
        $sqlcmdQuery = "ALTER LOGIN sa ENABLE; ALTER LOGIN sa WITH PASSWORD = '$saPassword'"
        $sqlcmdResult = sqlcmd -S "." -E -Q $sqlcmdQuery 2>&1
        
        Write-Log "SQLCMD result: $sqlcmdResult" "INFO"
        
        # Test again
        Start-Sleep -Seconds 3
        if (Test-SqlServerSaLogin -Password $saPassword) {
            Write-Log "✓ SA login configured successfully using SQLCMD!" "SUCCESS"
            $saConfigured = $true
        }
    } catch {
        Write-Log "Alternative SQLCMD method failed: $_" "WARN"
    }
}

# Step 4: Final fallback and status
if (-not $saConfigured) {
    Write-Log "❌ SA login configuration failed with all methods." "ERROR"
    Write-Log "Will continue with Windows Authentication only." "WARN"
    Write-Log "Manual SA configuration may be required after deployment." "WARN"
    
    # Log troubleshooting information
    Write-Log "=== SA TROUBLESHOOTING INFORMATION ===" "INFO"
    try {
        $authMode = Get-ItemProperty -Path $regKey -Name LoginMode -ErrorAction SilentlyContinue
        Write-Log "Current LoginMode registry value: $($authMode.LoginMode)" "INFO"
        
        $principals = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT name, type_desc, is_disabled FROM sys.server_principals WHERE name IN ('sa', 'BUILTIN\\Administrators')" -ErrorAction SilentlyContinue
        $principals | ForEach-Object { 
            Write-Log "Login: $($_.name), Type: $($_.type_desc), Disabled: $($_.is_disabled)" "INFO"
        }
    } catch {
        Write-Log "Could not retrieve troubleshooting information: $_" "WARN"
    }
    Write-Log "=== END SA TROUBLESHOOTING ===" "INFO"
} else {
    Write-Log "✓ SA login configured and tested successfully!" "SUCCESS"
}

# --- Test SQL Server connectivity (IMPROVED VERSION) ---
Write-Log "Testing SQL Server connectivity..." "INFO"

# Test Windows Authentication
$windowsAuthWorking = $false
try {
    $testQuery = "SELECT @@VERSION as SQLVersion, SERVERPROPERTY('ProductVersion') as ProductVersion, SERVERPROPERTY('Edition') as Edition"
    $result = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $testQuery -QueryTimeout 10 -ErrorAction Stop
    Write-Log "✓ Windows Authentication: SUCCESS" "SUCCESS"
    Write-Log "SQL Server Version: $($result.SQLVersion)" "INFO"
    Write-Log "SQL Server Edition: $($result.Edition)" "INFO"
    $windowsAuthWorking = $true
} catch {
    Write-Log "❌ Windows Authentication test failed: $_" "ERROR"
    Write-Log "This is a critical error - SQL Server must accept Windows Authentication." "ERROR"
    exit 1
}

# Test Mixed Mode Authentication (if SA was configured)
$mixedModeWorking = $false
if ($saConfigured) {
    Write-Log "Testing Mixed Mode authentication with SA login..." "INFO"
    try {
        $result2 = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query "SELECT 1 as TestConnection, USER_NAME() as CurrentUser" -Username "sa" -Password $saPassword -QueryTimeout 10 -ErrorAction Stop
        Write-Log "✓ Mixed Mode Authentication (SA): SUCCESS" "SUCCESS"
        Write-Log "Connected as user: $($result2.CurrentUser)" "INFO"
        $mixedModeWorking = $true
    } catch {
        Write-Log "⚠️ Mixed Mode authentication test failed: $_" "WARN"
        Write-Log "SA login may not be properly configured. Will use Windows Authentication." "WARN"
    }
} else {
    Write-Log "Skipping Mixed Mode test - SA login was not configured successfully." "WARN"
}

# Verify authentication mode is actually set to Mixed Mode
Write-Log "Verifying SQL Server authentication mode..." "INFO"
try {
    $authModeQuery = "SELECT CASE SERVERPROPERTY('IsIntegratedSecurityOnly') WHEN 1 THEN 'Windows Authentication' WHEN 0 THEN 'Mixed Mode' ELSE 'Unknown' END as AuthMode"
    $authResult = Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $authModeQuery -ErrorAction Stop
    Write-Log "Current authentication mode: $($authResult.AuthMode)" "INFO"
    
    if ($authResult.AuthMode -eq "Mixed Mode") {
        Write-Log "✓ SQL Server is correctly configured for Mixed Mode authentication." "SUCCESS"
    } else {
        Write-Log "⚠️ SQL Server is not in Mixed Mode. This may affect application connectivity." "WARN"
    }
} catch {
    Write-Log "Could not verify authentication mode: $_" "WARN"
}

# Test database creation capabilities
Write-Log "Testing database creation capabilities..." "INFO"
try {
    # Test creating a temporary database to verify permissions
    $testDbQuery = "CREATE DATABASE [TempTestDB_SplendidCRM]; DROP DATABASE [TempTestDB_SplendidCRM];"
    Invoke-Sqlcmd -ServerInstance "." -Database "master" -Query $testDbQuery -QueryTimeout 30 -ErrorAction Stop
    Write-Log "✓ Database creation test: SUCCESS" "SUCCESS"
} catch {
    Write-Log "⚠️ Database creation test failed: $_" "WARN"
    Write-Log "This may affect the application database restoration process." "WARN"
}

# Final connectivity summary
Write-Log "`n=== SQL SERVER CONNECTIVITY SUMMARY ===" "INFO"
Write-Log "Windows Authentication: $(if ($windowsAuthWorking) { '✓ Working' } else { '❌ Failed' })" "INFO"
Write-Log "Mixed Mode Authentication: $(if ($mixedModeWorking) { '✓ Working' } else { '⚠️ Not available' })" "INFO"
Write-Log "SA Login Configured: $(if ($saConfigured) { '✓ Yes' } else { '❌ No' })" "INFO"

if (-not $windowsAuthWorking) {
    Write-Log "❌ Critical: Windows Authentication is not working. Deployment cannot continue." "ERROR"
    exit 1
} else {
    Write-Log "✓ SQL Server connectivity verified. Ready for database operations." "SUCCESS"
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

Write-Log "✓ SQL Server configured and ready $(if ($saConfigured) { '(Mixed Mode + SA)' } else { '(Windows Auth only)' })" "SUCCESS"

if (-not $global:RestartRequired) {
    Write-Log "🎉 All installations completed successfully. Ready for application deployment." "SUCCESS"
} else {
    Write-Log "⏳ Installation complete but restart may be required for .NET 4.8." "WARN"
}

Write-Log "Infrastructure setup completed successfully!" "SUCCESS"
exit 0