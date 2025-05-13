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

    [string]$Configuration = "Release",
    [string]$OutputDir = "$env:TEMP"
)

function Build-SqlProj {
    Write-Host "Building project: $SqlProjPath"
    & msbuild $SqlProjPath /p:Configuration=$Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed."
    }
}

function Get-DacpacPath {
    $projName = [System.IO.Path]::GetFileNameWithoutExtension($SqlProjPath)
    $dacpacPath = Join-Path -Path (Join-Path -Path ([System.IO.Path]::GetDirectoryName($SqlProjPath)) -ChildPath "bin\$Configuration") -ChildPath "$projName.dacpac"
    if (-not (Test-Path $dacpacPath)) {
        throw "DACPAC not found at: $dacpacPath"
    }
    return $dacpacPath
}

function Publish-Dacpac {
    param ($DacpacPath)
    Write-Host "Publishing DACPAC to $ServerName\$DatabaseName"
    & sqlpackage /Action:Publish `
                 /SourceFile:$DacpacPath `
                 /TargetServerName:$ServerName `
                 /TargetDatabaseName:$DatabaseName `
                 /TargetTrustServerCertificate:true `
                 /TargetEncryptConnection:false `
                 /Quiet
}

function Script-And-Execute {
    param ($DacpacPath)
    $scriptPath = Join-Path -Path $OutputDir -ChildPath "DeployScript.sql"
    Write-Host "Generating deployment script..."
    & sqlpackage /Action:Script `
                 /SourceFile:$DacpacPath `
                 /TargetServerName:$ServerName `
                 /TargetDatabaseName:$DatabaseName `
                 /OutputPath:$scriptPath `
                 /TargetTrustServerCertificate:true `
                 /TargetEncryptConnection:false `
                 /Quiet

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