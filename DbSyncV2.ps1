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
$SqlCmdVariables = $configJson.SqlCmdVariables

if (-not (Test-Path $msbuildPath)) {
    throw "MSBuild not found at: $msbuildPath"
}

function Build-SqlProj {
    Write-Host "Using MSBuild: $msbuildPath"
    & "$msbuildPath" $SqlProjPath /p:Configuration=$Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed."
    }
}

function Get-DacpacPath {
    $projName = [System.IO.Path]::GetFileNameWithoutExtension($SqlProjPath)
    $projDir = Split-Path -Parent $SqlProjPath
    $dacpacPath = Join-Path -Path (Join-Path -Path $projDir -ChildPath "bin\$Configuration") -ChildPath "$projName.dacpac"

    if (-not (Test-Path $dacpacPath)) {
        throw "DACPAC not found at: $dacpacPath"
    }

    return $dacpacPath
}

function Publish-Dacpac {
    param ([string]$DacpacPath)

    Write-Host "Publishing DACPAC to $ServerName\$DatabaseName"
    $args = @(
        "/Action:Publish",
        "/SourceFile:$DacpacPath",
        "/TargetServerName:$ServerName",
        "/TargetDatabaseName:$DatabaseName",
        "/TargetTrustServerCertificate:true",
        "/TargetEncryptConnection:false",
        "/Quiet"
    )

    foreach ($key in $SqlCmdVariables.PSObject.Properties.Name) {
        $args += "/v:$key=$($SqlCmdVariables.$key)"
    }

    & sqlpackage @args
}

function Script-And-Execute {
    param ([string]$DacpacPath)

    $scriptPath = Join-Path -Path $outputDir -ChildPath "DeployScript.sql"

    Write-Host "Generating deployment script..."
    $args = @(
        "/Action:Script",
        "/SourceFile:$DacpacPath",
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

    & sqlpackage @args

    if (-not (Test-Path $scriptPath)) {
        throw "Failed to generate deployment script."
    }

    Write-Host "Executing script..."
    & sqlcmd -S $ServerName -d $DatabaseName -E -i $scriptPath
}

# Main flow
Build-SqlProj
$dacpac = Get-DacpacPath

switch ($Mode) {
    "Publish"          { Publish-Dacpac -DacpacPath $dacpac }
    "ScriptAndExecute" { Script-And-Execute -DacpacPath $dacpac }
}