# Contributing to Nova Bot
<!-- Creators: Tyler McKendry & Nova -->

Welcome to the Nova Bot project! We're thrilled that you're interested in contributing. This guide will help you get started and ensure your contributions align with our project standards.

## 🚀 Quick Start

### 1. Initial Setup

```powershell
# Clone the repository
git clone https://github.com/NovaIntelligence/Nova.git
cd Nova

# Run one-click setup
powershell -ExecutionPolicy Bypass -File scripts\Setup-LocalDev.ps1

# Verify installation
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1
```

### 2. Development Workflow

```powershell
# Create feature branch
git checkout -b feature/your-feature-name

# Make your changes
# ... code, code, code ...

# Run quality checks
powershell -ExecutionPolicy Bypass -File tools\Quality-Scorecard.ps1 -Detailed
powershell -ExecutionPolicy Bypass -File tools\Security-Audit.ps1 -Comprehensive

# Run tests
powershell -ExecutionPolicy Bypass -File tests\Integration.Tests.ps1

# Commit with conventional format
git add .
git commit -m "feat: add awesome new feature"
git push origin feature/your-feature-name
```

## 📋 Contribution Types

We welcome various types of contributions:

- 🐛 **Bug Fixes**: Help us squash bugs and improve stability
- ✨ **New Features**: Add exciting capabilities to Nova Bot
- 📝 **Documentation**: Improve guides, examples, and explanations
- 🧪 **Tests**: Enhance test coverage and reliability
- 🎨 **UI/UX**: Improve user experience and interface design
- 🔧 **Tooling**: Enhance development tools and workflows
- 🛡️ **Security**: Strengthen security practices and implementations

## 🎯 Contribution Guidelines

### Code Standards

#### PowerShell Best Practices
- Use approved PowerShell verbs (`Get-`, `Set-`, `New-`, `Remove-`, etc.)
- Follow PascalCase for functions and variables
- Use proper parameter validation with `[Parameter()]` attributes
- Include comprehensive error handling with `try/catch/finally`
- Write self-documenting code with clear variable names

#### Code Style
```powershell
# ✅ Good - Clear, descriptive function
function Get-NovaConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Environment = 'production'
    )
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }
        
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        throw
    }
}

# ❌ Bad - Poor naming and error handling
function getcfg($p) {
    $c = gc $p | ConvertFrom-Json
    return $c
}
```

#### File Structure
```
Nova/
├── tools/              # Development and operational tools
│   ├── Quality-Scorecard.ps1
│   └── Security-Audit.ps1
├── scripts/            # Automation and setup scripts
│   └── Setup-LocalDev.ps1
├── tests/              # Test files and coverage reports
│   ├── Integration.Tests.ps1
│   └── Coverage-Report.ps1
├── docs/               # Documentation and guides
│   ├── One-Paste-Pack-README.md
│   └── SECURITY.md
└── .github/            # GitHub workflows and templates
    └── workflows/
        └── scorecard.yml
```

### Quality Requirements

#### Minimum Quality Standards
- **Overall Score**: 8.0/10 (Quality Scorecard)
- **Security Score**: 85/100 (Security Audit)
- **Test Coverage**: 70% (Function Coverage)
- **Documentation**: All public functions documented

#### Required Checks
All contributions must pass:
```powershell
# Quality assessment
tools\Quality-Scorecard.ps1 -Target 8.0

# Security validation
tools\Security-Audit.ps1 -MinScore 85

# Test coverage
tests\Coverage-Report.ps1 -MinCoverage 70

# Integration tests
tests\Integration.Tests.ps1
```

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

#### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `chore`: Maintenance tasks
- `ci`: CI/CD changes
- `security`: Security improvements

#### Examples
```bash
# Simple feature
git commit -m "feat: add user authentication module"

# Bug fix with scope
git commit -m "fix(api): resolve null reference in user service"

# Breaking change
git commit -m "feat!: change configuration format to JSON"

# Detailed commit
git commit -m "feat(dashboard): add real-time metrics display

- Add WebSocket connection for live updates
- Implement metric cards with auto-refresh
- Add error handling for connection failures

Closes #123"
```

## 🔍 Testing Guidelines

### Test Structure

Our test suite includes:
- **Unit Tests**: Individual function testing
- **Integration Tests**: Component interaction testing
- **Security Tests**: Vulnerability and compliance testing
- **Performance Tests**: Load and efficiency testing

### Writing Tests

```powershell
# Example Pester test
Describe "Get-NovaConfiguration Tests" {
    BeforeAll {
        # Setup test environment
        $testConfigPath = "TestDrive:\test-config.json"
        @{ Environment = "test"; ApiUrl = "https://api.test.com" } | 
            ConvertTo-Json | Set-Content $testConfigPath
    }
    
    Context "Valid Configuration File" {
        It "Should load configuration successfully" {
            $config = Get-NovaConfiguration -ConfigPath $testConfigPath
            $config.Environment | Should -Be "test"
            $config.ApiUrl | Should -Be "https://api.test.com"
        }
    }
    
    Context "Invalid Configuration File" {
        It "Should throw error for missing file" {
            { Get-NovaConfiguration -ConfigPath "NonExistent.json" } | 
                Should -Throw "*not found*"
        }
    }
}
```

### Test Coverage Requirements

- **New Features**: 80% minimum coverage
- **Bug Fixes**: Include regression tests
- **Refactoring**: Maintain existing coverage
- **Critical Components**: 90% coverage target

## 📚 Documentation Guidelines

### Required Documentation

#### Function Documentation
```powershell
<#
.SYNOPSIS
    Brief description of what the function does.

.DESCRIPTION
    Detailed description including use cases and behavior.

.PARAMETER ParameterName
    Description of what this parameter does.

.EXAMPLE
    Get-NovaConfiguration -ConfigPath "config.json"
    
    Loads configuration from the specified JSON file.

.EXAMPLE
    Get-NovaConfiguration -ConfigPath "config.json" -Environment "staging"
    
    Loads configuration for the staging environment.

.NOTES
    Author: [Your Name]
    Created: [Date]
    Last Modified: [Date]

.LINK
    https://github.com/NovaIntelligence/Nova/docs
#>
```

#### README Updates
When adding new features:
- Update main README.md with feature description
- Add usage examples
- Update installation instructions if needed
- Include troubleshooting information

### Documentation Standards
- Use clear, concise language
- Include practical examples
- Provide troubleshooting guidance
- Keep documentation current with code changes

## 🔄 Pull Request Process

### Before Submitting

1. **Branch Naming**: Use descriptive names
   ```bash
   feature/add-user-auth
   fix/api-timeout-issue
   docs/improve-setup-guide
   ```

2. **Quality Checks**: Ensure all checks pass
   ```powershell
   # Run comprehensive checks
   scripts\Setup-LocalDev.ps1 -ValidateOnly
   tools\Quality-Scorecard.ps1 -Detailed
   tools\Security-Audit.ps1 -Comprehensive
   tests\Integration.Tests.ps1
   ```

3. **Self-Review**: Review your own changes
   - Check for unused code
   - Verify error handling
   - Ensure consistent formatting
   - Validate all links and references

### PR Template

When creating a PR, include:

```markdown
## Description
Brief description of changes and their purpose.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Quality Checklist
- [ ] Quality score meets minimum requirements (8.0/10)
- [ ] Security audit passes (85/100)
- [ ] Test coverage adequate (70%+)
- [ ] All tests pass
- [ ] Documentation updated

## Testing
Describe the tests run to verify your changes.

## Screenshots
Include screenshots for UI changes.
```

### Review Process

1. **Automated Checks**: CI/CD pipeline runs automatically
2. **Maintainer Review**: Code review by project maintainers
3. **Community Feedback**: Open for community input
4. **Final Approval**: Merge approval from maintainers

## 🎖️ Recognition

### Contributor Recognition

We recognize contributors through:
- **Contributors File**: Listed in CONTRIBUTORS.md
- **Release Notes**: Featured in version releases
- **GitHub Badges**: Contributor badges on profile
- **Hall of Fame**: Featured contributors section

### Maintainer Path

Active contributors may be invited to become maintainers based on:
- Consistent high-quality contributions
- Community engagement and helpfulness
- Understanding of project goals and architecture
- Commitment to project values and standards

## 🤝 Community Guidelines

### Code of Conduct

We are committed to providing a welcoming and inclusive environment:
- Be respectful and considerate
- Focus on constructive feedback
- Help others learn and grow
- Celebrate diverse perspectives and experiences

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and general discussion
- **Pull Requests**: Code review and collaboration

### Getting Help

Need assistance? Here's how to get help:

1. **Documentation**: Check existing docs and guides
2. **Search Issues**: Look for similar questions or problems
3. **Create Issue**: Open a new issue with detailed information
4. **Community Discussion**: Start a discussion for general questions

## 📊 Project Metrics

We track project health through:
- **Quality Score**: Overall codebase quality
- **Security Rating**: Security posture assessment
- **Test Coverage**: Percentage of code tested
- **Issue Resolution Time**: Average time to resolve issues
- **Contributor Activity**: New and active contributors

Current Status:
- Quality Score: ![Quality Score](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/NovaIntelligence/Nova/main/.github/badges/quality-score.json)
- Security Score: ![Security Score](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/NovaIntelligence/Nova/main/.github/badges/security-score.json)
- Test Coverage: ![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/NovaIntelligence/Nova/main/.github/badges/coverage.json)

## 📞 Contact

### Maintainers
- **Tyler McKendry**: Project Lead & Architecture
- **Nova**: AI Assistant & Code Quality

### Project Resources
- **Repository**: https://github.com/NovaIntelligence/Nova
- **Documentation**: https://github.com/NovaIntelligence/Nova/docs
- **Issues**: https://github.com/NovaIntelligence/Nova/issues
- **Discussions**: https://github.com/NovaIntelligence/Nova/discussions

---

Thank you for contributing to Nova Bot! Together, we're building something amazing. 🚀

*Last updated: November 8, 2024*  
*Guide version: 1.0*