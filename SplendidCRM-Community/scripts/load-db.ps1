# PowerShell Script to Download and Restore SplendidCRM Database from a .bacpac file

# --- Configuration ---
$bacpacUrl = "https://raw.githubusercontent.com/jitangupta/AzureDemos/main/SplendidCRM-Community/scripts/SplendidCRM.bacpac" # Assumes bacpac is in the same folder
$tempDir = "$env:TEMP\SplendidCRM-DB"
$bacpacFile = "$tempDir\SplendidCRM.bacpac"
$databaseName = "SplendidCRM"
$sqlServerInstance = "." # Local default instance

# Path to SqlPackage.exe - it can vary, so we search for it.
$sqlPackagePath = (Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server" -Recurse -Filter "SqlPackage.exe").FullName | Select-Object -First 1

# --- Preparation ---
Write-Host "Preparing for database restore..."
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir

if (-not $sqlPackagePath) {
    Write-Error "SqlPackage.exe not found. This tool is required to restore the database. Halting script."
    exit 1
}
Write-Host "Found SqlPackage.exe at: $sqlPackagePath"

# --- Download .bacpac file ---
Write-Host "Downloading SplendidCRM.bacpac from $bacpacUrl..."
try {
    Invoke-WebRequest -Uri $bacpacUrl -OutFile $bacpacFile -ErrorAction Stop
    Write-Host "Download complete."
} catch {
    Write-Error "Failed to download .bacpac file. Error: $_"
    exit 1
}

# --- Restore Database ---
Write-Host "Restoring database '$databaseName' from .bacpac file..."

# Construct the command-line arguments for SqlPackage.exe
$arguments = @(
    "/a:Import",
    "/sf:\"$bacpacFile\"",
    "/tsn:\"$sqlServerInstance\"",
    "/tdn:\"$databaseName\"",
    "/p:BlockOnPossibleDataLoss=false" # Required for some restores
)

try {
    # The SQL service must be running
    Start-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue
    
    # Execute SqlPackage.exe
    Start-Process -FilePath $sqlPackagePath -ArgumentList $arguments -Wait -NoNewWindow
    Write-Host "Database restore command executed."

    # Verify the database exists
    $db = Invoke-Sqlcmd -ServerInstance $sqlServerInstance -Query "SELECT name FROM sys.databases WHERE name = '$databaseName'"
    if ($db) {
        Write-Host "Database '$databaseName' restored successfully."
    } else {
        Write-Error "Database restore failed. The database '$databaseName' was not found after the operation."
        exit 1
    }
} catch {
    Write-Error "An error occurred during the database restore process. Error: $_"
    exit 1
}

# --- Cleanup ---
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "Database setup for SplendidCRM is complete."
