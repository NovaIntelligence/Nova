param()
$ErrorActionPreference='Stop'
function Get-NextWeekday { param([datetime]$From,[DayOfWeek]$Day) $d=$From; while($d.DayOfWeek -ne $Day){ $d=$d.AddDays(1) }; $d }
function New-NovaICSFile {
  param(
    [datetime[]]$StartTimes,
    [int]$DurationMinutes=45,
    [string]$Summary='Nova x Tyler - Session',
    [string]$Location='Video call (Nova)',
    [string]$Description='Creators: Tyler McKendry and Nova - tentative booking window (dry-run)',
    [string]$Timezone='Australia/Brisbane',
    [switch]$DryRun
  )
  if(-not $StartTimes -or $StartTimes.Count -lt 1){ throw 'StartTimes required' }
  $uidBase = [guid]::NewGuid().ToString()
  $dtStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
  $vtz = @"
BEGIN:VTIMEZONE
TZID:$Timezone
X-LIC-LOCATION:$Timezone
BEGIN:STANDARD
TZOFFSETFROM:+1000
TZOFFSETTO:+1000
TZNAME:AEST
DTSTART:19700101T000000
END:STANDARD
END:VTIMEZONE
"@
  $events = New-Object System.Text.StringBuilder
  foreach($i in 0..($StartTimes.Count-1)){
    $st = $StartTimes[$i]; $en = $st.AddMinutes($DurationMinutes)
    $stStr = $st.ToString("yyyyMMdd'T'HHmmss"); $enStr = $en.ToString("yyyyMMdd'T'HHmmss")
    $uid = "nova-ics-$uidBase-$i"
    $null = $events.AppendLine("BEGIN:VEVENT")
    $null = $events.AppendLine("UID:$uid")
    $null = $events.AppendLine("DTSTAMP:$dtStamp")
    $null = $events.AppendLine("DTSTART;TZID=${Timezone}:$stStr")
    $null = $events.AppendLine("DTEND;TZID=${Timezone}:$enStr")
    $null = $events.AppendLine("SUMMARY:$Summary")
    $null = $events.AppendLine("LOCATION:$Location")
    $desc = ($Description -replace "`r`n",' ' -replace "`n",' ')
    $null = $events.AppendLine("DESCRIPTION:$desc")
    $null = $events.AppendLine("STATUS:TENTATIVE")
    $null = $events.AppendLine("X-NOVA-DRYRUN:TRUE")
    $null = $events.AppendLine("END:VEVENT")
  }
  $cal = @()
  $cal += 'BEGIN:VCALENDAR'
  $cal += 'PRODID:-//Nova Intelligence Group//NovaICS 1.0//EN'
  $cal += 'VERSION:2.0'
  $cal += $vtz.Trim()
  $cal += $events.ToString().TrimEnd()
  $cal += 'END:VCALENDAR'
  $outDir = 'C:\Nova\out\calendar'; if(-not (Test-Path $outDir)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
  $fn = "nova-slots-$([DateTime]::Now.ToString('yyyyMMdd-HHmmss')).ics"
  $path = Join-Path $outDir $fn
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($path, ($cal -join "`r`n"), $enc)
  [pscustomobject]@{ path=$path; count=$StartTimes.Count; duration=$DurationMinutes; tz=$Timezone }
}
function Invoke-CalendarSlots { param([int]$DurationMinutes=45,[string]$Timezone='Australia/Brisbane',[switch]$DryRun)
  $now = Get-Date
  $tue = Get-NextWeekday -From $now -Day ([DayOfWeek]::Tuesday)
  $wed = Get-NextWeekday -From $now -Day ([DayOfWeek]::Wednesday)
  $thu = Get-NextWeekday -From $now -Day ([DayOfWeek]::Thursday)
  $slots = @(
    (Get-Date -Year $tue.Year -Month $tue.Month -Day $tue.Day -Hour 10 -Minute 30 -Second 0),
    (Get-Date -Year $wed.Year -Month $wed.Month -Day $wed.Day -Hour 14 -Minute 00 -Second 0),
    (Get-Date -Year $thu.Year -Month $thu.Month -Day $thu.Day -Hour 19 -Minute 00 -Second 0)
  )
  New-NovaICSFile -StartTimes $slots -DurationMinutes $DurationMinutes -Timezone $Timezone -DryRun:$DryRun
}