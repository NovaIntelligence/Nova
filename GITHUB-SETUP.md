# GitHub Repository Setup Guide

## 🚀 Complete GitHub CI/CD Setup Process

This guide will walk you through setting up the Nova Bot repository on GitHub with full CI/CD integration.

## Step 1: Create GitHub Repository

1. **Go to GitHub.com** and sign in to your account
2. **Click "New repository"** or go to: https://github.com/new
3. **Repository settings**:
   ```
   Repository name: Nova
   Description: PowerShell-based autonomous bot framework with metrics, skills, and CI/CD
   Visibility: Public (or Private if preferred)
   ✅ Add README file: NO (we already have one)
   ✅ Add .gitignore: NO (we'll create a custom one)
   ✅ Choose a license: MIT License (recommended)
   ```
4. **Click "Create repository"**

## Step 2: Add Remote and Push Repository

```powershell
# Navigate to Nova directory
cd D:\Nova

# Add GitHub remote (replace YOUR_USERNAME with your actual GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/Nova.git

# Verify remote was added
git remote -v

# Add essential files first
git add .github/ modules/ tools/ tests/ README.md
git commit -m "Initial Nova Bot framework with CI/CD pipeline"

# Push to GitHub
git push -u origin master

# Add remaining files (optional - many are large/temporary)
# git add .
# git commit -m "Add complete project structure"  
# git push origin master
```

## Step 3: Update README Badge URLs

After creating the repository, update the README.md file with your actual GitHub username:

```powershell
# Open README.md and replace YOUR_USERNAME with your actual GitHub username in these lines:
# ![CI Status](https://github.com/YOUR_USERNAME/Nova/workflows/Nova%20Bot%20CI/CD%20Pipeline/badge.svg)
# [![Test Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen.svg)](https://github.com/YOUR_USERNAME/Nova/actions)

# Example for username "johndoe":
# ![CI Status](https://github.com/johndoe/Nova/workflows/Nova%20Bot%20CI/CD%20Pipeline/badge.svg)
# [![Test Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen.svg)](https://github.com/johndoe/Nova/actions)
```

## Step 4: Configure Branch Protection Rules

1. **Go to repository Settings** → **Branches**
2. **Click "Add rule"**
3. **Configure protection for `master` branch**:
   ```
   Branch name pattern: master
   
   ✅ Restrict pushes that create files larger than 100MB
   ✅ Require a pull request before merging
       ✅ Require approvals: 1
       ✅ Dismiss stale reviews when new commits are pushed
   ✅ Require status checks to pass before merging
       ✅ Require branches to be up to date before merging
       ✅ Status checks: "Test Nova Bot" (will appear after first CI run)
   ✅ Require conversation resolution before merging
   ✅ Include administrators
   ```

## Step 5: Set Up Notification Webhooks

### Option A: GitHub Actions Notifications
1. **Go to repository Settings** → **Webhooks**
2. **Click "Add webhook"**
3. **Configure webhook**:
   ```
   Payload URL: https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN/github
   Content type: application/json
   Secret: (optional but recommended)
   
   Events to send:
   ✅ Workflow runs
   ✅ Pull requests  
   ✅ Pushes
   ✅ Issues
   ```

### Option B: Email Notifications
GitHub automatically sends email notifications to repository watchers when:
- CI builds fail
- Pull requests are opened/merged
- Issues are created/closed

To enable:
1. **Go to repository main page**
2. **Click "Watch" → "All Activity"**
3. **Check your GitHub notification settings**

### Option C: Slack Integration
1. **Install GitHub app in Slack workspace**
2. **Configure channel notifications**:
   ```
   /github subscribe YOUR_USERNAME/Nova
   /github subscribe YOUR_USERNAME/Nova reviews comments branches commits:all
   ```

## Step 6: Test CI Pipeline

1. **Make a small change** to test the pipeline:
   ```powershell
   # Edit a file (like README.md)
   echo "`n<!-- Test CI trigger -->" >> README.md
   
   # Commit and push
   git add README.md
   git commit -m "Test CI pipeline trigger"
   git push origin master
   ```

2. **Check CI execution**:
   - Go to **Actions** tab in GitHub repository
   - You should see "Nova Bot CI/CD Pipeline" workflow running
   - Monitor the logs for any issues

3. **Verify artifacts**:
   - After CI completes, check the **Actions** tab
   - Click on the workflow run
   - Scroll down to see uploaded artifacts

## Step 7: Create Your First Pull Request

1. **Create a feature branch**:
   ```powershell
   git checkout -b feature/test-pr
   echo "# Test Feature" > test-feature.md
   git add test-feature.md  
   git commit -m "Add test feature for PR validation"
   git push origin feature/test-pr
   ```

2. **Open Pull Request** on GitHub:
   - Go to repository → **Pull requests** → **New pull request**
   - Select `feature/test-pr` → `master`
   - Add title: "Test CI integration with PR"
   - Create pull request

3. **Verify CI blocking**:
   - CI should run automatically on the PR
   - PR should show "All checks have passed" before allowing merge
   - Test that branch protection rules are working

## Expected CI Results

After successful setup, you should see:

### ✅ Successful CI Run
- **Preflight Checks**: All 10 checks passing
- **Test Suite**: 13/13 tests passing (100% pass rate)
- **Security Scan**: No credential issues detected
- **Artifacts**: Logs, coverage, and lessons uploaded

### 🔒 Branch Protection Working
- PRs cannot be merged without CI passing
- Status checks required before merge
- Administrators included in protection rules

### 📊 Monitoring Active
- CI status badges showing in README
- Webhook notifications firing correctly
- GitHub Actions dashboard populated

## Troubleshooting

### Common Issues

**Q: CI workflow not triggering?**
A: Check that `.github/workflows/nova-ci.yml` is in the master branch and properly formatted.

**Q: PowerShell execution errors in CI?**
A: Verify that all PowerShell scripts have proper execution policies and are syntactically correct.

**Q: Pester tests failing in CI but passing locally?**
A: Ensure you're testing with PowerShell 7 locally (`pwsh -File tools\Run-Tests.ps1`)

**Q: Artifacts not uploading?**
A: Check that artifact directories exist and have proper permissions.

### Getting Help

1. **Check workflow logs** in Actions tab for detailed error messages
2. **Run preflight locally**: `powershell -File tools\Preflight.ps1`
3. **Test runner locally**: `pwsh -File tools\Run-Tests.ps1`
4. **Verify file permissions** and directory structure

---

## Quick Setup Commands

For experienced users, here's the complete setup in one block:

```powershell
# Replace YOUR_USERNAME with your GitHub username
$username = "YOUR_USERNAME"

# Configure git and push
git remote add origin "https://github.com/$username/Nova.git"
git add .github/ modules/ tools/ tests/ README.md
git commit -m "Initial Nova Bot framework with CI/CD pipeline"
git push -u origin master

# Update README badges (manual edit required)
Write-Host "⚠️  Remember to update README.md badge URLs with username: $username"

# Create test PR
git checkout -b feature/test-ci
echo "# CI Test" > ci-test.md
git add ci-test.md
git commit -m "Test CI pipeline"
git push origin feature/test-ci

Write-Host "✅ Setup complete! Go to GitHub to:"
Write-Host "1. Configure branch protection rules"
Write-Host "2. Set up webhooks"  
Write-Host "3. Create test PR to verify CI"
```

This completes the full GitHub integration setup for Nova Bot! 🚀