# 🚀 One-Paste Pack v1 - Local Development Guide
<!-- Creators: Tyler McKendry & Nova -->

## Quick Start (One-Paste Commands)

### 🎯 Complete Local Setup
```powershell
# One-paste complete setup
git clone https://github.com/NovaIntelligence/Nova.git; cd Nova; powershell -ExecutionPolicy Bypass -File scripts\Setup-LocalDev.ps1
```

### 📊 Quality Scorecard Check
```powershell
# Run complete quality analysis
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1 -Detailed
```

### 🧪 Full Test Suite
```powershell
# Run all tests with coverage
powershell -ExecutionPolicy Bypass -File tests\Coverage-Report.ps1 -RunTests
```

### 🛡️ Security Audit
```powershell
# Complete security scan
powershell -ExecutionPolicy Bypass -File tools\Security-Audit.ps1 -Comprehensive
```

## 📋 Prerequisites

- **Windows 10/11** with PowerShell 5.1+
- **Git** (latest version)
- **Admin privileges** (for some setup operations)
- **Internet connection** (for dependency downloads)

## 🏗️ Local Development Setup

### Step 1: Repository Setup
```powershell
# Clone repository
git clone https://github.com/NovaIntelligence/Nova.git
cd Nova

# Verify structure
ls
```

### Step 2: Automated Setup
```powershell
# Run automated setup (creates all directories, installs dependencies)
powershell -ExecutionPolicy Bypass -File scripts\Setup-LocalDev.ps1 -Verbose
```

### Step 3: Verification
```powershell
# Run preflight checks
powershell -ExecutionPolicy Bypass -File tools\Preflight.ps1 -Verbose

# Check quality scorecard
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1
```

## 🧪 Testing

### Unit Tests
```powershell
# Run Pester tests
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester tests\ -OutputFormat NUnitXml -OutputFile results.xml
```

### Integration Tests
```powershell
# Full integration test suite
powershell -ExecutionPolicy Bypass -File tests\Integration.Tests.ps1 -Verbose
```

### Coverage Analysis
```powershell
# Generate coverage report
powershell -ExecutionPolicy Bypass -File tests\Coverage-Report.ps1 -HTML
```

## 🛡️ Security

### Security Audit
```powershell
# Run security scan
powershell -ExecutionPolicy Bypass -File tools\Security-Audit.ps1 -Output security-report.json
```

### Credential Management
- Use environment variables for secrets
- Never commit passwords or API keys
- Use Windows Credential Manager for local development

## 📊 Quality Scorecard

The Quality Scorecard evaluates 8 dimensions:

1. **Code Organization** (Target: 9/10)
2. **Documentation Coverage** (Target: 8/10)
3. **Test Coverage** (Target: 8/10)
4. **Security Practices** (Target: 9/10)
5. **Error Handling** (Target: 8/10)
6. **Performance Metrics** (Target: 7/10)
7. **Dependency Management** (Target: 8/10)
8. **CI/CD Integration** (Target: 9/10)

### Generate Scorecard
```powershell
# Basic scorecard
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1

# Detailed with recommendations
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1 -Detailed -OutputFormat JSON
```

## 🚀 Development Workflow

### 1. Feature Development
```powershell
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes
# ... develop ...

# Run quality checks before commit
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1 -Quick
```

### 2. Pre-Commit Validation
```powershell
# Full validation suite
powershell -ExecutionPolicy Bypass -File tools\Preflight.ps1 -Force
powershell -ExecutionPolicy Bypass -File tools\Security-Audit.ps1 -Quick
powershell -ExecutionPolicy Bypass -File tests\Coverage-Report.ps1 -RunTests
```

### 3. Commit and Push
```powershell
# Stage and commit
git add .
git commit -m "feat: your feature description"
git push origin feature/your-feature-name
```

## 🏃‍♂️ Running Nova Bot

### Local Development Mode
```powershell
# Start Nova Bot in development mode
cd bot
powershell -ExecutionPolicy Bypass -File nova-bot.ps1 -SmokeTest
```

### Dashboard
```powershell
# Start monitoring dashboard
powershell -ExecutionPolicy Bypass -File tools\Nova.Dashboard.ps1 -DaemonMode
# Access: http://localhost:8765
```

## 🔧 Troubleshooting

### Common Issues

#### PowerShell Execution Policy
```powershell
# If you get execution policy errors
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```

#### Module Import Errors
```powershell
# Install required modules
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
```

#### Permission Issues
```powershell
# Run PowerShell as Administrator for setup
# Right-click PowerShell -> "Run as Administrator"
```

#### Path Issues
```powershell
# Ensure you're in the correct directory
Get-Location
# Should show: D:\Nova (or your clone location)
```

### Getting Help

#### Verbose Output
Add `-Verbose` to any script for detailed logging:
```powershell
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1 -Verbose
```

#### Debug Mode
Add `-Debug` for maximum detail:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\Setup-LocalDev.ps1 -Debug
```

#### Log Files
Check logs in:
- `logs\*.log` - General application logs
- `data\metrics\*.jsonl` - Metrics data
- `ci-artifacts\*.xml` - Test results

## 🎯 Quick Reference

| Command | Purpose | Time |
|---------|---------|------|
| `Setup-LocalDev.ps1` | Complete environment setup | 2-3 min |
| `Quality-Scorecard.ps1` | Quality analysis | 30 sec |
| `Security-Audit.ps1` | Security scan | 45 sec |
| `Coverage-Report.ps1` | Test coverage | 1-2 min |
| `Preflight.ps1` | Pre-commit checks | 45 sec |
| `Integration.Tests.ps1` | Full integration tests | 2-5 min |

## 📚 Additional Resources

- [Security Policy](../docs/SECURITY.md)
- [Contributing Guidelines](../docs/CONTRIBUTING.md)
- [CI/CD Pipeline](../.github/workflows/nova-ci.yml)
- [Quality Scorecard Details](../tools/Quality-Scorecard.ps1)

## 🤝 Contributing

1. Read [CONTRIBUTING.md](../docs/CONTRIBUTING.md)
2. Follow the development workflow above
3. Ensure quality scorecard passes (≥7.0 overall)
4. Submit PR with completed checklist

---
*Last updated: November 8, 2024*  
*One-Paste Pack v1 - Making Nova development effortless*