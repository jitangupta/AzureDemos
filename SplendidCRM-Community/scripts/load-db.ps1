# PowerShell Script to Load SplendidCRM Database Schema and Data

# --- Configuration ---
$databaseName = "SplendidCRM"
$sqlServerInstance = "." # Local default instance
$webRoot = "C:\inetpub\wwwroot"
$dbScriptsPath = "$webRoot\db"
$iisAppPoolUser = "IIS APPPOOL\DefaultAppPool"

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
try {
    Invoke-Sqlcmd -Query $createDbQuery -ServerInstance $sqlServerInstance -ErrorAction Stop
    Write-Host "Database '$databaseName' created or already exists."
} catch {
    Write-Error "Failed to create database. Error: $_"
    exit 1
}

# --- Create SQL Login for IIS App Pool ---
Write-Host "Creating SQL Login for IIS user: '$iisAppPoolUser'..."
$createLoginQuery = "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'$iisAppPoolUser') CREATE LOGIN [$iisAppPoolUser] FROM WINDOWS;"
try {
    Invoke-Sqlcmd -Query $createLoginQuery -ServerInstance $sqlServerInstance -ErrorAction Stop
    Write-Host "SQL Login for '$iisAppPoolUser' created or already exists."
} catch {
    Write-Error "Failed to create SQL login. Error: $_"
    exit 1
}

# --- Grant DB Ownership to IIS App Pool ---
Write-Host "Granting database ownership to '$iisAppPoolUser'..."
$grantDbOwnershipQuery = "USE [$databaseName]; ALTER AUTHORIZATION ON DATABASE::[$databaseName] TO [$iisAppPoolUser];"
try {
    Invoke-Sqlcmd -Query $grantDbOwnershipQuery -ServerInstance $sqlServerInstance -ErrorAction Stop
    Write-Host "Database ownership granted successfully."
} catch {
    Write-Error "Failed to grant database ownership. Error: $_"
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