# Nova Bot

![CI Status](https://github.com/YOUR_USERNAME/Nova/workflows/Nova%20Bot%20CI/CD%20Pipeline/badge.svg)
[![Test Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen.svg)](https://github.com/YOUR_USERNAME/Nova/actions)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Pester](https://img.shields.io/badge/Pester-v5.7-green.svg)](https://pester.dev/)

A comprehensive PowerShell-based autonomous bot framework with advanced metrics collection, sandboxed action execution, and robust failure handling capabilities.

## 🚀 Features

### Core Systems
- **📊 Metrics Collection**: Real-time performance monitoring with Prometheus export
- **🔒 Skills & Actions**: Sandboxed execution system with approval workflows
- **⚡ Dashboard**: HTTP-based monitoring interface on `localhost:8765`
- **🧪 Testing Suite**: Comprehensive failure injection tests with 100% pass rate
- **🛡️ Security**: PathGuard protection and input validation

### Advanced Capabilities
- **Automated Learning**: Nightly learning loops with lesson archival
- **Failure Recovery**: Robust error handling and graceful degradation
- **Action Queue**: Secure action submission, review, and execution pipeline
- **CI/CD Integration**: GitHub Actions with PowerShell 7 and Pester v5

## 📋 Requirements

- **PowerShell 5.1+** (PowerShell 7 recommended for CI)
- **Pester v5+** for testing framework
- **Git** for version control
- **Windows** environment (primary target)

## 🛠️ Installation

1. **Clone the repository**:
   ```powershell
   git clone https://github.com/YOUR_USERNAME/Nova.git
   cd Nova
   ```

2. **Run preflight checks**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\Preflight.ps1
   ```

3. **Install dependencies** (if needed):
   ```powershell
   Install-Module -Name Pester -MinimumVersion 5.0 -Force
   ```

## 🏃‍♂️ Quick Start

### Start the Dashboard
```powershell
# Start dashboard in daemon mode
powershell -ExecutionPolicy Bypass -File tools\Nova.Dashboard.ps1 -DaemonMode
```

### Submit an Action
```powershell
# Import skills module
Import-Module .\modules\Nova.Skills.psm1

# Submit a filesystem action
Submit-Action -Type "filesystem" -Action "create_directory" -Path "D:\Nova\temp\test"
```

### Review Actions
```powershell
# Launch interactive approval interface
powershell -ExecutionPolicy Bypass -File tools\Approve-Actions.ps1
```

### Run Tests
```powershell
# Run comprehensive test suite
pwsh -File tools\Run-Tests.ps1

# Run specific test categories
Invoke-Pester -Path tests\*.Tests.ps1 -Tag "Critical"
```

## 📁 Project Structure

```
Nova/
├── .github/workflows/     # CI/CD pipeline configuration
├── modules/               # Core PowerShell modules
│   ├── Nova.Metrics.psm1  # Metrics collection system
│   └── Nova.Skills.psm1   # Action queue and skills management
├── tools/                 # Operational scripts
│   ├── Nova.Dashboard.ps1  # HTTP dashboard server
│   ├── Approve-Actions.ps1 # Action approval TUI
│   ├── Preflight.ps1      # Pre-CI validation checks
│   └── Run-Tests.ps1      # Test suite runner
├── tests/                 # Test suites
│   └── FailureInjection.Tests.ps1  # Comprehensive failure tests
├── data/                  # Runtime data
│   └── queue/             # Action queue storage
├── skills/                # Skill definitions
└── lessons/               # Learning archives
```

## 🔧 Configuration

### Environment Setup
Nova Bot automatically creates required directory structures on first run:
- `data/queue/inbox/` - Incoming action requests
- `data/queue/outbox/` - Processed actions
- `logs/` - System logs and audit trails
- `lessons/` - Learning data and archives

### Metrics Configuration
The metrics system runs automatically and provides:
- **Counters**: Increment-only metrics (actions processed, errors)
- **Gauges**: Current value metrics (queue size, memory usage)  
- **Histograms**: Distribution metrics (response times, sizes)
- **Daily Rotation**: Automatic log rotation and archival

## 🧪 Testing

Nova Bot includes comprehensive failure injection testing covering:

### Security Tests (`Critical`)
- PathGuard validation (blocks dangerous system paths)
- File name sanitization
- Input validation and escaping

### Resilience Tests  
- **API Integration**: Timeout handling, retry logic
- **Process Management**: Crash detection, restart throttling
- **Metrics System**: Malformed data recovery, atomic writes

### Test Execution
```powershell
# Run all tests with coverage
pwsh -File tools\Run-Tests.ps1

# Run security-critical tests only
Invoke-Pester -Path tests\*.Tests.ps1 -Tag "Critical"

# Run with detailed output
pwsh -File tools\Run-Tests.ps1 -Detailed
```

## 🚀 CI/CD Pipeline

The GitHub Actions pipeline (`nova-ci.yml`) provides:

### Automated Testing
- **PowerShell 7** runtime with **PowerShell 5.1** compatibility mode
- **Pester v5** test execution with failure detection
- **80% minimum pass rate** validation
- **Critical test failure** blocking (immediate CI failure)

### Artifact Collection
- **Logs**: System logs, error traces, debug output
- **Coverage**: Test coverage reports and metrics
- **Lessons**: Learning data and AI model artifacts
- **Retention**: 30 days for artifacts, 14 days for test results

### Security Scanning
- **Credential Detection**: Scans for hardcoded secrets/passwords
- **Pattern Matching**: Identifies potential security vulnerabilities
- **PR-based**: Runs on all pull requests for security review

## 📊 Monitoring

### Dashboard Access
- **URL**: `http://localhost:8765`
- **Endpoints**:
  - `/` - Main dashboard
  - `/metrics` - Prometheus metrics
  - `/health` - System health check
  - `/queue` - Action queue status

### Metrics Available
- System performance counters
- Action execution statistics  
- Error rates and failure patterns
- Queue depth and processing times
- Resource utilization metrics

## 🔐 Security

### PathGuard Protection
- Blocks writes to system directories (`C:\Windows`, `C:\Program Files`)
- Validates file paths and prevents directory traversal
- Sanitizes file names and removes dangerous characters

### Action Approval System
- All high-risk actions require manual approval
- Interactive TUI for reviewing queued actions
- Audit trail for all approved/denied actions
- Automatic timeout for stale approval requests

## 🤝 Contributing

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Run preflight checks**: `powershell -File tools\Preflight.ps1`
4. **Run tests**: `pwsh -File tools\Run-Tests.ps1`  
5. **Commit changes**: `git commit -m 'Add amazing feature'`
6. **Push to branch**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

### Development Guidelines
- All PowerShell code must pass `PSScriptAnalyzer` validation
- Maintain 80%+ test coverage for new features
- Include failure injection tests for critical components
- Update documentation for API changes
- Follow PowerShell best practices and naming conventions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **PowerShell Team** - For the excellent automation platform
- **Pester Project** - For the comprehensive testing framework  
- **GitHub Actions** - For reliable CI/CD infrastructure
- **Contributors** - For making Nova Bot better every day

---

**Nova Bot** - Autonomous PowerShell Framework  
Built with ❤️ by Tyler McKendry & Nova