param (
    [Parameter(Mandatory = $true)]
    [string]$SqlProjPath,

    [Parameter(Mandatory = $true)]
    [string]$ServerName,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Publish", "ScriptAndExecute")]
    [string]$Mode,

    [string]$Configuration = "Release"
)

# Constants
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDir "DeployConfig.json"
$outputDir = Join-Path $scriptDir "output"

# Ensure output directory exists
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Load JSON config
if (-not (Test-Path $configFile)) {
    throw "DeployConfig.json not found at $configFile"
}

$configJson = Get-Content $configFile | ConvertFrom-Json
$msbuildPath = $configJson.MSBuildPath
$sqlPackagePath = $configJson.SqlPackagePath
$dacpacPath = $configJson.DacpacPath
$SqlCmdVariables = $configJson.SqlCmdVariables

if (-not (Test-Path $msbuildPath)) {
    throw "MSBuild not found at: $msbuildPath"
}
if (-not (Test-Path $sqlPackagePath)) {
    throw "sqlpackage.exe not found at: $sqlPackagePath"
}

function Build-SqlProj {
    Write-Host "Using MSBuild: $msbuildPath"
    & "$msbuildPath" $SqlProjPath /p:Configuration=$Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed."
    }
}

function Publish-Dacpac {
    if (-not (Test-Path $dacpacPath)) {
        throw "DACPAC not found at: $dacpacPath"
    }

    Write-Host "Publishing DACPAC to $ServerName\$DatabaseName"
    $args = @(
        "/Action:Publish",
        "/SourceFile:$dacpacPath",
        "/TargetServerName:$ServerName",
        "/TargetDatabaseName:$DatabaseName",
        "/TargetTrustServerCertificate:true",
        "/TargetEncryptConnection:false",
        "/Quiet"
    )

    foreach ($key in $SqlCmdVariables.PSObject.Properties.Name) {
        $args += "/v:$key=$($SqlCmdVariables.$key)"
    }

    & "$sqlPackagePath" @args
}

function Script-And-Execute {
    if (-not (Test-Path $dacpacPath)) {
        throw "DACPAC not found at: $dacpacPath"
    }

    $scriptPath = Join-Path -Path $outputDir -ChildPath "DeployScript.sql"

    Write-Host "Generating deployment script..."
    $args = @(
        "/Action:Script",
        "/SourceFile:$dacpacPath",
        "/TargetServerName:$ServerName",
        "/TargetDatabaseName:$DatabaseName",
        "/OutputPath:$scriptPath",
        "/TargetTrustServerCertificate:true",
        "/TargetEncryptConnection:false",
        "/Quiet"
    )

    foreach ($key in $SqlCmdVariables.PSObject.Properties.Name) {
        $args += "/v:$key=$($SqlCmdVariables.$key)"
    }

    & "$sqlPackagePath" @args

    if (-not (Test-Path $scriptPath)) {
        throw "Failed to generate deployment script."
    }

    Write-Host "Executing script..."
    & sqlcmd -S $ServerName -d $DatabaseName -E -i $scriptPath
}

# Main flow
Build-SqlProj

switch ($Mode) {
    "Publish"          { Publish-Dacpac }
    "ScriptAndExecute" { Script-And-Execute }
}