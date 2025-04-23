# =========================================
# SQL Project Sync Script (No backups, no prompts)
# Builds, deploys .dacpac to local DB, logs output
# =========================================

# === CONFIGURATION ===
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sqlProjName = "YourDatabaseProject"
$dbName = "YourLocalDb"

$sqlProjPath = "$scriptDir\$sqlProjName\$sqlProjName.sqlproj"
$dacpacPath = "$scriptDir\$sqlProjName\bin\Debug\$sqlProjName.dacpac"

# Tools (update if needed)
$msbuildPath = "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
$sqlPackagePath = "C:\Program Files\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe"

# Logging setup
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = "$scriptDir\logs\deploy-$dbName-$timestamp.log"
$connectionString = "Server=localhost;Database=$dbName;Trusted_Connection=True;"

# Ensure log folder exists
New-Item -ItemType Directory -Force -Path "$scriptDir\logs" | Out-Null

# Logging helper
function Log {
    param ([string]$msg)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $entry
    Add-Content -Path $logPath -Value $entry
}

# === START SYNC ===
Log "=== Starting sync to $dbName ==="

# === BUILD .sqlproj ===
Log "Building SQL project..."
& "$msbuildPath" "$sqlProjPath" /p:Configuration=Debug | Tee-Object -FilePath $logPath -Append

if (!(Test-Path $dacpacPath)) {
    Log "ERROR: .dacpac not found at $dacpacPath"
    exit 1
}

# === DEPLOY .dacpac ===
Log "Deploying DACPAC..."
& "$sqlPackagePath" /Action:Publish `
    /SourceFile:"$dacpacPath" `
    /TargetConnectionString:"$connectionString" `
    /p:BlockOnPossibleDataLoss=false `
    /p:DropObjectsNotInSource=false `
    /p:IgnorePermissions=true `
    /p:IgnoreRoleMembership=true | Tee-Object -FilePath $logPath -Append

Log "=== Deployment complete for $dbName ==="
