Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Self-Sufficiency-Model Edge Cases' {
    BeforeAll {
        $global:TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("nova_ssm_edge_" + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
        New-Item -ItemType Directory -Force -Path $global:TempRoot | Out-Null
    }

    It 'Errors when CloseRate <= 0' {
        $outDir = Join-Path $global:TempRoot 'out_cr0'
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 100 -AvgDealValue 1000 -CloseRate 0 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0

        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 100 -AvgDealValue 1000 -CloseRate -0.1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'Errors when CloseRate > 1' {
        $outDir = Join-Path $global:TempRoot 'out_crgt1'
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 100 -AvgDealValue 1000 -CloseRate 1.1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'Gracefully handles InfraMonthlyCost = 0 (no deals needed)' {
        $outDir = Join-Path $global:TempRoot 'out_zero_infra'
        if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir -InfraMonthlyCost 0 -AvgDealValue 1000 -CloseRate 0.25 | Out-Null
        $report = Get-Content -Path (Join-Path $outDir 'self_sufficiency_report.json') -Raw | ConvertFrom-Json
        [int]$report.outputs.DealsToBreakEven | Should -Be 0
        [int]$report.outputs.MeetingsToBreakEven | Should -Be 0
    }

    It 'WeeksToBreakEven is null when MeetingsPerWeek is not provided or 0' {
        $outDir1 = Join-Path $global:TempRoot 'out_noweeks'
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir1 -InfraMonthlyCost 200 -AvgDealValue 1000 -CloseRate 0.25 | Out-Null
        $report1 = Get-Content -Path (Join-Path $outDir1 'self_sufficiency_report.json') -Raw | ConvertFrom-Json
        $report1.outputs.WeeksToBreakEven | Should -BeNullOrEmpty

        $outDir2 = Join-Path $global:TempRoot 'out_weeks0'
        pwsh -NoLogo -NoProfile -File 'tools/skills/Self-Sufficiency-Model.ps1' -OutDir $outDir2 -InfraMonthlyCost 200 -AvgDealValue 1000 -CloseRate 0.25 -MeetingsPerWeek 0 | Out-Null
        $report2 = Get-Content -Path (Join-Path $outDir2 'self_sufficiency_report.json') -Raw | ConvertFrom-Json
        $report2.outputs.WeeksToBreakEven | Should -BeNullOrEmpty
    }
}
