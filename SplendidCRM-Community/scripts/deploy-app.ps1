# PowerShell Script to Download and Deploy SplendidCRM Application

# --- Configuration ---
$repoUrl = "https://github.com/splendidcrm/SplendidCRM-Community-Edition/archive/refs/heads/master.zip"
$tempDir = "$env:TEMP\SplendidCRM-Deploy"
$tempZipFile = "$tempDir\SplendidCRM.zip"
$webRoot = "C:\inetpub\wwwroot"

# --- Preparation ---
Write-Host "Preparing for deployment..."
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir

# --- Download Application with Retry Logic ---
Write-Host "Downloading SplendidCRM from $repoUrl..."
$maxRetries = 3
$retryCount = 0
$downloadSuccess = $false

while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
    try {
        Invoke-WebRequest -Uri $repoUrl -OutFile $tempZipFile -TimeoutSec 300 -ErrorAction Stop
        $downloadSuccess = $true
        Write-Host "Download complete."
    } catch {
        $retryCount++
        Write-Warning "Download attempt $retryCount failed: $_"
        if ($retryCount -lt $maxRetries) {
            Write-Host "Retrying in 10 seconds..."
            Start-Sleep -Seconds 10
        }
    }
}

if (-not $downloadSuccess) {
    Write-Error "Failed to download after $maxRetries attempts. Halting deployment."
    exit 1
}

# --- Extract Application ---
Write-Host "Extracting application files..."
try {
    Expand-Archive -Path $tempZipFile -DestinationPath $tempDir -Force
    Write-Host "Extraction complete."
} catch {
    Write-Error "Failed to extract archive: $_"
    exit 1
}

# --- Find Application Source with Multiple Strategies ---
Write-Host "Locating application source folder..."
$appSourcePath = $null

# Strategy 1: Look for the expected GitHub folder pattern
$extractedFolder = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like '*SplendidCRM*' } | Select-Object -First 1
if ($extractedFolder) {
    $appSourcePath = $extractedFolder.FullName
    Write-Host "Found application folder: $($extractedFolder.Name)"
}

# Strategy 2: Look for web.config to identify the correct folder
if (-not $appSourcePath) {
    Write-Host "Searching for web.config to locate application root..."
    $webConfigPaths = Get-ChildItem -Path $tempDir -Recurse -Filter "web.config" -File
    foreach ($webConfigPath in $webConfigPaths) {
        $parentFolder = $webConfigPath.Directory.FullName
        # Check if this looks like the main application folder (has bin, App_Code, etc.)
        if ((Test-Path "$parentFolder\bin") -or (Test-Path "$parentFolder\App_Code")) {
            $appSourcePath = $parentFolder
            Write-Host "Found application root via web.config: $appSourcePath"
            break
        }
    }
}

if (-not $appSourcePath -or -not (Test-Path $appSourcePath)) {
    Write-Error "Could not locate the application source folder. Available folders:"
    Get-ChildItem -Path $tempDir -Recurse -Directory | ForEach-Object { Write-Host "  $($_.FullName)" }
    exit 1
}

# --- Backup Current Web Root ---
$backupPath = "$env:TEMP\wwwroot_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Write-Host "Creating backup of current web root at: $backupPath"
try {
    if (Test-Path $webRoot) {
        Copy-Item -Path $webRoot -Destination $backupPath -Recurse -Force
        Write-Host "Backup created successfully."
    }
} catch {
    Write-Warning "Could not create backup: $_"
}

# --- Deploy to IIS ---
Write-Host "Deploying application to IIS web root: $webRoot"

# Clear existing default IIS content
Write-Host "Clearing existing content from $webRoot..."
try {
    Get-ChildItem -Path $webRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Some files could not be removed: $_"
}

# Copy application files from the correct folder
Write-Host "Copying SplendidCRM files from $appSourcePath..."
try {
    Copy-Item -Path "$appSourcePath\*" -Destination $webRoot -Recurse -Force
    Write-Host "Application files copied successfully."
} catch {
    Write-Error "Failed to copy application files: $_"
    
    # Attempt to restore backup
    if (Test-Path $backupPath) {
        Write-Host "Attempting to restore backup..."
        Copy-Item -Path "$backupPath\*" -Destination $webRoot -Recurse -Force
    }
    exit 1
}

# --- Configure Database Connection ---
Write-Host "Updating web.config with local SQL Server connection string..."
$webConfigFile = Join-Path $webRoot "web.config"
if (-not (Test-Path $webConfigFile)) {
    Write-Error "web.config not found at $webConfigFile. Halting configuration."
    exit 1
}

# Create backup of web.config
$webConfigBackup = "$webConfigFile.backup"
Copy-Item -Path $webConfigFile -Destination $webConfigBackup -Force

try {
    # Load the XML content with proper error handling
    [xml]$webConfig = Get-Content $webConfigFile -ErrorAction Stop
    
    # Define the new connection string
    $newConnString = "Data Source=(local);Initial Catalog=SplendidCRM;User ID=sa;Password=splendidcrm2005;Encrypt=False;TrustServerCertificate=True"
    
    # Multiple strategies to find and update connection string
    $updated = $false
    
    # Strategy 1: Look for SplendidCRM connection string
    if ($webConfig.configuration.connectionStrings) {
        $connStringNode = $webConfig.configuration.connectionStrings.add | Where-Object { $_.name -eq 'SplendidCRM' }
        if ($connStringNode) {
            $connStringNode.connectionString = $newConnString
            $updated = $true
            Write-Host "Updated existing 'SplendidCRM' connection string."
        }
    }
    
    # Strategy 2: Look for any connection string and update the first one
    if (-not $updated -and $webConfig.configuration.connectionStrings) {
        $firstConnString = $webConfig.configuration.connectionStrings.add | Select-Object -First 1
        if ($firstConnString) {
            $firstConnString.connectionString = $newConnString
            $updated = $true
            Write-Host "Updated first available connection string: $($firstConnString.name)"
        }
    }
    
    # Strategy 3: Create the connectionStrings section if it doesn't exist
    if (-not $updated) {
        if (-not $webConfig.configuration.connectionStrings) {
            $connStringsElement = $webConfig.CreateElement("connectionStrings")
            $webConfig.configuration.AppendChild($connStringsElement)
        }
        
        $addElement = $webConfig.CreateElement("add")
        $addElement.SetAttribute("name", "SplendidCRM")
        $addElement.SetAttribute("connectionString", $newConnString)
        $webConfig.configuration.connectionStrings.AppendChild($addElement)
        $updated = $true
        Write-Host "Created new 'SplendidCRM' connection string."
    }
    
    if ($updated) {
        # Save the modified XML back to the file
        $webConfig.Save($webConfigFile)
        Write-Host "web.config connection string updated successfully."
    } else {
        Write-Warning "Could not update connection string in web.config."
    }
    
} catch {
    Write-Error "Failed to update web.config: $_"
    # Restore backup
    if (Test-Path $webConfigBackup) {
        Copy-Item -Path $webConfigBackup -Destination $webConfigFile -Force
        Write-Host "Restored web.config backup."
    }
    exit 1
}

# --- Configure IIS Application and Application Pool ---
Write-Host "Configuring IIS Application and Application Pool..."
try {
    Import-Module WebAdministration -ErrorAction Stop
    
    # Create a dedicated application pool for SplendidCRM
    $appPoolName = "SplendidCRM_AppPool"
    
    # Remove existing app pool if it exists
    if (Get-IISAppPool -Name $appPoolName -ErrorAction SilentlyContinue) {
        Write-Host "Removing existing application pool: $appPoolName"
        Remove-WebAppPool -Name $appPoolName
    }
    
    # Create new application pool with proper settings
    Write-Host "Creating application pool: $appPoolName"
    New-WebAppPool -Name $appPoolName
    
    # Configure application pool settings for .NET 4.8
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name managedRuntimeVersion -Value "v4.0"
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name enable32BitAppOnWin64 -Value $false
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name processModel.identityType -Value "ApplicationPoolIdentity"
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name recycling.periodicRestart.time -Value "00:00:00"  # Disable periodic restart
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name processModel.idleTimeout -Value "00:00:00"  # Disable idle timeout
    
    Write-Host "Application pool configured with .NET 4.0 framework."
    
    # Remove Default Web Site if it exists
    if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
        Write-Host "Removing Default Web Site"
        Remove-Website -Name "Default Web Site"
    }
    
    # Create the SplendidCRM web application
    $siteName = "SplendidCRM"
    $sitePort = 80
    
    # Remove existing site if it exists
    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Write-Host "Removing existing website: $siteName"
        Remove-Website -Name $siteName
    }
    
    # Create new website
    Write-Host "Creating website: $siteName"
    New-Website -Name $siteName -Port $sitePort -PhysicalPath $webRoot -ApplicationPool $appPoolName
    
    # Set proper permissions on the web directory
    Write-Host "Setting permissions on web directory..."
    
    # Give IIS_IUSRS read and execute permissions
    $acl = Get-Acl $webRoot
    $accessRule1 = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($accessRule1)
    
    # Give the application pool identity modify permissions to App_Data if it exists
    $appDataPath = Join-Path $webRoot "App_Data"
    if (Test-Path $appDataPath) {
        $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS AppPool\$appPoolName", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($accessRule2)
        Write-Host "Set modify permissions on App_Data folder."
    }
    
    # Apply permissions
    Set-Acl -Path $webRoot -AclObject $acl
    Write-Host "Permissions configured successfully."
    
    # Start the application pool and website
    Start-WebAppPool -Name $appPoolName
    Start-Website -Name $siteName
    
    Write-Host "IIS Application and Application Pool configured successfully."
    
} catch {
    Write-Error "Failed to configure IIS Application: $_"
    exit 1
}

# --- Verify Deployment ---
Write-Host "Verifying deployment..."
$requiredFiles = @("web.config", "default.aspx", "bin")
$missingFiles = @()

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $webRoot $file
    if (-not (Test-Path $filePath)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Warning "Some expected files/folders are missing: $($missingFiles -join ', ')"
} else {
    Write-Host "All required files are present."
}

# --- Test Web Application ---
Write-Host "Testing web application deployment..."
try {
    # Wait a moment for IIS to initialize
    Start-Sleep -Seconds 10
    
    # Test if the website is responding
    $testUrl = "http://localhost"
    Write-Host "Testing website at: $testUrl"
    
    try {
        $response = Invoke-WebRequest -Uri $testUrl -TimeoutSec 30 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✓ Website is responding successfully (Status: $($response.StatusCode))"
            
            # Check if it's actually the SplendidCRM app
            if ($response.Content -match "SplendidCRM|Splendid") {
                Write-Host "✓ SplendidCRM application detected in response"
            } else {
                Write-Warning "Website is responding but may not be showing SplendidCRM content"
            }
        } else {
            Write-Warning "Website responded with status code: $($response.StatusCode)"
        }
    } catch {
        Write-Warning "Website test failed: $_"
        Write-Host "This might be expected if the database isn't configured yet."
    }
    
    # Check application pool status
    $appPoolStatus = Get-WebAppPoolState -Name $appPoolName
    Write-Host "Application Pool Status: $($appPoolStatus.Value)"
    
    # Check website status
    $websiteStatus = Get-WebsiteState -Name $siteName
    Write-Host "Website Status: $($websiteStatus.Value)"
    
} catch {
    Write-Warning "Could not complete web application testing: $_"
}

# --- Display Configuration Summary ---
Write-Host "`n=== DEPLOYMENT SUMMARY ===" -ForegroundColor Yellow
Write-Host "✓ Application files deployed to: $webRoot"
Write-Host "✓ Website Name: $siteName"
Write-Host "✓ Application Pool: $appPoolName"
Write-Host "✓ Website URL: http://localhost"
Write-Host "✓ Physical Path: $webRoot"

# Show important next steps
Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
Write-Host "1. Ensure SQL Server database is restored"
Write-Host "2. Verify database connection string in web.config"
Write-Host "3. Test the application by browsing to http://localhost"
Write-Host "4. Check IIS logs if any issues: C:\inetpub\logs\LogFiles\"

Write-Host "Deployment script finished successfully."

# --- Cleanup ---
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "SplendidCRM application has been deployed and configured."
Write-Host "Backup location: $backupPath"