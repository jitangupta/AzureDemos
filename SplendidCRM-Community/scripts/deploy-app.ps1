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

# Find the actual application source folder (it's nested)
$extractedFolder = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
$appSourcePath = Join-Path $extractedFolder.FullName "SplendidCRM"

if (-not (Test-Path $appSourcePath)) {
    Write-Error "Could not find the nested application folder at $appSourcePath. Halting deployment."
    exit 1
}

# --- Deploy to IIS ---
Write-Host "Deploying application to IIS web root: $webRoot"

# Clear existing default IIS content
Write-Host "Clearing default IIS content from $webRoot..."
Get-ChildItem -Path $webRoot | Remove-Item -Recurse -Force

# Copy application files from the correct nested folder
Write-Host "Copying SplendidCRM files from $appSourcePath..."
Copy-Item -Path "$appSourcePath\*" -Destination $webRoot -Recurse -Force

# --- Configure Database Connection ---
Write-Host "Updating web.config with local SQL Server connection string..."
$webConfigFile = Join-Path $webRoot "web.config"
if (-not (Test-Path $webConfigFile)) {
    Write-Error "web.config not found at $webConfigFile. Halting configuration."
    exit 1
}

# Load the XML
$xml = [xml](Get-Content $webConfigFile)

# Find the connectionStrings node and the specific 'add' element
$connStringNode = $xml.SelectSingleNode("//connectionStrings/add[@name='SplendidCRM']")
if ($null -ne $connStringNode) {
    # Update the connectionString attribute for local SQL Server with Windows Auth
    $connStringNode.SetAttribute("connectionString", "server=.;database=SplendidCRM;trusted_connection=true")
    # Save the modified XML back to the file
    $xml.Save($webConfigFile)
    Write-Host "web.config updated successfully."
} else {
    Write-Warning "Could not find the 'SplendidCRM' connection string in web.config. Application might not work."
}

# --- Set IIS Application Pool ---
Write-Host "Configuring IIS Application Pool..."
Import-Module WebAdministration
Set-ItemProperty -Path 'IIS:\AppPools\DefaultAppPool' -Name managedRuntimeVersion -Value "v4.0"

Write-Host "Deployment script finished successfully."

# --- Cleanup ---
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "SplendidCRM application has been deployed and configured."