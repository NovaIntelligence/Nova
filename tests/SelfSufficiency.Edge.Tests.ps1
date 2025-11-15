Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Self-Sufficiency Model Edge Cases' {
    BeforeAll {
        $global:TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("nova_ssm_edge_" + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
        New-Item -ItemType Directory -Force -Path $global:TempRoot | Out-Null
    }

    It 'Throws on missing mandatory parameters' {
        { pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' } | Should -Throw
    }

    It 'Throws when CloseRate is out of (0,1]' {
        $outDir = Join-Path $global:TempRoot 'bad_close_rate'
        { pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 200 -AvgDealValue 1000 -CloseRate 0 -MeetingsPerWeek 5 } | Should -Throw
        { pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 200 -AvgDealValue 1000 -CloseRate 1.5 -MeetingsPerWeek 5 } | Should -Throw
    }

    It 'Handles extreme values without crashing and computes non-negative outputs' {
        $outDir = Join-Path $global:TempRoot 'extreme'
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 1e9 -AvgDealValue 1e6 -CloseRate 0.01 -MeetingsPerWeek 50
        $report = Join-Path $outDir 'self_sufficiency_report.json'
        Test-Path $report | Should -BeTrue
        $js = Get-Content -Path $report -Raw | ConvertFrom-Json
        [int]$js.outputs.DealsToBreakEven     | Should -BeGreaterThan 0
        [int]$js.outputs.MeetingsToBreakEven  | Should -BeGreaterThan 0
        if ($js.outputs.WeeksToBreakEven) { [double]$js.outputs.WeeksToBreakEven | Should -BeGreaterThan 0 }
    }

    It 'Reads metrics from JSON and overrides inputs' {
        $outDir = Join-Path $global:TempRoot 'metrics_json'
        $metrics = Join-Path $global:TempRoot 'metrics.json'
        @{ InfraMonthlyCost = 123; AvgDealValue = 4567; CloseRate = 0.25; MeetingsPerWeek = 8 } | ConvertTo-Json | Set-Content -Path $metrics -Encoding UTF8
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -MetricsPath $metrics -InfraMonthlyCost 1 -AvgDealValue 1 -CloseRate 0.1 -MeetingsPerWeek 1
        $report = Join-Path $outDir 'self_sufficiency_report.json'
        $js = Get-Content -Path $report -Raw | ConvertFrom-Json
        [int]$js.inputs.InfraMonthlyCost | Should -Be 123
        [int]$js.inputs.AvgDealValue     | Should -Be 4567
        [double]$js.inputs.CloseRate     | Should -Be 0.25
        [int]$js.inputs.MeetingsPerWeek  | Should -Be 8
    }
}
