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

# --- Download Application ---
Write-Host "Downloading SplendidCRM from $repoUrl..."
Invoke-WebRequest -Uri $repoUrl -OutFile $tempZipFile
Write-Host "Download complete."

# --- Extract Application ---
Write-Host "Extracting application files..."
Expand-Archive -Path $tempZipFile -DestinationPath $tempDir -Force
Write-Host "Extraction complete."

# Find the extracted folder name (it's usually repo-branch)
$extractedFolder = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
if ($null -eq $extractedFolder) {
    Write-Error "Could not find the extracted application folder in $tempDir. Halting deployment."
    exit 1
}
$sourcePath = $extractedFolder.FullName

# --- Deploy to IIS ---
Write-Host "Deploying application to IIS web root: $webRoot"

# Clear existing default IIS content
Write-Host "Clearing default IIS content from $webRoot..."
Get-ChildItem -Path $webRoot | Remove-Item -Recurse -Force

# Copy application files
Write-Host "Copying SplendidCRM files..."
Copy-Item -Path "$sourcePath\*" -Destination $webRoot -Recurse -Force

# --- Set IIS Application Pool ---
# Ensure the DefaultAppPool is running with ASP.NET v4.0
Write-Host "Configuring IIS Application Pool..."
Import-Module WebAdministration
Set-ItemProperty -Path 'IIS:\AppPools\DefaultAppPool' -Name managedRuntimeVersion -Value "v4.0"

Write-Host "Deployment script finished successfully."

# --- Cleanup ---
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "SplendidCRM application has been deployed."
