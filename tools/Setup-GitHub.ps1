# Setup-GitHub.ps1 - Nova Bot GitHub Repository Setup Helper
# This script helps configure the GitHub repository and update URLs

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubUsername,
    
    [string]$RepositoryName = "Nova",
    
    [switch]$UpdateBadges,
    [switch]$AddRemote,
    [switch]$InitialPush
)

Write-Host "🚀 Nova Bot GitHub Setup Helper" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

$repoUrl = "https://github.com/$GitHubUsername/$RepositoryName.git"

if ($AddRemote) {
    Write-Host "📡 Adding GitHub remote..." -ForegroundColor Yellow
    
    # Check if remote already exists
    $existingRemote = git remote get-url origin 2>$null
    if ($existingRemote) {
        Write-Host "⚠️  Remote 'origin' already exists: $existingRemote" -ForegroundColor Yellow
        $confirm = Read-Host "Replace existing remote? (y/N)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            git remote remove origin
            git remote add origin $repoUrl
            Write-Host "✅ Remote updated to: $repoUrl" -ForegroundColor Green
        } else {
            Write-Host "❌ Remote not changed" -ForegroundColor Red
        }
    } else {
        git remote add origin $repoUrl
        Write-Host "✅ Remote added: $repoUrl" -ForegroundColor Green
    }
}

if ($UpdateBadges) {
    Write-Host "🏷️  Updating README badges..." -ForegroundColor Yellow
    
    $readmePath = "README.md"
    if (Test-Path $readmePath) {
        $content = Get-Content $readmePath -Raw
        $updatedContent = $content -replace "YOUR_USERNAME", $GitHubUsername
        
        if ($content -ne $updatedContent) {
            Set-Content -Path $readmePath -Value $updatedContent -Encoding UTF8
            Write-Host "✅ README badges updated with username: $GitHubUsername" -ForegroundColor Green
        } else {
            Write-Host "ℹ️  No badge updates needed" -ForegroundColor Blue
        }
    } else {
        Write-Host "❌ README.md not found" -ForegroundColor Red
    }
}

if ($InitialPush) {
    Write-Host "📤 Preparing initial push..." -ForegroundColor Yellow
    
    # Check git status
    $status = git status --porcelain
    if (-not $status) {
        Write-Host "ℹ️  No changes to commit" -ForegroundColor Blue
    } else {
        Write-Host "📋 Files to commit:" -ForegroundColor Blue
        git status --short
        
        $confirm = Read-Host "`nProceed with commit and push? (y/N)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            # Add essential CI/CD files
            git add .github/ modules/ tools/ tests/ README.md .gitignore GITHUB-SETUP.md
            
            git commit -m "Initial Nova Bot framework with CI/CD pipeline - Complete GitHub Actions pipeline with PowerShell 7 + Pester v5, comprehensive test suite, preflight validation, metrics collection, skills management, interactive dashboard, and setup guides"
            
            Write-Host "🚀 Pushing to GitHub..." -ForegroundColor Yellow
            git push -u origin master
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Successfully pushed to GitHub!" -ForegroundColor Green
                Write-Host "🌐 Repository URL: https://github.com/$GitHubUsername/$RepositoryName" -ForegroundColor Cyan
            } else {
                Write-Host "❌ Push failed. Check your GitHub credentials and repository access." -ForegroundColor Red
            }
        } else {
            Write-Host "❌ Push cancelled" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "1. 🌐 Visit: https://github.com/$GitHubUsername/$RepositoryName" -ForegroundColor White
Write-Host "2. ⚙️  Configure branch protection rules (Settings → Branches)" -ForegroundColor White  
Write-Host "3. 🔔 Set up webhooks for notifications (Settings → Webhooks)" -ForegroundColor White
Write-Host "4. 🧪 Create a test PR to verify CI pipeline" -ForegroundColor White
Write-Host "5. 📊 Monitor Actions tab for CI execution" -ForegroundColor White

Write-Host "`n🔧 Quick Setup Commands:" -ForegroundColor Yellow
Write-Host "# Complete setup in one command:" -ForegroundColor Gray
Write-Host "powershell -File tools\Setup-GitHub.ps1 -GitHubUsername '$GitHubUsername' -AddRemote -UpdateBadges -InitialPush" -ForegroundColor Gray
Write-Host "`n# Individual steps:" -ForegroundColor Gray
Write-Host "powershell -File tools\Setup-GitHub.ps1 -GitHubUsername '$GitHubUsername' -AddRemote" -ForegroundColor Gray
Write-Host "powershell -File tools\Setup-GitHub.ps1 -GitHubUsername '$GitHubUsername' -UpdateBadges" -ForegroundColor Gray
Write-Host "powershell -File tools\Setup-GitHub.ps1 -GitHubUsername '$GitHubUsername' -InitialPush" -ForegroundColor Gray