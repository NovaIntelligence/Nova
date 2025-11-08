param()
$ErrorActionPreference='Stop'
function Get-MacroConfig { $p="C:\Nova\core\config\macro-windows.json"; if(-not (Test-Path $p)){ throw "macro-windows.json missing at $p" }; Get-Content $p -Raw | ConvertFrom-Json }
function Test-MacroBlock {
  $cfg=Get-MacroConfig; $now=Get-Date
  foreach($w in $cfg.windows){
    $st=[datetime]::Parse($w.start); $en=[datetime]::Parse($w.end)
    if($now -ge $st -and $now -le $en){ return [pscustomobject]@{blocked=$true; label=$w.label; start=$st; end=$en; note=$w.note} }
  }
  [pscustomobject]@{blocked=$false}
}
function Invoke-RegimeDetector { param([double[]]$Series,[int]$Window=50)
  if(-not $Series){
    $Series=@(); $x=100.0; 1..$Window | ForEach-Object { $x += (Get-Random -Minimum 0.1 -Maximum 0.9); $Series += [math]::Round($x,2) }
  }
  if($Series.Count -lt 10){ throw 'Series too short' }
  $n=$Series.Count; $xs=0.0; $ys=0.0; $xys=0.0; $xxs=0.0
  for($i=0;$i -lt $n;$i++){ $x=[double]$i; $y=[double]$Series[$i]; $xs+=$x; $ys+=$y; $xys+=($x*$y); $xxs+=($x*$x) }
  $den = ($n * $xxs) - ($xs * $xs); if($den -eq 0){ $den = 0.0001 }
  $slope = (( $n * $xys) - ($xs * $ys)) / $den
  $diffs=@(); for($i=1;$i -lt $n;$i++){ $diffs += [math]::Abs($Series[$i]-$Series[$i-1]) }
  $meanDiff = ($diffs | Measure-Object -Average).Average; if(-not $meanDiff){ $meanDiff = 0.0001 }
  $trendScore = [math]::Min(1.0, [math]::Abs($slope) / $meanDiff)
  $regime = if($trendScore -ge 0.6){ 'trend' } else { 'mean-reversion' }
  [pscustomobject]@{ regime=$regime; trendScore=[math]::Round($trendScore,3); slope=[math]::Round($slope,4); samples=$n }
}
function Evaluate-TradePermission {
  $m = Test-MacroBlock
  if($m.blocked){ return [pscustomobject]@{ allow=$false; reason='macro_window'; detail=$m } }
  $r = Invoke-RegimeDetector
  [pscustomobject]@{ allow=$true; reason='ok'; regime=$r }
}