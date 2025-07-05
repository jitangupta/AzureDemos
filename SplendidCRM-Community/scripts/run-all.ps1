# Master PowerShell script to orchestrate the entire VM setup.

# --- Configuration ---
$scriptsPath = $PSScriptRoot # The directory where this script is located.

# --- Execution Order ---

# 1. Install IIS, .NET 4.8, and SQL Server
Write-Host "Executing Step 1: install-iis-sql.ps1..."
try {
    . "$scriptsPath\install-iis-sql.ps1" -ErrorAction Stop
} catch {
    Write-Error "Failed to execute install-iis-sql.ps1. Error: $_"
    exit 1
}
Write-Host "Step 1 completed."

# 2. Deploy the SplendidCRM Application
Write-Host "Executing Step 2: deploy-app.ps1..."
try {
    . "$scriptsPath\deploy-app.ps1" -ErrorAction Stop
} catch {
    Write-Error "Failed to execute deploy-app.ps1. Error: $_"
    exit 1
}
Write-Host "Step 2 completed."

# 3. Load the Database Schema and Data
Write-Host "Executing Step 3: load-db.ps1..."
try {
    . "$scriptsPath\load-db.ps1" -ErrorAction Stop
} catch {
    Write-Error "Failed to execute load-db.ps1. Error: $_"
    exit 1
}
Write-Host "Step 3 completed."

Write-Host "All setup scripts have been executed successfully."
