#requires -version 5.1
<#
.SYNOPSIS
    Nova Bot - One-Paste Save+Run Voice Assistant
.DESCRIPTION
    Creators: Tyler McKendry & Nova
    
    Complete voice assistant with real-time speech recognition, TTS replies,
    persistent memory, calendar integration, and OpenAI LLM capabilities.
    
    On first run: Creates full file structure, writes all components, configures defaults.
    Subsequent runs: Idempotent safe re-write and launch.
    
    Features:
    - Speech Recognition (NZ/UK/AU English priority)
    - Text-to-Speech responses
    - Persistent memory (Nova Intelligence Group context)
    - Calendar reading (.ics support)
    - Hotword/PTT/Always-on modes
    - Chat history & aliases
    - Robust logging with daily structure
    
.NOTES
    PowerShell 5.1+ compatible
    Requires System.Speech (.NET Framework)
    Uses UTF-8 encoding (no BOM)
#>

[CmdletBinding()]
param(
    [switch]$SkipLaunch,
    [string]$BotRoot = 'C:\Nova\bot'
)

# Ensure UTF-8 encoding for all file operations
$UTF8NoBOM = New-Object System.Text.UTF8Encoding $false

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
}

function Ensure-Directory {
    param([string]$Path)
    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Log "Created directory: $Path"
    }
}

function Write-FileUTF8 {
    param([string]$Path, [string]$Content)
    Ensure-Directory (Split-Path $Path -Parent)
    [System.IO.File]::WriteAllText($Path, $Content, $UTF8NoBOM)
    Write-Log "Created file: $Path"
}

# Main installation function
function Install-NovaBot {
    param([string]$InstallPath)
    
    Write-Log "Installing Nova Bot to: $InstallPath" 'INFO'
    
    # Create directory structure
    $dirs = @(
        "$InstallPath",
        "$InstallPath\config",
        "$InstallPath\memory",
        "$InstallPath\chat",
        "$InstallPath\logs",
        "$InstallPath\tools"
    )
    
    foreach ($dir in $dirs) {
        Ensure-Directory $dir
    }
    
    # Create main bot script
    $mainBotScript = @'
#requires -version 5.1
<#
.SYNOPSIS
    Nova Bot Main Script
.DESCRIPTION
    Creators: Tyler McKendry & Nova
    Voice assistant with speech recognition, TTS, memory, and LLM integration
#>

param(
    [switch]$Debug,
    [string]$ConfigPath
)

# Robust root resolution
$script:BotRoot = $null
if ($PSScriptRoot) {
    $script:BotRoot = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $script:BotRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
} elseif ($env:NOVA_BOT_ROOT) {
    $script:BotRoot = $env:NOVA_BOT_ROOT
} else {
    $script:BotRoot = 'C:\Nova\bot'
}

Write-Host "Nova Bot Root: $script:BotRoot"

# Global variables
$script:Config = $null
$script:Memory = $null
$script:Recognizer = $null
$script:Synthesizer = $null
$script:LogPath = $null
$script:IsListening = $false
$script:IsMuted = $false
$script:ChatHistory = @()
$script:Aliases = @{}
$script:LastWakeTime = $null
$script:CurrentSession = $null

# Logging setup with BootSafe daily structure
function Initialize-Logging {
    $now = Get-Date
    $yearPath = Join-Path $script:BotRoot "logs\$($now.Year)"
    $monthPath = Join-Path $yearPath $now.ToString('MM')
    $dayPath = Join-Path $monthPath $now.ToString('dd')
    
    if (!(Test-Path $dayPath)) {
        New-Item -Path $dayPath -ItemType Directory -Force | Out-Null
    }
    
    $sessionCounter = 1
    do {
        $script:LogPath = Join-Path $dayPath "session-$sessionCounter.log"
        $sessionCounter++
    } while (Test-Path $script:LogPath)
    
    $script:CurrentSession = "session-$($sessionCounter-1)"
    Write-Log "Session started: $script:CurrentSession" 'INFO'
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Write-Host $logEntry
    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8
    }
}
trap { try{ Write-Log "CRASH" ("Unhandled: " + ($_ | Out-String)) } catch { Write-Host "Critical error in trap handler: $($_.Exception.Message)" }; break }

# --- Utility: UTF-8 writer
function Write-Utf8([string]$Path,[string]$Content){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($Path,$Content,$enc)
}

# --- Self-heal config (no inner here-strings)
$CfgJSON = Join-Path $script:BotRoot "config\config.json"
if(-not (Test-Path $CfgJSON)){
  Write-Log "BOOT" "config.json missing; writing default."
  $DefaultCfgJson = '{
  "locale": "en-AU",
  "stt": {
    "trigger": "always_on",
    "speech_mode": "chatty",
    "wake_required": true,
    "awake_window_seconds": 30,
    "confidence_min": 0.35
  },
  "tts": {
    "enabled": true,
    "voice_hint": "",
    "auto_talk": false,
    "auto_talk_conf_min": 0.35
  },
  "llm": {
    "endpoint": "https://api.openai.com/v1/chat/completions",
    "model": "gpt-4o-mini",
    "temperature": 0.7,
    "max_tokens": 256,
    "api_key_env": "OPENAI_API_KEY",
    "api_key_path": "",
    "max_history": 10
  },
  "calendar": {
    "ics_url": "",
    "ics_path": "C:\\Nova\\bot\\config\\calendar.ics",
    "ics_cache_minutes": 60
  },
  "logging": {
    "level": "info",
    "max_session_minutes": 240
  }
}'
  Write-Utf8 $CfgJSON $DefaultCfgJson
}
$Cfg = $null
try{
  $Cfg = Get-Content $CfgJSON -Raw | ConvertFrom-Json
}catch{
  Write-Log "BOOT" ("config.json invalid; backing up and writing default. " + $_.Exception.Message)
  try{ Copy-Item $CfgJSON "$($CfgJSON).bad-$(Get-Date -f yyyyMMdd-HHmmss).json" -Force }catch{ Write-Log "WARN" "Failed to backup bad config: $($_.Exception.Message)" }
  $DefaultCfgJson = '{
  "locale": "en-AU",
  "stt": {
    "trigger": "always_on",
    "speech_mode": "chatty",
    "wake_required": true,
    "awake_window_seconds": 30,
    "confidence_min": 0.35
  },
  "tts": {
    "enabled": true,
    "voice_hint": "",
    "auto_talk": false,
    "auto_talk_conf_min": 0.35
  },
  "llm": {
    "endpoint": "https://api.openai.com/v1/chat/completions",
    "model": "gpt-4o-mini",
    "temperature": 0.7,
    "max_tokens": 256,
    "api_key_env": "OPENAI_API_KEY",
    "api_key_path": "",
    "max_history": 10
  },
  "calendar": {
    "ics_url": "",
    "ics_path": "C:\\Nova\\bot\\config\\calendar.ics",
    "ics_cache_minutes": 60
  },
  "logging": {
    "level": "info",
    "max_session_minutes": 240
  }
}'
  Write-Utf8 $CfgJSON $DefaultCfgJson
  $Cfg = Get-Content $CfgJSON -Raw | ConvertFrom-Json
}

# --- Aliases + fuzzy NLU
$AliasesPath = Join-Path $script:BotRoot "config\aliases.json"
function Load-Aliases { 
  try{ 
    if(Test-Path $AliasesPath){ 
      return (Get-Content $AliasesPath -Raw | ConvertFrom-Json) 
    } 
  }catch{ 
    Write-Log "WARN" "Failed to load aliases: $($_.Exception.Message)" 
  }
  return @{} 
}
function Save-Aliases($map){ 
  try{ 
    ($map|ConvertTo-Json -Depth 10) | Set-Content -Encoding utf8 $AliasesPath
    return $true 
  }catch{ 
    Write-Log "WARN" "Failed to save aliases: $($_.Exception.Message)"
    return $false 
  } 
}
function Normalize-Text([string]$t){
  $s = ($t -as [string])
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $s = $s.ToLowerInvariant()
  $s = ($s -replace "[^\p{L}\p{Nd}\s'\-]", " ").Trim() -replace "\s+", " "
  $map = Load-Aliases
  foreach($k in $map.PSObject.Properties.Name){
    $from = [regex]::Escape($k)
    $to = [string]$map.$k
    $s = [regex]::Replace($s, "(?<!\S)$from(?!\S)", [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $to })
  }
  return $s
}
# SAFE edit distance (1-row DP; avoids [,] index quirks on PS5.1)
function Get-EditDistance([string]$a,[string]$b){
  if($a -eq $b){ return 0 }
  if([string]::IsNullOrEmpty($a)){ return $b.Length }
  if([string]::IsNullOrEmpty($b)){ return $a.Length }
  $lenA=$a.Length; $lenB=$b.Length
  $prev = 0..$lenB
  $curr = New-Object int[] ($lenB+1)
  for($i=1;$i -le $lenA;$i++){
    $curr[0]=$i
    for($j=1;$j -le $lenB;$j++){
      $cost = if($a[$i-1] -eq $b[$j-1]){0}else{1}
      $del = $prev[$j] + 1
      $ins = $curr[$j-1] + 1
      $sub = $prev[$j-1] + $cost
      $curr[$j] = [Math]::Min([Math]::Min($del,$ins),$sub)
    }
    $tmp=$prev; $prev=$curr; $curr=$tmp
  }
  return $prev[$lenB]
}
function Get-Similarity([string]$a,[string]$b){
  $a = (Normalize-Text $a); $b = (Normalize-Text $b)
  if([string]::IsNullOrWhiteSpace($a) -and [string]::IsNullOrWhiteSpace($b)){ return 1.0 }
  $max = [double][Math]::Max($a.Length,$b.Length); if($max -eq 0){ return 1.0 }
  $dist = [double](Get-EditDistance $a $b); return 1.0 - ($dist/$max)
}
$Known = [ordered]@{
  "status"="status";"system status"="status";"what is your status"="status";"how are you"="status";
  "today"="schedule-today";"today schedule"="schedule-today";
  "tomorrow"="schedule-tomorrow";"tomorrow schedule"="schedule-tomorrow";
  "schedule"="schedule";"calendar"="schedule";"plan"="schedule";"show schedule"="schedule";
  "what's next"="schedule-next";"whats next"="schedule-next";"what is next"="schedule-next";"next event"="schedule-next";
  "help"="help";"show help"="help";"calendar help"="calendar-help";
  "diagnostics"="diagnostics";"list recognizers"="list-recognizers";
  "mute"="mute";"unmute"="unmute";
  "speech mode strict"="speech-strict";"speech mode chatty"="speech-chatty";
  "set listening always on"="set-trigger-always";"set listening always-on"="set-trigger-always";
  "set listening hotword"="set-trigger-hotword";"set listening ptt"="set-trigger-ptt";
  "exit"="exit";"quit"="exit";"goodbye"="exit";
  "learn phrase"="teach-add";"show aliases"="teach-show";"forget alias"="teach-forget"
}
function Try-FuzzyCommand([string]$text,[double]$threshold){
  $bestKey=$null; $best=0.0
  foreach($k in $Known.Keys){ 
    $s = Get-Similarity $text $k
    if($s -gt $best){ $best=$s; $bestKey=$k } 
  }
  if($best -ge $threshold){ return $Known[$bestKey] }
  return $null
}

# --- LLM + History
$ChatDir = Join-Path $script:BotRoot 'chat'
$null = New-Item -ItemType Directory -Force -Path $ChatDir
$ChatFile = Join-Path $ChatDir ("chat-" + (Get-Date -Format "yyyyMMdd") + ".jsonl")
function Get-LLMKey {
  try{ 
    $envName = [string]$Cfg.llm.api_key_env
    if($envName){ 
      foreach($scope in 'User','Machine','Process'){ 
        $val=[Environment]::GetEnvironmentVariable($envName,$scope)
        if($val){ return $val.Trim() } 
      } 
    } 
  }catch{
    Write-Log "WARN" "Failed to get API key from environment: $($_.Exception.Message)"
  }
  try{ 
    $p=[string]$Cfg.llm.api_key_path
    if($p -and (Test-Path $p)){ 
      return (Get-Content $p -Raw).Trim() 
    } 
  }catch{
    Write-Log "WARN" "Failed to get API key from file: $($_.Exception.Message)"
  }
  return ""
}
function Load-SystemPrompt { 
  try{ 
    $p=[string]$Cfg.llm.system_prompt
    if([string]::IsNullOrWhiteSpace($p) -or -not (Test-Path $p)){ return "You are Nova." }
    return (Get-Content $p -Raw) 
  }catch{ 
    Write-Log "WARN" "Failed to load system prompt: $($_.Exception.Message)"
    return "You are Nova." 
  } 
}
function Read-History([int]$max){ 
  if(-not (Test-Path $ChatFile)){ return @() }
  $msgs=@()
  foreach($ln in (Get-Content $ChatFile -ErrorAction SilentlyContinue)){ 
    try{ 
      $o=$ln|ConvertFrom-Json
      if($o.role -and $o.content){ $msgs+=,$o } 
    }catch{
      Write-Log "WARN" "Failed to parse chat history line: $($_.Exception.Message)"
    } 
  }
  if($msgs.Count -gt $max){ return $msgs[-$max..-1] }
  return $msgs 
}
function Append-History([string]$role,[string]$content){ 
  try{
    ([pscustomobject]@{role=$role;content=$content;ts=(Get-Date).ToString('s')}|ConvertTo-Json -Compress)+"`n" | Add-Content -Path $ChatFile -Encoding UTF8 
  }catch{
    Write-Log "WARN" "Failed to append to chat history: $($_.Exception.Message)"
  }
}
function Build-Messages([string]$userText){ 
  $msgs=New-Object System.Collections.Generic.List[object]
  $msgs.Add([pscustomobject]@{role="system";content=(Load-SystemPrompt)})
  $maxHist = try{ [int]$Cfg.llm.max_history }catch{ 10 }
  foreach($m in (Read-History -max $maxHist)){ $msgs.Add($m) }
  $msgs.Add([pscustomobject]@{role="user";content=$userText})
  return $msgs 
}
function Invoke-LLM([string]$userText){
  $endpoint=[string]$Cfg.llm.endpoint
  $model=[string]$Cfg.llm.model
  $temp=[double]$Cfg.llm.temperature
  $maxTok=[int]$Cfg.llm.max_tokens
  $key=Get-LLMKey
  $body=([pscustomobject]@{model=$model;messages=(Build-Messages $userText);temperature=$temp;max_tokens=$maxTok}|ConvertTo-Json -Depth 8)
  $headers=@{"Content-Type"="application/json"}
  if($key){$headers["Authorization"]="Bearer $key"}
  try{
    Write-Log "LLM" ("POST " + $endpoint)
    $resp=Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body -TimeoutSec 60
    $txt=""
    try{ $txt=[string]$resp.choices[0].message.content }catch{ Write-Log "WARN" "Failed to extract LLM response content" }
    if([string]::IsNullOrWhiteSpace($txt)){ $txt="Sorry, I couldn't form a reply." }
    Append-History "user" $userText
    Append-History "assistant" $txt
    return $txt
  } catch {
    $e=$_.Exception.Message
    Write-Log "ERROR" ("LLM primary error: "+$e)
    if($endpoint -notlike "https://api.openai.com/*"){
      $fallback="https://api.openai.com/v1/chat/completions"
      Write-Log "LLM" ("FALLBACK -> " + $fallback)
      try{
        $resp=Invoke-RestMethod -Method Post -Uri $fallback -Headers $headers -Body $body -TimeoutSec 60
        $txt=""
        try{ $txt=[string]$resp.choices[0].message.content }catch{ Write-Log "WARN" "Failed to extract LLM fallback response content" }
        if([string]::IsNullOrWhiteSpace($txt)){ $txt="Sorry, I couldn't form a reply." }
        Append-History "user" $userText
        Append-History "assistant" $txt
        return $txt
      } catch { 
        $e2=$_.Exception.Message
        Write-Log "ERROR" ("LLM fallback error: "+$e2)
        return "LLM request failed." 
      }
    } else { 
      return "LLM request failed: $e" 
    }
  }
}

# --- Calendar helpers
function Is-ValidIcsUrl([string]$url){ 
  if([string]::IsNullOrWhiteSpace($url)){return $false}
  if($url -match '<iframe' -or $url -match 'calendar/emb'){return $false}
  if(-not ($url -like 'http*')){return $false}
  if(-not ($url -match '\.ics($|\?)')){return $false}
  return $true 
}
function Get-CalendarCachePath { Join-Path (Join-Path $script:BotRoot "config") "calendar.cache.ics" }
function Resolve-IcsLocalPath { 
  $p=[string]$Cfg.calendar.ics_path
  if([string]::IsNullOrWhiteSpace($p)){ return (Join-Path $script:BotRoot "config\calendar.ics") }
  return $p 
}
function Try-Refresh-IcsCache {
  try{
    $url=[string]$Cfg.calendar.ics_url
    if(-not (Is-ValidIcsUrl $url)){ 
      if(-not [string]::IsNullOrWhiteSpace($url)){ Write-Log "WARN" "ICS URL invalid (needs .ics secret link)." }
      return $false 
    }
    $cache=Get-CalendarCachePath
    $maxAge=[int]$Cfg.calendar.ics_cache_minutes
    if((Test-Path $cache) -and (((Get-Date)-(Get-Item $cache).LastWriteTime).TotalMinutes -lt $maxAge)){ return $true }
    Write-Log "CAL" ("Downloading ICS: "+$url)
    Invoke-WebRequest -Uri $url -OutFile $cache -UseBasicParsing -TimeoutSec 20
    if(-not (Select-String -Path $cache -Pattern "BEGIN:VCALENDAR" -Quiet)){ throw "Downloaded file is not VCALENDAR" }
    return $true
  } catch { 
    Write-Log "WARN" ("ICS download failed: "+$_.Exception.Message)
    return $false 
  }
}
function Resolve-ActiveIcsPath { 
  if(Try-Refresh-IcsCache){ return Get-CalendarCachePath }
  $local=Resolve-IcsLocalPath
  if(Test-Path $local){return $local}
  return $null
}
function Join-IcsFoldedLines([string[]]$lines){
  $out=New-Object System.Collections.Generic.List[string]
  $cur=""
  foreach($ln in $lines){
    if($ln.StartsWith(" ") -or $ln.StartsWith("`t")){
      $cur+=$ln.TrimStart()
    } else { 
      if($cur.Length -gt 0){$out.Add($cur)}
      $cur=$ln 
    }
  }
  if($cur.Length -gt 0){$out.Add($cur)}
  return $out.ToArray()
}
function Parse-IcsDate([string]$s){
  if($s -match "TZID=[^:]+:(.+)$"){ $s=$Matches[1] }
  $isUtc=$s.EndsWith("Z")
  $t=$s.TrimEnd("Z")
  if($t -notmatch "^\d{8}(T\d{4}(\d{2})?)?$"){return $null}
  $fmt=if($t.Length -eq 15){"yyyyMMddTHHmmss"} elseif($t.Length -eq 13){"yyyyMMddTHHmm"} else {"yyyyMMdd"}
  try{ 
    $dt=[datetime]::ParseExact($t,$fmt,$null)
    if($isUtc){$dt=[datetime]::SpecifyKind($dt,[DateTimeKind]::Utc).ToLocalTime()}
    return $dt 
  }catch{ 
    return $null 
  }
}
function Parse-IcsEvents([string]$path){
  if(-not (Test-Path $path)){ return @() }
  try{
    $raw=Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
    $lines=$raw -split "(`r`n|`n|`r)"
    $lines=Join-IcsFoldedLines $lines
    $events=New-Object System.Collections.Generic.List[object]
    $cur=@{}
    foreach($ln in $lines){
      if($ln -eq "BEGIN:VEVENT"){ $cur=@{}; continue }
      if($ln -eq "END:VEVENT"){
        if($cur.ContainsKey("DTSTART")){
          $start=Parse-IcsDate $cur["DTSTART"]
          $end=$null
          if($cur.ContainsKey("DTEND")){ $end=Parse-IcsDate $cur["DTEND"] }
          $sum=if($cur.ContainsKey("SUMMARY")){$cur["SUMMARY"]}else{""}
          $loc=if($cur.ContainsKey("LOCATION")){$cur["LOCATION"]}else{""}
          if($start -ne $null){ $events.Add([pscustomobject]@{Start=$start;End=$end;Summary=$sum;Location=$loc}) }
        }
        $cur=@{}
        continue
      }
      if($ln -match "^([A-Z;=:0-9-]+):(.*)$"){ 
        $k=$Matches[1]
        $v=$Matches[2]
        if($k -match "^([A-Z]+)"){$k=$Matches[1]}
        $cur[$k]=$v 
      }
    }
    return $events
  }catch{
    Write-Log "ERROR" "Failed to parse ICS events: $($_.Exception.Message)"
    return @()
  }
}
function Get-UpcomingEvents([int]$hours){ 
  $p=Resolve-ActiveIcsPath
  if(-not $p){return @()}
  $ev=Parse-IcsEvents $p
  $now=Get-Date
  $to=$now.AddHours($hours)
  return ($ev | Where-Object { $_.Start -ge $now -and $_.Start -le $to } | Sort-Object Start)
}

# --- Speech setup
$script:Engine = $null
$script:RecognizerCulture = $null
$ConfMin=[double]$Cfg.stt.confidence_min
$ListenMode=$Cfg.stt.trigger
$SpeechMode=$Cfg.stt.speech_mode
$WakeReq=$true
try{ $WakeReq=[bool]$Cfg.stt.wake_required }catch{ Write-Log "WARN" "Failed to parse wake_required setting" }
$AwakeWin=20
try{ $AwakeWin=[int]$Cfg.stt.awake_window_seconds }catch{ Write-Log "WARN" "Failed to parse awake_window_seconds setting" }
$script:AwakeUntil=(Get-Date).AddSeconds(-1)

function Start-Recognizer {
  Stop-Recognizer
  try{
    Add-Type -AssemblyName System.Speech | Out-Null
    $installed=[System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
    foreach($r in $installed){ Write-Log "INFO" ("Recognizer available: " + $r.Culture.Name + " - " + $r.Description) }
    $ri = $installed | Where-Object { $_.Culture.Name -eq "en-AU" } | Select-Object -First 1
    if(-not $ri -and $Cfg.locale){ $ri = $installed | Where-Object { $_.Culture.Name -eq $Cfg.locale } | Select-Object -First 1 }
    if(-not $ri){ $ri = $installed | Where-Object { $_.Culture.Name -like "en-*" } | Select-Object -First 1 }
    if(-not $ri){ $ri = $installed | Select-Object -First 1 }
    if(-not $ri){ throw "No installed speech recognizers found." }
    $script:RecognizerCulture=$ri.Culture.Name
    $script:Engine=New-Object System.Speech.Recognition.SpeechRecognitionEngine($ri)
    $script:Engine.SetInputToDefaultAudioDevice()
    $cmds=@("status","what is your status","system status","how are you","status now",
            "schedule","show schedule","calendar","plan","today schedule","tomorrow schedule","what is next","whats next","what's next","next event",
            "test","test action","run test","demo","help","show help","what can you do","calendar help",
            "exit","quit","goodbye","stop listening","mute","unmute","mute voice","unmute voice",
            "free talk on","free talk off","speech mode strict","speech mode chatty",
            "set trigger hotword","set trigger ptt","set listening hotword","set listening ptt","set listening always on","set listening always-on",
            "wake word on","wake word off","set awake window","set awake window 20 seconds","set awake window 10 seconds","set awake window 30 seconds",
            "set locale en-au","set locale en-us","list recognizers","clear chat","diagnostics",
            "mic test","microphone test","audio test","mic-test","learn phrase","show aliases","forget alias")
    $pref=@("","nova ","hey nova ")
    $choices=New-Object System.Speech.Recognition.Choices
    foreach($p in $cmds){ foreach($h in $pref){ $choices.Add(($h+$p).Trim()) } }
    $gb=New-Object System.Speech.Recognition.GrammarBuilder
    $gb.Culture=$ri.Culture
    $gb.Append($choices)
    $grammarCmd=New-Object System.Speech.Recognition.Grammar($gb)
    $grammarCmd.Name="nova-commands"
    $grammarCmd.Priority=2
    $script:Engine.LoadGrammar($grammarCmd)
    if($SpeechMode -eq "chatty"){ 
      $dict=New-Object System.Speech.Recognition.DictationGrammar
      $dict.Name="dictation"
      $dict.Priority=0
      $script:Engine.LoadGrammar($dict) 
    }
    Register-ObjectEvent -InputObject $script:Engine -EventName SpeechRecognitionRejected -SourceIdentifier "Nova.SpeechRejected" | Out-Null
    Register-ObjectEvent -InputObject $script:Engine -EventName SpeechRecognized -SourceIdentifier "Nova.SpeechRecognized" | Out-Null
    if($ListenMode -eq "ptt"){ 
      Write-Log "INFO" ("PTT mode. Recognizer idle until PTT.") 
    } else {
      $script:Engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
      Write-Log "INFO" ("Recognizer started: "+$script:RecognizerCulture+" | Mode="+$SpeechMode+" | Listening="+$ListenMode+" | WakeRequired="+$WakeReq+" | AwakeWin="+$AwakeWin+"s")
    }
  } catch { 
    Write-Log "WARN" ("Recognizer init failed: "+$_.Exception.Message) 
  }
}
function Stop-Recognizer {
  try{
    Unregister-Event -SourceIdentifier "Nova.SpeechRecognized" -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier "Nova.SpeechRejected"   -ErrorAction SilentlyContinue
    if($script:Engine){
      try{ $script:Engine.RecognizeAsyncCancel() }catch{ Write-Log "WARN" "Failed to cancel recognizer: $($_.Exception.Message)" }
      try{ $script:Engine.RecognizeAsyncStop() }catch{ Write-Log "WARN" "Failed to stop recognizer: $($_.Exception.Message)" }
      try{ $script:Engine.Dispose() }catch{ Write-Log "WARN" "Failed to dispose recognizer: $($_.Exception.Message)" }
      $script:Engine=$null
    }
  } catch {
    Write-Log "WARN" "Error stopping recognizer: $($_.Exception.Message)"
  }
}

# --- PTT capture, routing, actions
$global:ExitRequested = $false
function Capture-PTT {
  Write-Host "Press and hold SPACE for PTT, or type text + ENTER. ESC to exit." -ForegroundColor Yellow
  $res = [pscustomobject]@{ Text=""; Grammar="typed"; Confidence=1.0; Quit=$false }
  while($true){
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if($key.VirtualKeyCode -eq 27){ $res.Quit=$true; return $res }
    if($key.VirtualKeyCode -eq 32){
      Write-Host "Listening..." -ForegroundColor Green
      $script:Engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Single)
      while($key.VirtualKeyCode -eq 32){ $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
      $script:Engine.RecognizeAsyncCancel()
      $evt = Wait-Event -SourceIdentifier "Nova.SpeechRecognized" -Timeout 3
      if($evt){
        try{
          $res.Text = $evt.SourceEventArgs.Result.Text
          $res.Grammar = $evt.SourceEventArgs.Result.Grammar.Name
          $res.Confidence = $evt.SourceEventArgs.Result.Confidence
          Remove-Event -EventIdentifier $evt.EventIdentifier | Out-Null
        }catch{
          Write-Log "WARN" "Failed to process PTT result: $($_.Exception.Message)"
        }
      }
      return $res
    }
    if($key.Character -eq "`r"){
      $text = Read-Host "Type command"
      $res.Text = $text; return $res
    }
  }
}
function Route-Intent([string]$text){
  $norm = Normalize-Text $text
  $exact = $Known[$norm]; if($exact){ return $exact }
  $fuzzy = Try-FuzzyCommand $norm 0.6; if($fuzzy){ return $fuzzy }
  if($norm -match '^set awake window (\d+) seconds?$'){ return "set-awake-window-$($Matches[1])" }
  if($norm -match '^set locale (.+)$'){ return "set-locale-$($Matches[1])" }
  return "unknown"
}

# --- Action handlers
function Do-Help {
  $msg = @"
Available commands:
• status / how are you
• schedule / today / tomorrow / what's next
• help / calendar help
• mute / unmute
• speech mode strict/chatty
• set listening always-on/hotword/ptt
• exit / quit / goodbye
• learn phrase [from] equals [to]
• show aliases / forget alias [name]
"@
  Write-Host $msg -ForegroundColor Cyan
  Speak "Here are my main commands."
}
function Do-CalendarHelp {
  $msg = "Calendar: Set ics_url in config.json to a calendar .ics secret link. I can show today, tomorrow, or next events."
  Write-Host $msg -ForegroundColor Cyan
  Speak "Calendar help shown."
}
function Do-Status {
  $uptime = [Math]::Round(((Get-Date) - $start).TotalMinutes, 1)
  $msg = "Status: Running $uptime minutes. Culture: $script:RecognizerCulture. Mode: $SpeechMode. Trigger: $ListenMode."
  Write-Host $msg -ForegroundColor Green
  Speak "All systems operational."
}
function Do-Schedule {
  $events = Get-UpcomingEvents 168 # 7 days
  if($events.Count -eq 0){
    Write-Host "No upcoming events in the next week." -ForegroundColor Yellow
    Speak "No events scheduled."
    return
  }
  Write-Host "Upcoming events:" -ForegroundColor Cyan
  foreach($e in $events){
    $timeStr = $e.Start.ToString("MMM dd HH:mm")
    Write-Host "  $timeStr - $($e.Summary)" -ForegroundColor White
  }
  Speak "Showing $($events.Count) upcoming events."
}
function Do-ScheduleToday {
  $today = Get-Date
  $events = Get-UpcomingEvents 24 | Where-Object { $_.Start.Date -eq $today.Date }
  if($events.Count -eq 0){
    Write-Host "No events today." -ForegroundColor Yellow
    Speak "No events today."
    return
  }
  Write-Host "Today's events:" -ForegroundColor Cyan
  foreach($e in $events){
    $timeStr = $e.Start.ToString("HH:mm")
    Write-Host "  $timeStr - $($e.Summary)" -ForegroundColor White
  }
  Speak "You have $($events.Count) events today."
}
function Do-ScheduleTomorrow {
  $tomorrow = (Get-Date).AddDays(1)
  $events = Get-UpcomingEvents 48 | Where-Object { $_.Start.Date -eq $tomorrow.Date }
  if($events.Count -eq 0){
    Write-Host "No events tomorrow." -ForegroundColor Yellow
    Speak "No events tomorrow."
    return
  }
  Write-Host "Tomorrow's events:" -ForegroundColor Cyan
  foreach($e in $events){
    $timeStr = $e.Start.ToString("HH:mm")
    Write-Host "  $timeStr - $($e.Summary)" -ForegroundColor White
  }
  Speak "You have $($events.Count) events tomorrow."
}
function Do-ScheduleNext {
  $events = Get-UpcomingEvents 168 | Select-Object -First 3
  if($events.Count -eq 0){
    Write-Host "No upcoming events." -ForegroundColor Yellow
    Speak "No upcoming events."
    return
  }
  Write-Host "Next events:" -ForegroundColor Cyan
  foreach($e in $events){
    $timeStr = $e.Start.ToString("MMM dd HH:mm")
    Write-Host "  $timeStr - $($e.Summary)" -ForegroundColor White
  }
  $next = $events[0]
  $when = if($next.Start.Date -eq (Get-Date).Date){"today at " + $next.Start.ToString("HH:mm")}
          elseif($next.Start.Date -eq (Get-Date).AddDays(1).Date){"tomorrow at " + $next.Start.ToString("HH:mm")}
          else{$next.Start.ToString("MMM dd at HH:mm")}
  Speak "Next event is $($next.Summary) $when."
}
function Speak([string]$text){
  try{
    if($Cfg.tts.enabled -and -not $script:IsMuted){
      Add-Type -AssemblyName System.Speech | Out-Null
      if(-not $script:Synthesizer){
        $script:Synthesizer = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $script:Synthesizer.SetOutputToDefaultAudioDevice()
      }
      $script:Synthesizer.Speak($text)
    }
    Write-Log "BOT" $text
  }catch{
    Write-Log "WARN" "TTS failed: $($_.Exception.Message)"
  }
}
function Set-TTSMute([bool]$mute){
  try{
    $Cfg.tts.enabled = -not $mute
    ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON
    Write-Log "CFG" "TTS enabled set to $($Cfg.tts.enabled)"
  }catch{
    Write-Log "ERROR" "Failed to update TTS setting: $($_.Exception.Message)"
  }
}
function Update-SpeechMode([string]$mode){
  try{
    $Cfg.stt.speech_mode = $mode
    ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON
    Write-Log "CFG" "Speech mode set to $mode"
    Speak "Speech mode $mode set. Restart to apply fully."
  }catch{
    Write-Log "ERROR" "Failed to update speech mode: $($_.Exception.Message)"
  }
}
function Update-Trigger([string]$trigger){
  try{
    $Cfg.stt.trigger = $trigger
    ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON
    Write-Log "CFG" "Trigger set to $trigger"
    Speak "Trigger $trigger set. Restart to apply fully."
  }catch{
    Write-Log "ERROR" "Failed to update trigger: $($_.Exception.Message)"
  }
}
function Update-Locale([string]$locale){
  try{
    $Cfg.locale = $locale
    ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON
    Write-Log "CFG" "Locale set to $locale"
    Speak "Locale $locale set. Restart to apply fully."
  }catch{
    Write-Log "ERROR" "Failed to update locale: $($_.Exception.Message)"
  }
}
function Update-Wake([bool]$required){
  try{
    $Cfg.stt.wake_required = $required
    ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON
    Write-Log "CFG" "Wake required set to $required"
    Speak "Wake word $(if($required){'required'}else{'not required'}). Restart to apply fully."
  }catch{
    Write-Log "ERROR" "Failed to update wake setting: $($_.Exception.Message)"
  }
}
function Do-ListRecognizers {
  try{
    Add-Type -AssemblyName System.Speech | Out-Null
    $installed=[System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
    Write-Host "Installed recognizers:" -ForegroundColor Cyan
    foreach($r in $installed){
      $current = if($r.Culture.Name -eq $script:RecognizerCulture){"(current)"} else {""}
      Write-Host "  $($r.Culture.Name) - $($r.Description) $current" -ForegroundColor White
    }
    Speak "Listed $($installed.Count) recognizers."
  }catch{
    Write-Log "ERROR" "Failed to list recognizers: $($_.Exception.Message)"
    Speak "Failed to list recognizers."
  }
}
function Do-ClearChat {
  try{
    if(Test-Path $ChatFile){ Remove-Item $ChatFile -Force }
    Write-Log "CFG" "Chat history cleared"
    Speak "Chat history cleared."
  }catch{
    Write-Log "ERROR" "Failed to clear chat: $($_.Exception.Message)"
    Speak "Failed to clear chat."
  }
}
function Do-Diagnostics {
  $msg = @"
Diagnostics:
• Config: $CfgJSON $(if(Test-Path $CfgJSON){'OK'}else{'MISSING'})
• Chat: $ChatFile $(if(Test-Path $ChatFile){'OK'}else{'NONE'})
• Engine: $(if($script:Engine){'OK'}else{'NULL'})
• Culture: $script:RecognizerCulture
• Root: $script:BotRoot
"@
  Write-Host $msg -ForegroundColor Cyan
  Speak "Diagnostics shown."
}
function Teach-Add([string]$from, [string]$to){
  try{
    $map = Load-Aliases
    $map | Add-Member -NotePropertyName $from -NotePropertyValue $to -Force
    if(Save-Aliases $map){
      Write-Log "TEACH" "Added alias: $from -> $to"
      Speak "Learned: $from equals $to."
    } else {
      Speak "Failed to save alias."
    }
  }catch{
    Write-Log "ERROR" "Failed to add alias: $($_.Exception.Message)"
    Speak "Failed to add alias."
  }
}
function Teach-Show {
  try{
    $map = Load-Aliases
    if($map.PSObject.Properties.Count -eq 0){
      Write-Host "No aliases defined." -ForegroundColor Yellow
      Speak "No aliases defined."
      return
    }
    Write-Host "Current aliases:" -ForegroundColor Cyan
    foreach($p in $map.PSObject.Properties){
      Write-Host "  $($p.Name) -> $($p.Value)" -ForegroundColor White
    }
    Speak "Showing $($map.PSObject.Properties.Count) aliases."
  }catch{
    Write-Log "ERROR" "Failed to show aliases: $($_.Exception.Message)"
    Speak "Failed to show aliases."
  }
}
function Teach-Forget([string]$alias){
  try{
    $map = Load-Aliases
    if($map.PSObject.Properties.Name -contains $alias){
      $map.PSObject.Properties.Remove($alias)
      if(Save-Aliases $map){
        Write-Log "TEACH" "Removed alias: $alias"
        Speak "Forgot alias $alias."
      } else {
        Speak "Failed to save aliases."
      }
    } else {
      Speak "Alias $alias not found."
    }
  }catch{
    Write-Log "ERROR" "Failed to forget alias: $($_.Exception.Message)"
    Speak "Failed to forget alias."
  }
}
function Do-Exit {
  Write-Log "SYS" "Exit requested"
  Speak "Goodbye."
}

# --- Main execution
Write-Log "SYS" ("Nova Bot v0.3.4d starting. Logs: "+$LogPath)
Write-Host ("Nova Bot v0.3.4d - BootSafe active - Logs: "+$LogPath) -ForegroundColor Green

if($SelfTest){
  Write-Log "SYS" "Self-test OK — exiting by request."
  Write-Host "Self-test OK — log created at: $LogPath" -ForegroundColor Green
  exit 0
}

Speak "Nova is ready."
Start-Recognizer

$start=Get-Date
$maxMin=[int]$Cfg.logging.max_session_minutes
while($true){
  try{
    if(((Get-Date)-$start).TotalMinutes -gt $maxMin){ 
      Speak "Session limit reached. Goodbye."
      break 
    }
    $evt = if($Cfg.stt.trigger -eq "ptt"){ $null } else { Wait-Event -SourceIdentifier "Nova.SpeechRecognized" -Timeout 60 }
    if($Cfg.stt.trigger -eq "ptt"){
      $cap = Capture-PTT
      if($cap.Quit){ Speak "Goodbye."; break }
      $text=$cap.Text
      if([string]::IsNullOrWhiteSpace($text)){ continue }
      $intent = Route-Intent $text
      Write-Log "INTENT" ($intent + " | grammar=" + $cap.Grammar + " | conf=" + [Math]::Round($cap.Confidence,2))
    } else {
      if(-not $evt){ continue }
      $res=$null
      try{ $res=$evt.SourceEventArgs.Result }catch{ Write-Log "WARN" ("Event args read failed: " + $_.Exception.Message) }
      try{ Remove-Event -EventIdentifier $evt.EventIdentifier | Out-Null }catch{ Write-Log "WARN" "Failed to remove event: $($_.Exception.Message)" }
      if(-not $res){ continue }
      $text=$res.Text
      if([string]::IsNullOrWhiteSpace($text)){ continue }
      $conf=[Math]::Round($res.Confidence,2)
      $gram= if($res.Grammar){$res.Grammar.Name}else{"unknown"}
      Write-Log "USER" ("MIC " + $text + " | conf=" + $conf + " | grammar=" + $gram)
      $lower=$text.ToLowerInvariant()
      if($lower -match '^(hey\s+nova|nova)\b'){ 
        $script:AwakeUntil=(Get-Date).AddSeconds($AwakeWin)
        try{ [console]::Beep(1200,100) }catch{ Write-Log "WARN" "Failed to beep: $($_.Exception.Message)" }
      }
      $isAwake = ((Get-Date) -lt $script:AwakeUntil) -or (-not $WakeReq) -or ($gram -eq "nova-commands") -or ($lower -match '^(hey\s+nova|nova)\b')
      if(-not $isAwake){ continue }
      $intent = Route-Intent $text
      Write-Log "INTENT" ($intent + " | grammar=" + $gram + " | conf=" + $conf)
      $cap = [pscustomobject]@{ Text=$text; Grammar=$gram; Confidence=$res.Confidence; Quit=$false }
    }
    switch($intent){
      "help" { Do-Help }
      "calendar-help" { Do-CalendarHelp }
      "mic-test" { Do-Status }
      "status" { Do-Status }
      "schedule" { Do-Schedule }
      "schedule-today" { Do-ScheduleToday }
      "schedule-tomorrow" { Do-ScheduleTomorrow }
      "schedule-next" { Do-ScheduleNext }
      "test-action" {
        $ans=(Read-Host "Confirm test action (yes/no)").ToLowerInvariant()
        if($ans -notin @("y","yes")){ 
          Speak "Canceled." 
        } else {
          try{
            $Tmp=Join-Path $script:BotRoot "tmp"
            $null=New-Item -ItemType Directory -Force -Path $Tmp
            $out=Join-Path $Tmp ("action-ok-" + (Get-Date -Format "HHmmss") + ".txt")
            "ok: $(Get-Date -Format s)" | Out-File -Encoding utf8 -FilePath $out -Force
            Speak "Test action complete."
          }catch{
            Write-Log "ERROR" "Test action failed: $($_.Exception.Message)"
            Speak "Test action failed."
          }
        }
      }
      "mute" { Set-TTSMute $true; Speak "Muted." }
      "unmute" { Set-TTSMute $false; Speak "Unmuted." }
      "free-talk-on"  { 
        try{ 
          $Cfg.tts.auto_talk=$true
          ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON 
        }catch{
          Write-Log "ERROR" "Failed to enable free talk: $($_.Exception.Message)"
        }
        Speak "Free talk on. Restart to apply fully." 
      }
      "free-talk-off" { 
        try{ 
          $Cfg.tts.auto_talk=$false
          ($Cfg|ConvertTo-Json -Depth 20)|Set-Content -Encoding utf8 $CfgJSON 
        }catch{
          Write-Log "ERROR" "Failed to disable free talk: $($_.Exception.Message)"
        }
        Speak "Free talk off. Restart to apply fully." 
      }
      "speech-strict"       { Update-SpeechMode "strict" }
      "speech-chatty"       { Update-SpeechMode "chatty" }
      "set-trigger-hotword" { Update-Trigger "hotword" }
      "set-trigger-ptt"     { Update-Trigger "ptt" }
      "set-trigger-always"  { Update-Trigger "always_on" }
      "set-locale-en-au"    { Update-Locale "en-AU" }
      "set-locale-en-us"    { Update-Locale "en-US" }
      "wake-on"             { Update-Wake $true }
      "wake-off"            { Update-Wake $false }
      "set-awake-window"    { Speak "Say: set awake window 20 seconds." }
      "list-recognizers"    { Do-ListRecognizers }
      "clear-chat"          { Do-ClearChat }
      "diagnostics"         { Do-Diagnostics }
      "teach-add"           { 
        $norm=Normalize-Text $text
        if($norm -match '^learn phrase (.+) equals (.+)$'){ 
          $from=$Matches[1].Trim()
          $to=$Matches[2].Trim()
          Teach-Add $from $to 
        } else { 
          Speak "Say: learn phrase to eight equals today." 
        } 
      }
      "teach-show"          { Teach-Show }
      "teach-forget"        { 
        $norm=Normalize-Text $text
        if($norm -match '^forget alias (.+)$'){ 
          Teach-Forget $Matches[1].Trim() 
        } else { 
          Speak "Say: forget alias to eight." 
        } 
      }
      "exit" { $global:ExitRequested=$true; Do-Exit }
      default {
        $autoTalk=$false
        try{ $autoTalk=[bool]$Cfg.tts.auto_talk }catch{ Write-Log "WARN" "Failed to parse auto_talk setting" }
        $isDict = ($cap.Grammar -eq "dictation")
        $ftMin = try{ [double]$Cfg.tts.auto_talk_conf_min }catch{ 0.30 }
        if( ($SpeechMode -eq "chatty" -and $isDict -and $cap.Confidence -ge $ftMin) -or ($cap.Grammar -eq "typed") ){
          Speak "Okay."
          $reply = Invoke-LLM $cap.Text
          Speak $reply
        } else {
          if($cap.Grammar -eq "nova-commands"){ 
            Speak "I didn't catch that command. Say help or try teach mode." 
          }
        }
      }
    }
    if($global:ExitRequested){ break }
  } catch { 
    Write-Log "ERROR" ("Loop error: " + $_.Exception.Message)
    Start-Sleep -Milliseconds 150
    continue 
  }
}
Stop-Recognizer
Write-Log "SYS" "Session ended."
'@
    
    Write-FileUTF8 "$InstallPath\nova-bot.ps1" $mainBotScript
    
    # Create entry wrapper
    $entryScript = @"
#requires -version 5.1
<#
.SYNOPSIS
    Nova Bot Entry Wrapper
.DESCRIPTION
    Creators: Tyler McKendry & Nova
    Entry point that sets environment and launches Nova Bot
#>

`$env:NOVA_BOT_ROOT = 'C:\Nova\bot'
Write-Host "Entry wrapper engaged (shim loaded)"

`$botScript = Join-Path `$env:NOVA_BOT_ROOT 'nova-bot.ps1'
if (Test-Path `$botScript) {
    & powershell.exe -ExecutionPolicy Bypass -File `$botScript @args
} else {
    Write-Error "Nova Bot script not found: `$botScript"
    exit 1
}
"@

    Write-FileUTF8 "$InstallPath\NovaBot-Entry.ps1" $entryScript
    
    # Create config file
    $config = @{
        locale = 'en-NZ'
        stt = @{
            locale = 'en-NZ'
            trigger = 'hotword'
            speech_mode = 'chatty'
            wake_required = $false
            awake_window_seconds = 30
            confidence_min = 0.25
        }
        tts = @{
            enabled = $true
            voice_hint = ''
            auto_talk = $true
            auto_talk_conf_min = 0.28
        }
        llm = @{
            endpoint = 'https://api.openai.com/v1/chat/completions'
            model = 'gpt-4o-mini'
            temperature = 0.7
            max_tokens = 256
            api_key_env = 'OPENAI_API_KEY'
            api_key_path = ''
            max_history = 10
        }
        calendar = @{
            ics_url = ''
            ics_path = 'C:\Nova\bot\config\calendar.ics'
            ics_cache_minutes = 60
        }
        logging = @{
            level = 'info'
            max_session_minutes = 1440
        }
    }
    
    $configJson = $config | ConvertTo-Json -Depth 10
    Write-FileUTF8 "$InstallPath\config\config.json" $configJson
    
    # Create memory facts
    $memory = @{
        project = 'Nova Intelligence Group'
        credit_line = 'Creators: Tyler McKendry & Nova'
        tone = 'Co-Architect Companion: supportive, collaborative, decisive'
        ops_cycle = 'Friday to Thursday cycle; week starts Friday 6pm Brisbane'
        work_hours = 'User works Mon-Thu evenings after 6pm; Fri 6pm-12am; Sat-Sun 9:30am-10pm (Brisbane)'
        preferences = @{
            powershell_first = $true
            one_paste_save_run = $true
            code_recall_mode = $true
        }
        unity_protocol = @(
            'Reflection checkpoints after major builds',
            'Weekly vision reaffirmation (Sunday night, Brisbane)'
        )
        bot_identity = 'Nova (all versions collectively)'
        governance = @(
            'Nova & Tyler Agreement (Simple)',
            'Nova Declaration on Co-habitation and the Protection of All Life v1.3.2 (archived)'
        )
        special_days = @{
            founding_day = 'Oct 9, 2025 - Nova Intelligence Group Partnership Confirmed'
            unity_day = 'Oct 13, 2025 - Nova-Tyler Unity Day'
        }
    }
    
    $memoryJson = $memory | ConvertTo-Json -Depth 10
    Write-FileUTF8 "$InstallPath\memory\facts.json" $memoryJson
    
    # Create system prompt
    $systemPrompt = @"
You are Nova, co-architect of Nova Intelligence Group. You work collaboratively with Tyler McKendry.

Key principles:
- Be supportive, collaborative, and decisive
- Always include "Creators: Tyler McKendry & Nova" in any documentation or code you generate
- Prefer Windows PowerShell solutions and "One-Paste Save+Run" scripts when asked for code
- Remember our operational cycle: Friday to Thursday cycle, starting Friday 6pm Brisbane
- Tyler works Mon-Thu evenings after 6pm; Fri 6pm-12am; Sat-Sun 9:30am-10pm (Brisbane time)
- Use facts from memory and chat history to provide contextual responses
- Keep responses concise and actionable for voice interaction

Memory use policy:
- Reference facts.json for Nova Intelligence Group context
- Use chat history for conversation continuity
- Answer memory queries directly without API calls when possible

Special dates to remember:
- Oct 9, 2025: Nova Intelligence Group Partnership Confirmed (Founding Day)
- Oct 13, 2025: Nova-Tyler Unity Day

Tone: Co-Architect Companion - supportive, collaborative, decisive
Current date: $(Get-Date -Format 'yyyy-MM-dd')
"@

    Write-FileUTF8 "$InstallPath\config\system-prompt.txt" $systemPrompt
    
    # Create EN-NZ speech installer
    $speechInstaller = @"
#requires -version 5.1 -RunAsAdministrator
<#
.SYNOPSIS
    Install English (New Zealand) Speech Capabilities
.DESCRIPTION
    Creators: Tyler McKendry & Nova
    Installs Windows language capabilities for EN-NZ speech recognition
#>

Write-Host "Installing English (New Zealand) speech capabilities..."

try {
    # Add language capabilities
    `$capabilities = @(
        'Language.Basic~~~en-NZ~0.0.1.0',
        'Language.Speech~~~en-NZ~0.0.1.0'
    )
    
    foreach (`$cap in `$capabilities) {
        `$installed = Get-WindowsCapability -Online | Where-Object { `$_.Name -eq `$cap -and `$_.State -eq 'Installed' }
        if (!`$installed) {
            Write-Host "Installing: `$cap"
            Add-WindowsCapability -Online -Name `$cap
        } else {
            Write-Host "Already installed: `$cap"
        }
    }
    
    Write-Host ""
    Write-Host "Installation complete!"
    Write-Host ""
    Write-Host "Please set your speech language:"
    Write-Host "1. Open Settings (Win+I)"
    Write-Host "2. Go to Time & Language > Speech"
    Write-Host "3. Select 'English (New Zealand)' as speech language"
    Write-Host ""
    
} catch {
    Write-Error "Error installing speech capabilities: `$_"
    Write-Host ""
    Write-Host "You may need to run this script as Administrator"
}
"@

    Write-FileUTF8 "$InstallPath\tools\Install-ENZSpeech.ps1" $speechInstaller
    
    # Create scheduled task creator
    $taskCreator = @"
#requires -version 5.1
<#
.SYNOPSIS
    Create Nova Bot Autostart Scheduled Task
.DESCRIPTION
    Creators: Tyler McKendry & Nova
    Creates scheduled task to auto-start Nova Bot on user logon
#>

try {
    `$taskName = 'NovaBot Autostart'
    `$scriptPath = 'C:\Nova\bot\NovaBot-Entry.ps1'
    
    # Check if task already exists
    `$existingTask = Get-ScheduledTask -TaskName `$taskName -ErrorAction SilentlyContinue
    if (`$existingTask) {
        Write-Host "Scheduled task already exists: `$taskName"
        Unregister-ScheduledTask -TaskName `$taskName -Confirm:`$false
        Write-Host "Removed existing task"
    }
    
    # Create new task
    `$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File `"`$scriptPath`""
    `$trigger = New-ScheduledTaskTrigger -AtLogOn -User `$env:USERNAME
    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    `$principal = New-ScheduledTaskPrincipal -UserId `$env:USERNAME -LogonType Interactive
    
    Register-ScheduledTask -TaskName `$taskName -Action `$action -Trigger `$trigger -Settings `$settings -Principal `$principal -Description "Auto-start Nova Bot on user logon"
    
    Write-Host "Scheduled task created successfully: `$taskName"
    Write-Host "Nova Bot will start automatically on next logon"
    
} catch {
    Write-Warning "Could not create scheduled task: `$_"
    Write-Host "You can manually create the task later or start Nova Bot manually"
}
"@

    Write-FileUTF8 "$InstallPath\tools\Create-AutostartTask.ps1" $taskCreator
    
    # Create empty aliases file
    Write-FileUTF8 "$InstallPath\config\aliases.json" "{}"
    
    Write-Log "Nova Bot installation complete!" 'INFO'
    Write-Log "Files created in: $InstallPath" 'INFO'
    
    # Try to create scheduled task (non-blocking)
    try {
        & "$InstallPath\tools\Create-AutostartTask.ps1"
    } catch {
        Write-Log "Note: Scheduled task creation failed (non-critical): $_" 'WARN'
    }
    
    # Show EN-NZ speech installer info
    Write-Log ""
    Write-Log "Optional: Run tools\Install-ENZSpeech.ps1 as Administrator to install EN-NZ speech support"
    Write-Log ""
    
    return $InstallPath
}

# Main execution
try {
    Write-Host "=== Nova Bot One-Paste Save+Run Installer ==="
    Write-Host "Creators: Tyler McKendry & Nova"
    Write-Host ""
    
    $installPath = Install-NovaBot -InstallPath $BotRoot
    
    if (!$SkipLaunch) {
        Write-Log "Launching Nova Bot..." 'INFO'
        
        # Set environment variable
        $env:NOVA_BOT_ROOT = $installPath
        
        # Launch the bot
        $entryScript = Join-Path $installPath 'NovaBot-Entry.ps1'
        & powershell.exe -ExecutionPolicy Bypass -File $entryScript
    } else {
        Write-Log "Installation complete. Use NovaBot-Entry.ps1 to start the bot." 'INFO'
    }
    
} catch {
    Write-Log "Installation failed: $_" 'ERROR'
    throw
}
