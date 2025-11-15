param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][string]$BundlePath,
    [Parameter(Mandatory=$true)][string]$TargetDir,
    [string]$ChecksumFile,
    [switch]$VerifyChecksum,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-File($Path){ if(-not (Test-Path -LiteralPath $Path)){ throw "Missing file: $Path" } }

Assert-File $ZipPath
Assert-File $BundlePath
if($VerifyChecksum){ Assert-File $ChecksumFile }

if(Test-Path $TargetDir){
    if(-not $Force){ throw "TargetDir $TargetDir already exists. Use -Force to overwrite." }
    Remove-Item -Recurse -Force $TargetDir
}
New-Item -ItemType Directory -Path $TargetDir | Out-Null

Write-Host "[INFO] Restoring backup into $TargetDir"

if($VerifyChecksum){
    Write-Host "[INFO] Verifying checksum..."
    $expected = (Get-Content -Path $ChecksumFile -Raw).Trim().Split(' ')[0]
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash
    if($expected -ne $actual){ throw "Checksum mismatch. Expected $expected Actual $actual" }
    Write-Host "[INFO] Checksum OK: $actual"
}

Write-Host "[INFO] Extracting ZIP contents..."
Expand-Archive -LiteralPath $ZipPath -DestinationPath $TargetDir -Force

# If extracted tree includes a full working copy we keep it; clone bundle for git history if .git missing
$gitDir = Join-Path $TargetDir '.git'
if(-not (Test-Path $gitDir)){
    Write-Host "[INFO] No .git directory found after extraction; cloning bundle for repo history..."
    Push-Location $TargetDir
    git clone $BundlePath repo-from-bundle
    Pop-Location
    Write-Host "[INFO] Bundle clone complete at $(Join-Path $TargetDir 'repo-from-bundle')"
} else {
    Write-Host "[INFO] Working copy already present. Optionally import bundle refs."
    Write-Host "[INFO] To import refs run: git fetch $BundlePath 'refs/*:refs/*'"
}

Write-Host "[INFO] Restore finished."
