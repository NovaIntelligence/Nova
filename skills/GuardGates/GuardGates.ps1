param([datetime]$Now)
$ErrorActionPreference='Stop'
Set-StrictMode -Off

function Get-AutopilotConfig {
  $p="C:\Nova\core\config\autopilot.json"
  if(-not (Test-Path $p)){ throw "autopilot.json missing at $p" }
  Get-Content $p -Raw | ConvertFrom-Json
}

function Test-AutopilotWindow {
  param([datetime]$Now=(Get-Date))
  $cfg = Get-AutopilotConfig
  $day = [string]$Now.DayOfWeek

  if(-not $cfg.windows.PSObject.Properties.Match($day).Count){
    return [pscustomobject]@{ open=$false; reason='no_window'; today=$day; next_open=$null }
  }

  $date = Get-Date -Year $Now.Year -Month $Now.Month -Day $Now.Day -Hour 0 -Minute 0 -Second 0
  $open=$false; $currentStart=$null; $currentEnd=$null; $nextOpen=$null

  foreach($w in $cfg.windows.$day){
    $sParts=$w.start.Split(':'); $eParts=$w.end.Split(':')
    $s = Get-Date -Year $date.Year -Month $date.Month -Day $date.Day -Hour ([int]$sParts[0]) -Minute ([int]$sParts[1]) -Second 0
    $e = Get-Date -Year $date.Year -Month $date.Month -Day $date.Day -Hour ([int]$eParts[0]) -Minute ([int]$eParts[1]) -Second 0
    if($e -le $s){ $e = $e.AddDays(1) }  # cross-midnight safeguard
    if($Now -ge $s -and $Now -le $e){ $open=$true; $currentStart=$s; $currentEnd=$e }
    if(-not $open -and $Now -lt $s){
      if($null -eq $nextOpen -or $s -lt $nextOpen){ $nextOpen=$s }
    }
  }

  $reason = 'window_closed'
  if($open){ $reason = 'window_open' }

  $obj=[ordered]@{ open=$open; reason=$reason; today=$day }
  if($open){
    $obj.current_start=$currentStart; $obj.current_end=$currentEnd
  } else {
    $obj.next_open=$nextOpen
  }
  [pscustomobject]$obj
}

function Evaluate-FinalTradePermission {
  param([datetime]$Now=(Get-Date))
  . "C:\Nova\skills\FeatureFlags\FeatureFlags.ps1"
  . "C:\Nova\skills\RegimeDetector\RegimeDetector.ps1"

  $flags = Get-NovaFlags
  $flagAutoPlace = $false
  if($flags.features.PSObject.Properties.Match('trading.autoplace').Count){
    $flagAutoPlace = [bool]$flags.features.'trading.autoplace'
  }

  $macro = Test-MacroBlock
  if($macro.blocked){ return [pscustomobject]@{ allow=$false; reason='macro_window'; detail=$macro } }

  $auto = Test-AutopilotWindow -Now $Now
  if(-not $auto.open){ return [pscustomobject]@{ allow=$false; reason='autopilot_closed'; detail=$auto } }

  if(-not $flagAutoPlace){ return [pscustomobject]@{ allow=$false; reason='flag_off'; flag='trading.autoplace' } }

  $reg = Invoke-RegimeDetector
  [pscustomobject]@{ allow=$true; reason='ok'; regime=$reg; autopilot=$auto; flag='trading.autoplace' }
}