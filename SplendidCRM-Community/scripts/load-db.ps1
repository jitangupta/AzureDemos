# PowerShell Script to Load SplendidCRM Database Schema and Data

# --- Configuration ---
$databaseName = "SplendidCRM"
$sqlServerInstance = ".\MSSQLSERVER" # Default instance
$webRoot = "C:\inetpub\wwwroot"
$dbScriptsPath = "$webRoot\db"

# --- Main Logic ---
Write-Host "Starting database setup for SplendidCRM..."

# Check if the database scripts path exists
if (-not (Test-Path -Path $dbScriptsPath)) {
    Write-Error "Database scripts folder not found at $dbScriptsPath. Ensure the application is deployed first. Halting script."
    exit 1
}

# --- Create the Database ---
Write-Host "Creating database: $databaseName..."
$createDbQuery = "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'$databaseName') CREATE DATABASE [$databaseName];"

# Using -S . for local default instance
try {
    Invoke-Sqlcmd -Query $createDbQuery -ServerInstance $sqlServerInstance -ErrorAction Stop
    Write-Host "Database '$databaseName' created or already exists."
} catch {
    Write-Error "Failed to create database. Error: $_"
    exit 1
}

# --- Execute SQL Scripts ---
# The order of execution is important: Schema first, then data.
$schemaFile = "$dbScriptsPath\SplendidCRM.sql"
$dataFile = "$dbScriptsPath\vwSplendidCRM_Data.sql"

if (-not (Test-Path -Path $schemaFile)) {
    Write-Error "Schema file not found: $schemaFile. Halting script."
    exit 1
}
if (-not (Test-Path -Path $dataFile)) {
    Write-Error "Data file not found: $dataFile. Halting script."
    exit 1
}

# Execute Schema Script
Write-Host "Executing schema script: $schemaFile..."
try {
    Invoke-Sqlcmd -InputFile $schemaFile -ServerInstance $sqlServerInstance -Database $databaseName -ErrorAction Stop
    Write-Host "Schema script executed successfully."
} catch {
    Write-Error "Failed to execute schema script. Error: $_"
    exit 1
}

# Execute Data Script
Write-Host "Executing data script: $dataFile..."
try {
    Invoke-Sqlcmd -InputFile $dataFile -ServerInstance $sqlServerInstance -Database $databaseName -ErrorAction Stop
    Write-Host "Data script executed successfully."
} catch {
    Write-Error "Failed to execute data script. Error: $_"
    exit 1
}

Write-Host "Database setup for SplendidCRM is complete."
