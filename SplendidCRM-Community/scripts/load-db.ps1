# PowerShell Script to Restore Production SplendidCRM Database from BACPAC
# Simulates real-world lift & shift migration scenario

# --- Configuration ---
$databaseName = "SplendidCRM"
$sqlServerInstance = "." # Local default instance
$saPassword = "splendidcrm2005"
$tempDir = "$env:TEMP\SplendidCRM-DB"

# Production-like BACPAC sources (ordered by preference)
$bacpacSources = @(
    @{
        "Name" = "Azure Storage Account"
        "Url" = "https://splendidcrmstorage.blob.core.windows.net/backups/SplendidCRM-Production.bacpac"
        "Description" = "Production backup from Azure Storage"
        "AuthRequired" = $true
    },
    @{
        "Name" = "GitHub Demo Repository" 
        "Url" = "https://github.com/jitangupta/AzureDemos/raw/main/SplendidCRM-Community/scripts/SplendidCRM.bacpac"
        "Description" = "Demo BACPAC from GitHub (raw file)"
        "AuthRequired" = $false
    },
    @{
        "Name" = "Alternative GitHub Location"
        "Url" = "https://raw.githubusercontent.com/jitangupta/AzureDemos/main/SplendidCRM-Community/scripts/SplendidCRM.bacpac"
        "Description" = "Alternative GitHub raw URL"
        "AuthRequired" = $false
    },
    @{
        "Name" = "DropBox/OneDrive Link"
        "Url" = "https://www.dropbox.com/s/example/SplendidCRM.bacpac?dl=1"
        "Description" = "Shared drive backup (update URL as needed)"
        "AuthRequired" = $false
    }
)

Write-Host "=== PRODUCTION LIFT & SHIFT MIGRATION ===" -ForegroundColor Yellow
Write-Host "Restoring SplendidCRM production database from BACPAC export..." -ForegroundColor Cyan
Write-Host "This simulates migrating an existing on-premises database to Azure VM" -ForegroundColor Gray

# --- Preparation ---
Write-Host "`nPreparing migration environment..."
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir

# --- Find SqlPackage.exe with Comprehensive Search ---
Write-Host "Locating SqlPackage.exe for BACPAC import..."
$sqlPackagePath = $null

# Strategy 1: Common SQL Server installation paths (ordered by version)
$commonPaths = @(
    "C:\Program Files\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",  # SQL 2022
    "C:\Program Files\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",  # SQL 2019
    "C:\Program Files\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe",  # SQL 2017
    "C:\Program Files\Microsoft SQL Server\130\DAC\bin\SqlPackage.exe",  # SQL 2016
    "C:\Program Files (x86)\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
    "C:\Program Files (x86)\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
    "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe"
)

foreach ($path in $commonPaths) {
    if (Test-Path $path) {
        $sqlPackagePath = $path
        Write-Host "✓ Found SqlPackage.exe at: $sqlPackagePath"
        break
    }
}

# Strategy 2: Search in SQL Server directories
if (-not $sqlPackagePath) {
    Write-Host "Searching SQL Server directories for SqlPackage.exe..."
    $sqlServerDirs = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $sqlServerDirs) {
        $searchPath = Join-Path $dir.FullName "DAC\bin\SqlPackage.exe"
        if (Test-Path $searchPath) {
            $sqlPackagePath = $searchPath
            Write-Host "✓ Found SqlPackage.exe at: $sqlPackagePath"
            break
        }
    }
}

# Strategy 3: Download SqlPackage if not found (production fallback)
if (-not $sqlPackagePath) {
    Write-Host "SqlPackage.exe not found locally. Downloading latest version..."
    try {
        $sqlPackageUrl = "https://aka.ms/sqlpackage-windows"
        $sqlPackageZip = "$tempDir\sqlpackage.zip"
        $sqlPackageExtractPath = "$tempDir\sqlpackage"
        
        Write-Host "Downloading SqlPackage from Microsoft..."
        Invoke-WebRequest -Uri $sqlPackageUrl -OutFile $sqlPackageZip -TimeoutSec 300 -UserAgent "PowerShell Migration Script"
        
        Write-Host "Extracting SqlPackage..."
        Expand-Archive -Path $sqlPackageZip -DestinationPath $sqlPackageExtractPath -Force
        
        $sqlPackagePath = Get-ChildItem -Path $sqlPackageExtractPath -Recurse -Filter "SqlPackage.exe" | Select-Object -First 1 | ForEach-Object { $_.FullName }
        
        if ($sqlPackagePath) {
            Write-Host "✓ Downloaded SqlPackage.exe to: $sqlPackagePath"
        }
    } catch {
        Write-Error "Failed to download SqlPackage.exe: $_"
        Write-Host "MANUAL STEP REQUIRED: Please install SQL Server Data Tools (SSDT) or download SqlPackage manually"
        exit 1
    }
}

if (-not $sqlPackagePath) {
    Write-Error "SqlPackage.exe is required for BACPAC import but was not found."
    Write-Host "Please install one of the following:"
    Write-Host "- SQL Server Management Studio (SSMS)"
    Write-Host "- SQL Server Data Tools (SSDT)"
    Write-Host "- Azure Data Studio"
    exit 1
}

# --- Ensure SQL Server is Running ---
Write-Host "`nEnsuring SQL Server is running..."
try {
    $sqlService = Get-Service -Name "MSSQL*" | Where-Object { $_.DisplayName -like "SQL Server (*)" } | Select-Object -First 1
    if ($sqlService) {
        if ($sqlService.Status -ne "Running") {
            Write-Host "Starting SQL Server service..."
            Start-Service -Name $sqlService.Name -ErrorAction Stop
            Write-Host "✓ SQL Server started: $($sqlService.Name)"
        } else {
            Write-Host "✓ SQL Server is running: $($sqlService.Name)"
        }
    } else {
        Write-Error "SQL Server service not found. Ensure SQL Server is installed."
        exit 1
    }
} catch {
    Write-Error "Failed to start SQL Server: $_"
    exit 1
}

# --- Wait for SQL Server Ready State ---
Write-Host "Waiting for SQL Server to accept connections..."
$maxAttempts = 30
$attempt = 0
$sqlReady = $false

while (-not $sqlReady -and $attempt -lt $maxAttempts) {
    try {
        Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database "master" -Query "SELECT @@VERSION" -QueryTimeout 5 -ErrorAction Stop | Out-Null
        $sqlReady = $true
        Write-Host "✓ SQL Server is ready for connections."
    } catch {
        $attempt++
        Write-Host "Waiting for SQL Server... (Attempt $attempt/$maxAttempts)"
        Start-Sleep -Seconds 5
    }
}

if (-not $sqlReady) {
    Write-Error "SQL Server failed to become ready within expected time."
    exit 1
}

# --- Handle Existing Database (Production Scenario) ---
Write-Host "`nChecking for existing database '$databaseName'..."
try {
    $existingDb = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query "SELECT name FROM sys.databases WHERE name = '$databaseName'" -ErrorAction Stop
    if ($existingDb) {
        Write-Host "⚠️  Database '$databaseName' already exists."
        Write-Host "In a real migration, this would be your target environment."
        
        # In production, you'd want to backup the existing database first
        Write-Host "Creating backup of existing database before migration..."
        $backupPath = "$tempDir\$databaseName-pre-migration-$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
        $backupQuery = "BACKUP DATABASE [$databaseName] TO DISK = '$backupPath'"
        
        try {
            Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query $backupQuery -QueryTimeout 300
            Write-Host "✓ Backup created: $backupPath"
        } catch {
            Write-Warning "Could not create backup: $_"
        }
        
        # Drop the existing database
        Write-Host "Dropping existing database for migration..."
        $dropQuery = @"
ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$databaseName];
"@
        Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query $dropQuery -ErrorAction Stop
        Write-Host "✓ Existing database removed."
    } else {
        Write-Host "✓ No existing database found. Proceeding with fresh import."
    }
} catch {
    Write-Warning "Could not check for existing database: $_"
}

# --- Download Production BACPAC ---
Write-Host "`nAttempting to download production BACPAC file..."
$downloadSuccess = $false
$bacpacFile = "$tempDir\SplendidCRM-Production.bacpac"

foreach ($source in $bacpacSources) {
    if ($downloadSuccess) { break }
    
    Write-Host "`nTrying source: $($source.Name)"
    Write-Host "URL: $($source.Url)"
    Write-Host "Description: $($source.Description)"
    
    try {
        # Test if URL is accessible
        Write-Host "Testing URL accessibility..."
        $headers = @{
            'User-Agent' = 'PowerShell Migration Script v1.0'
        }
        
        $testResponse = Invoke-WebRequest -Uri $source.Url -Method Head -Headers $headers -TimeoutSec 30 -ErrorAction Stop
        
        if ($testResponse.StatusCode -eq 200) {
            $contentLength = $testResponse.Headers.'Content-Length'
            $contentType = $testResponse.Headers.'Content-Type'
            
            Write-Host "✓ URL is accessible (Status: $($testResponse.StatusCode))"
            
            if ($contentLength) {
                $sizeMB = [math]::Round($contentLength / 1MB, 2)
                Write-Host "✓ File size: $sizeMB MB"
                
                if ($sizeMB -lt 0.1) {
                    Write-Warning "File seems too small to be a valid BACPAC"
                    continue
                }
            }
            
            # Download the file
            Write-Host "Downloading BACPAC file... (this may take several minutes)"
            Invoke-WebRequest -Uri $source.Url -OutFile $bacpacFile -Headers $headers -TimeoutSec 1800 -ErrorAction Stop
            
            # Verify download
            if (Test-Path $bacpacFile) {
                $downloadedSize = (Get-Item $bacpacFile).Length
                Write-Host "✓ Download complete. File size: $([math]::Round($downloadedSize / 1MB, 2)) MB"
                
                # Basic BACPAC validation (should start with PK)
                $fileHeader = Get-Content $bacpacFile -Encoding Byte -TotalCount 2
                if ($fileHeader[0] -eq 80 -and $fileHeader[1] -eq 75) { # PK signature
                    Write-Host "✓ File appears to be a valid ZIP/BACPAC archive"
                    $downloadSuccess = $true
                } else {
                    Write-Warning "Downloaded file doesn't appear to be a valid BACPAC"
                    Remove-Item $bacpacFile -Force
                }
            }
        } else {
            Write-Warning "URL returned status: $($testResponse.StatusCode)"
        }
    } catch {
        Write-Warning "Failed to download from $($source.Name): $_"
    }
}

if (-not $downloadSuccess) {
    Write-Error "Could not download BACPAC file from any source."
    Write-Host "`nFor a real migration, you would:"
    Write-Host "1. Export BACPAC from source SQL Server using SSMS or SqlPackage"
    Write-Host "2. Upload to Azure Storage Account or secure file share"
    Write-Host "3. Download during migration using this script"
    Write-Host "`nPlease provide a valid BACPAC file URL or path."
    exit 1
}

# --- Import BACPAC Database ---
Write-Host "`n=== IMPORTING PRODUCTION DATABASE ===" -ForegroundColor Yellow
Write-Host "Starting BACPAC import... (this typically takes 5-30 minutes)"

# Try multiple authentication methods
$connectionMethods = @(
    @{
        "Name" = "Windows Authentication"
        "Args" = "/tsn:`"$sqlServerInstance`""
    },
    @{
        "Name" = "SQL Authentication"
        "Args" = "/tsn:`"$sqlServerInstance`" /tu:`"sa`" /tp:`"$saPassword`""
    }
)

$importSuccess = $false
foreach ($method in $connectionMethods) {
    if ($importSuccess) { break }
    
    Write-Host "`nAttempting import with $($method.Name)..."
    
    # Construct SqlPackage arguments
    $arguments = @(
        "/a:Import",
        "/sf:`"$bacpacFile`"",
        $method.Args,
        "/tdn:`"$databaseName`"",
        "/p:BlockOnPossibleDataLoss=true",
        "/p:Storage=File",
        "/p:CommandTimeout=7200",  # 2 hours
        "/p:DatabaseServiceObjective=Basic",
        "/p:DatabaseEdition=Basic"
    )
    
    # Create log files for troubleshooting
    $outputLog = "$tempDir\import_output_$(Get-Date -Format 'HHmmss').log"
    $errorLog = "$tempDir\import_error_$(Get-Date -Format 'HHmmss').log"
    
    try {
        Write-Host "Executing SqlPackage.exe..."
        Write-Host "Command: $sqlPackagePath $($arguments -join ' ')"
        
        $process = Start-Process -FilePath $sqlPackagePath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog
        
        Write-Host "SqlPackage completed with exit code: $($process.ExitCode)"
        
        # Show last few lines of output for troubleshooting
        if (Test-Path $outputLog) {
            $output = Get-Content $outputLog -Tail 5
            Write-Host "Last output lines:"
            $output | ForEach-Object { Write-Host "  $_" }
        }
        
        if ($process.ExitCode -eq 0) {
            Write-Host "✓ BACPAC import successful with $($method.Name)!" -ForegroundColor Green
            $importSuccess = $true
        } else {
            Write-Warning "Import failed with exit code: $($process.ExitCode)"
            if (Test-Path $errorLog) {
                $errors = Get-Content $errorLog
                Write-Host "Error details:"
                $errors | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            }
        }
    } catch {
        Write-Warning "Error executing SqlPackage: $_"
    }
}

if (-not $importSuccess) {
    Write-Error "BACPAC import failed with all authentication methods."
    Write-Host "Check log files in: $tempDir"
    Write-Host "Common issues:"
    Write-Host "- Insufficient SQL Server permissions"
    Write-Host "- BACPAC file corruption"
    Write-Host "- SQL Server version compatibility"
    Write-Host "- Insufficient disk space"
    exit 1
}

# --- Post-Import Verification ---
Write-Host "`n=== VERIFYING MIGRATION ===" -ForegroundColor Yellow

try {
    # Verify database exists
    $db = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query "SELECT name FROM sys.databases WHERE name = '$databaseName'"
    if (-not $db) {
        throw "Database not found after import"
    }
    Write-Host "✓ Database '$databaseName' exists"
    
    # Check table count
    $tableCount = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database $databaseName -Query "SELECT COUNT(*) as TableCount FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'"
    Write-Host "✓ Database contains $($tableCount.TableCount) tables"
    
    # Check for key SplendidCRM tables
    $keyTables = @('USERS', 'ACCOUNTS', 'CONTACTS', 'CONFIG', 'MODULES')
    foreach ($table in $keyTables) {
        $tableExists = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database $databaseName -Query "SELECT COUNT(*) as Exists FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$table'"
        if ($tableExists.Exists -gt 0) {
            Write-Host "✓ Key table '$table' found"
        } else {
            Write-Warning "Key table '$table' not found"
        }
    }
    
    # Check data counts
    try {
        $userCount = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database $databaseName -Query "SELECT COUNT(*) as UserCount FROM USERS"
        Write-Host "✓ Users in database: $($userCount.UserCount)"
    } catch {
        Write-Warning "Could not count users: $_"
    }
    
    # Optimize database for performance
    Write-Host "Optimizing database settings..."
    $optimizeQuery = @"
ALTER DATABASE [$databaseName] SET RECOVERY SIMPLE;
ALTER DATABASE [$databaseName] SET AUTO_SHRINK OFF;
ALTER DATABASE [$databaseName] SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE [$databaseName] SET AUTO_UPDATE_STATISTICS ON;
UPDATE STATISTICS [$databaseName];
"@
    Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query $optimizeQuery -QueryTimeout 300
    Write-Host "✓ Database optimized for performance"
    
} catch {
    Write-Error "Database verification failed: $_"
    exit 1
}

# --- Cleanup ---
Write-Host "`nCleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# --- Migration Summary ---
Write-Host "`n=== MIGRATION COMPLETED SUCCESSFULLY ===" -ForegroundColor Green
Write-Host "🎉 Production database has been migrated to Azure VM!" -ForegroundColor Green

Write-Host "`n--- Connection Details ---"
Write-Host "Database Name: $databaseName"
Write-Host "Server Instance: $sqlServerInstance"
Write-Host "Windows Auth: Data Source=$sqlServerInstance;Initial Catalog=$databaseName;Integrated Security=True"
Write-Host "SQL Auth: Data Source=$sqlServerInstance;Initial Catalog=$databaseName;User ID=sa;Password=$saPassword;Encrypt=False"

Write-Host "`n--- Next Steps ---"
Write-Host "1. ✓ Database migration complete"
Write-Host "2. → Update web.config connection string"
Write-Host "3. → Test application at http://localhost"
Write-Host "4. → Verify user logins and functionality"
Write-Host "5. → Configure SSL and security settings"
Write-Host "6. → Set up backup schedule"

Write-Host "`n--- Production Checklist ---"
Write-Host "□ Test all critical business functions"
Write-Host "□ Verify user authentication"
Write-Host "□ Check data integrity"
Write-Host "□ Configure monitoring"
Write-Host "□ Document connection strings"
Write-Host "□ Train operations team"

Write-Host "`nLift & Shift migration completed!" -ForegroundColor Cyan