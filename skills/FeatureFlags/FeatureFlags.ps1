param()
$ErrorActionPreference='Stop'
function Get-FlagsPath { Join-Path "C:\Nova\core\config" "flags.json" }
function Get-NovaFlags {
  $p = Get-FlagsPath
  if(-not (Test-Path $p)){ throw "flags.json missing at $p" }
  try{ Get-Content $p -Raw | ConvertFrom-Json }catch{ throw "flags.json unreadable: $_" }
}
function Set-NovaFlag {
  param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][bool]$Value,[switch]$DryRun)
  $cfg = Get-NovaFlags
  if(-not $cfg.features.PSObject.Properties.Match($Name).Count){ $cfg.features | Add-Member -NotePropertyName $Name -NotePropertyValue $Value } else { $cfg.features.$Name = $Value }
  $cfg.meta.updated = (Get-Date).ToString("s")
  if($DryRun){ return $cfg }
  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Get-FlagsPath), ($cfg | ConvertTo-Json -Depth 10), $Utf8NoBom)
  return $cfg
}
function Test-NovaFlag { param([Parameter(Mandatory)][string]$Name)
  $cfg = Get-NovaFlags; $v=$false
  if($cfg.features.PSObject.Properties.Match($Name).Count){ $v=[bool]$cfg.features.$Name }
  [pscustomobject]@{ name=$Name; enabled=$v }
}
function Test-NovaCanary { param([double]$Ratio=0.10,[int]$Seed=1337,[switch]$ForceCanary)
  if($ForceCanary){ return [pscustomobject]@{canary=$true; roll=0.0; ratio=$Ratio; seed=$Seed} }
  $ticks=[int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds
  $seed2=[int]($Seed + ($ticks % 2147483647))
  $rand=New-Object System.Random($seed2)
  $roll=$rand.NextDouble()
  $canary=($roll -lt $Ratio)
  [pscustomobject]@{ canary=$canary; roll=[math]::Round($roll,4); ratio=$Ratio; seed=$Seed }
}