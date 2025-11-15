[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $OffersCsv = "samples/skills/sample-offers.csv",
    [Parameter(Mandatory = $false)] [string] $TemplatePath = "tools/skills/templates/sales-page.md",
    [Parameter(Mandatory = $false)] [string] $OutDir,
    [Parameter(Mandatory = $false)] [int] $MaxOffers = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-OutputDir {
    param([string]$Base)
    if (-not $Base) { $Base = Join-Path -Path $PWD -ChildPath ("nova_offers_out_" + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    if (-not (Test-Path $Base)) { New-Item -Path $Base -ItemType Directory | Out-Null }
    return (Resolve-Path $Base).Path
}

function Load-Template {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Template not found at $Path" }
    return Get-Content -Path $Path -Raw
}

function Parse-OffersCsv {
    param([string]$CsvPath)
    if (-not (Test-Path $CsvPath)) { throw "Offers CSV not found at $CsvPath" }
    $rows = Import-Csv -Path $CsvPath
    return $rows
}

function Apply-Template {
    param(
        [string]$Template,
        [hashtable]$Map
    )
    $result = $Template
    foreach ($k in $Map.Keys) {
        $result = $result -replace [regex]::Escape("{{${k}}}"), [string]$Map[$k]
    }
    return $result
}

function New-AdVariants {
    param([string]$Headline, [string]$Audience)
    $variants = @(
        @{ platform = 'LinkedIn'; headline = $Headline; hook = "${Audience}: Cut time-to-value in weeks, not months."; cta = 'Book a demo'; characterCount = 220 },
        @{ platform = 'Facebook'; headline = $Headline; hook = "Proof-first offer: pay only when milestones are hit."; cta = 'Get the playbook'; characterCount = 120 },
        @{ platform = 'X'; headline = $Headline; hook = "Ops pain → recurring cashflow. Ship outcomes, not tasks."; cta = 'See how'; characterCount = 120 }
    )
    return $variants
}

try {
    $outPath = New-OutputDir -Base $OutDir
    $template = Load-Template -Path $TemplatePath
    $offers = Parse-OffersCsv -CsvPath $OffersCsv
    $count = 0
    $summary = @()

    foreach ($o in $offers) {
        if ($count -ge $MaxOffers) { break }
        # Expected columns: OfferName, Audience, Pain, Promise, Proof, Price, CTA
        $map = @{
            name    = $o.OfferName
            audience= $o.Audience
            pain    = $o.Pain
            promise = $o.Promise
            proof   = $o.Proof
            price   = $o.Price
            cta     = $o.CTA
            today   = (Get-Date).ToString('yyyy-MM-dd')
        }

        $page = Apply-Template -Template $template -Map $map
        $slug = ($o.OfferName -replace "[^a-zA-Z0-9_-]", "-").ToLower()
        $pageFile = Join-Path $outPath "$slug-sales-page.md"
        Set-Content -Path $pageFile -Value $page -Encoding UTF8

        $ads = New-AdVariants -Headline $o.Promise -Audience $o.Audience
        $adsFile = Join-Path $outPath "$slug-ad-variants.json"
        $ads | ConvertTo-Json -Depth 6 | Set-Content -Path $adsFile -Encoding UTF8

        $summary += [pscustomobject]@{
            offer   = $o.OfferName
            audience= $o.Audience
            page    = $pageFile
            ads     = $adsFile
        }
        $count++
    }

    $summaryObj = [pscustomobject]@{
        generated = $count
        outDir    = $outPath
        runAt     = (Get-Date).ToString('s')
        items     = $summary
    }
    $summaryPath = Join-Path $outPath 'offer_architect_summary.json'
    $summaryObj | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host "Offer Architect completed. Outputs in: $outPath"
}
catch {
    Write-Error $_
    exit 1
}
