# Master script to execute all deployment scripts in sequence
# Designed for Azure Custom Script Extension automated execution

param(
    [switch]$Force = $false
)

# --- Configuration ---
$ErrorActionPreference = "Continue"  # Continue on errors to get better logging
$logFile = "C:\Temp\deployment.log"
$scriptsToRun = @(
    "install-iis-sql.ps1",
    "deploy-app.ps1", 
    "load-db.ps1"
)

# --- Initialize Logging ---
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force
}

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

Write-Log "=== STARTING SPLENDIDCRM DEPLOYMENT ===" "INFO"
Write-Log "Force mode: $Force" "INFO"
Write-Log "Current directory: $(Get-Location)" "INFO"
Write-Log "Available files: $(Get-ChildItem | Select-Object -ExpandProperty Name)" "INFO"

# --- Execute Scripts in Sequence ---
$overallSuccess = $true

foreach ($script in $scriptsToRun) {
    Write-Log "--- Executing $script ---" "INFO"
    
    if (-not (Test-Path $script)) {
        Write-Log "Script not found: $script" "ERROR"
        $overallSuccess = $false
        continue
    }
    
    try {
        Write-Log "Starting execution of $script" "INFO"
        
        # Execute script and capture output
        $output = & powershell.exe -ExecutionPolicy Unrestricted -File $script -Force:$Force 2>&1
        
        # Log all output
        $output | ForEach-Object {
            Write-Log "[$script] $_" "INFO"
        }
        
        # Check if script succeeded
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-Log "✓ $script completed successfully" "SUCCESS"
        } else {
            Write-Log "✗ $script failed with exit code: $LASTEXITCODE" "ERROR"
            $overallSuccess = $false
            
            # In automated deployment, continue with other scripts
            Write-Log "Continuing with remaining scripts..." "WARN"
        }
        
    } catch {
        Write-Log "✗ Failed to execute $script. Error: $_" "ERROR"
        $overallSuccess = $false
    }
    
    Write-Log "--- Completed $script ---" "INFO"
    Start-Sleep -Seconds 5
}

# --- Final Status ---
if ($overallSuccess) {
    Write-Log "🎉 ALL SCRIPTS COMPLETED SUCCESSFULLY" "SUCCESS"
    Write-Log "SplendidCRM deployment finished!" "SUCCESS"
    exit 0
} else {
    Write-Log "⚠️ SOME SCRIPTS FAILED - CHECK LOGS" "ERROR"
    Write-Log "Deployment completed with errors. Check individual script logs." "ERROR"
    exit 1
}
