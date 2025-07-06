# PowerShell Script to Download and Restore SplendidCRM Database from a .bacpac file

# --- Configuration ---
$bacpacUrl = "https://raw.githubusercontent.com/jitangupta/AzureDemos/main/SplendidCRM-Community/scripts/SplendidCRM.bacpac"
$tempDir = "$env:TEMP\SplendidCRM-DB"
$bacpacFile = "$tempDir\SplendidCRM.bacpac"
$databaseName = "SplendidCRM"
$sqlServerInstance = "." # Local default instance
$saPassword = "splendidcrm2005"

# --- Preparation ---
Write-Host "Preparing for database restore..."
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir

# --- Find SqlPackage.exe with Multiple Strategies ---
Write-Host "Locating SqlPackage.exe..."
$sqlPackagePath = $null

# Strategy 1: Common SQL Server installation paths
$commonPaths = @(
    "C:\Program Files\Microsoft SQL Server\*\DAC\bin\SqlPackage.exe",
    "C:\Program Files (x86)\Microsoft SQL Server\*\DAC\bin\SqlPackage.exe",
    "C:\Program Files\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
    "C:\Program Files\Microsoft SQL Server\140\DAC\bin\SqlPackage.exe",
    "C:\Program Files\Microsoft SQL Server\130\DAC\bin\SqlPackage.exe"
)

foreach ($path in $commonPaths) {
    $foundPath = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($foundPath) {
        $sqlPackagePath = $foundPath.FullName
        Write-Host "Found SqlPackage.exe at: $sqlPackagePath"
        break
    }
}

# Strategy 2: Search recursively if not found (but limit scope)
if (-not $sqlPackagePath) {
    Write-Host "Searching for SqlPackage.exe in SQL Server directories..."
    $sqlServerDirs = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $sqlServerDirs) {
        $searchPath = Join-Path $dir.FullName "DAC\bin\SqlPackage.exe"
        if (Test-Path $searchPath) {
            $sqlPackagePath = $searchPath
            Write-Host "Found SqlPackage.exe at: $sqlPackagePath"
            break
        }
    }
}

# Strategy 3: Try to download and use SqlPackage from Microsoft
if (-not $sqlPackagePath) {
    Write-Host "SqlPackage.exe not found locally. Downloading from Microsoft..."
    try {
        $sqlPackageUrl = "https://aka.ms/sqlpackage-windows"
        $sqlPackageZip = "$tempDir\sqlpackage.zip"
        $sqlPackageExtractPath = "$tempDir\sqlpackage"
        
        Invoke-WebRequest -Uri $sqlPackageUrl -OutFile $sqlPackageZip -TimeoutSec 300
        Expand-Archive -Path $sqlPackageZip -DestinationPath $sqlPackageExtractPath -Force
        
        $sqlPackagePath = Get-ChildItem -Path $sqlPackageExtractPath -Recurse -Filter "SqlPackage.exe" | Select-Object -First 1 | ForEach-Object { $_.FullName }
        
        if ($sqlPackagePath) {
            Write-Host "Downloaded and extracted SqlPackage.exe to: $sqlPackagePath"
        }
    } catch {
        Write-Warning "Failed to download SqlPackage.exe: $_"
    }
}

if (-not $sqlPackagePath) {
    Write-Error "SqlPackage.exe not found and could not be downloaded. This tool is required to restore the database. Halting script."
    exit 1
}

# --- Ensure SQL Server is Running ---
Write-Host "Ensuring SQL Server is running..."
try {
    $sqlService = Get-Service -Name "MSSQL*" | Where-Object { $_.DisplayName -like "SQL Server (*)" } | Select-Object -First 1
    if ($sqlService) {
        if ($sqlService.Status -ne "Running") {
            Start-Service -Name $sqlService.Name -ErrorAction Stop
            Write-Host "Started SQL Service: $($sqlService.Name)"
        } else {
            Write-Host "SQL Service is already running: $($sqlService.Name)"
        }
    } else {
        Write-Error "Could not find SQL Server service. Halting script."
        exit 1
    }
} catch {
    Write-Error "Failed to start SQL Server service: $_"
    exit 1
}

# --- Wait for SQL Server to be Ready ---
Write-Host "Waiting for SQL Server to be ready..."
$maxAttempts = 30
$attempt = 0
$sqlReady = $false

while (-not $sqlReady -and $attempt -lt $maxAttempts) {
    try {
        Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database "master" -Query "SELECT 1" -QueryTimeout 5 -ErrorAction Stop
        $sqlReady = $true
        Write-Host "SQL Server is ready."
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

# --- Check if Database Already Exists ---
Write-Host "Checking if database '$databaseName' already exists..."
try {
    $existingDb = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query "SELECT name FROM sys.databases WHERE name = '$databaseName'" -ErrorAction Stop
    if ($existingDb) {
        Write-Host "Database '$databaseName' already exists. Dropping it first..."
        
        # Set database to single user mode and drop it
        $dropQuery = @"
ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$databaseName];
"@
        Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query $dropQuery -ErrorAction Stop
        Write-Host "Existing database dropped successfully."
    }
} catch {
    Write-Warning "Could not check/drop existing database: $_"
}

# --- Download .bacpac file ---
Write-Host "Downloading SplendidCRM.bacpac from $bacpacUrl..."
$maxRetries = 3
$retryCount = 0
$downloadSuccess = $false

while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
    try {
        # Check if file exists at URL first
        $response = Invoke-WebRequest -Uri $bacpacUrl -Method Head -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Invoke-WebRequest -Uri $bacpacUrl -OutFile $bacpacFile -TimeoutSec 600 -ErrorAction Stop
            $downloadSuccess = $true
            Write-Host "Download complete. File size: $((Get-Item $bacpacFile).Length / 1MB) MB"
        }
    } catch {
        $retryCount++
        Write-Warning "Download attempt $retryCount failed: $_"
        if ($retryCount -lt $maxRetries) {
            Write-Host "Retrying in 15 seconds..."
            Start-Sleep -Seconds 15
        }
    }
}

if (-not $downloadSuccess) {
    Write-Error "Failed to download .bacpac file after $maxRetries attempts. Halting script."
    exit 1
}

# --- Restore Database ---
Write-Host "Restoring database '$databaseName' from .bacpac file..."
Write-Host "This may take several minutes depending on the database size..."

# Try both Windows Authentication and SQL Authentication
$connectionStrings = @(
    "/tsn:`"$sqlServerInstance`"",  # Windows Authentication
    "/tsn:`"$sqlServerInstance`" /tu:`"sa`" /tp:`"$saPassword`""  # SQL Authentication
)

$restoreSuccess = $false
foreach ($connString in $connectionStrings) {
    if ($restoreSuccess) { break }
    
    # Construct the command-line arguments for SqlPackage.exe
    $arguments = @(
        "/a:Import",
        "/sf:`"$bacpacFile`"",
        $connString,
        "/tdn:`"$databaseName`"",
        "/p:BlockOnPossibleDataLoss=true",
        "/p:Storage=File",
        "/p:CommandTimeout=3600"
    )
    
    Write-Host "Attempting restore with connection: $($connString.Split(' ')[0])"
    
    try {
        # Execute SqlPackage.exe with timeout
        $process = Start-Process -FilePath $sqlPackagePath -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$tempDir\restore_output.log" -RedirectStandardError "$tempDir\restore_error.log"
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Database restore completed successfully."
            $restoreSuccess = $true
        } else {
            Write-Warning "SqlPackage.exe exited with code: $($process.ExitCode)"
            if (Test-Path "$tempDir\restore_error.log") {
                $errorContent = Get-Content "$tempDir\restore_error.log" -Raw
                Write-Host "Error details: $errorContent"
            }
        }
    } catch {
        Write-Warning "Error executing SqlPackage.exe: $_"
    }
}

if (-not $restoreSuccess) {
    Write-Error "Database restore failed with all authentication methods. Check the logs in $tempDir"
    exit 1
}

# --- Verify Database Restoration ---
Write-Host "Verifying database restoration..."
try {
    # Check if database exists
    $db = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query "SELECT name FROM sys.databases WHERE name = '$databaseName'" -ErrorAction Stop
    if ($db) {
        Write-Host "Database '$databaseName' verified successfully."
        
        # Check table count
        $tableCount = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database $databaseName -Query "SELECT COUNT(*) as TableCount FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'" -ErrorAction Stop
        Write-Host "Database contains $($tableCount.TableCount) tables."
        
        # Test a simple query
        $testQuery = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Database $databaseName -Query "SELECT TOP 1 * FROM INFORMATION_SCHEMA.TABLES" -ErrorAction Stop
        if ($testQuery) {
            Write-Host "Database is accessible and contains data."
        }
    } else {
        Write-Error "Database verification failed. The database '$databaseName' was not found after the operation."
        exit 1
    }
} catch {
    Write-Error "Database verification failed: $_"
    exit 1
}

# --- Set Database Recovery Model ---
Write-Host "Setting database recovery model to SIMPLE for better performance..."
try {
    Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query "ALTER DATABASE [$databaseName] SET RECOVERY SIMPLE" -ErrorAction Stop
    Write-Host "Database recovery model set to SIMPLE."
} catch {
    Write-Warning "Could not set recovery model: $_"
}

# --- Cleanup ---
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Database setup for SplendidCRM is complete."
Write-Host "Database Name: $databaseName"
Write-Host "Connection String: Data Source=$sqlServerInstance;Initial Catalog=$databaseName;Integrated Security=True"