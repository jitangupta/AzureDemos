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

# --- Check for restart scenarios ---
$restartMarker = "$env:TEMP\dotnet48_restart_marker.txt"
$resumeAfterRestart = $false

if (Test-Path $restartMarker) {
    Write-Log "🔄 Detected restart marker - resuming after .NET 4.8 installation restart" "INFO"
    $resumeAfterRestart = $true
    
    # Verify .NET 4.8 installation after restart
    $net48Version = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction SilentlyContinue).Release
    if ($net48Version -ge 528040) {
        Write-Log "✓ .NET Framework 4.8 installation verified after restart (Release: $net48Version)" "SUCCESS"
        
        # Clean up restart marker
        Remove-Item $restartMarker -Force -ErrorAction SilentlyContinue
        
        # Clean up scheduled task
        try {
            Unregister-ScheduledTask -TaskName "SplendidCRM-Resume-After-Restart" -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "✓ Restart task cleaned up" "INFO"
        } catch {
            Write-Log "Could not clean up restart task: $_" "WARN"
        }
        
        # Skip install-iis-sql.ps1 since it already ran before restart
        Write-Log "Skipping install-iis-sql.ps1 - already completed before restart" "INFO"
        $scriptsToRun = @("deploy-app.ps1", "load-db.ps1")
        
    } else {
        Write-Log "❌ .NET Framework 4.8 installation not verified after restart (Release: $net48Version)" "ERROR"
        Write-Log "Will attempt to continue with existing .NET version..." "WARN"
        # Clean up marker and continue with all scripts
        Remove-Item $restartMarker -Force -ErrorAction SilentlyContinue
    }
}

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
