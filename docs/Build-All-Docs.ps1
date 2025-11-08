# Build-All-Docs.ps1 - Multi-Stack Documentation Pipeline Orchestrator
# Creators: Tyler McKendry & Nova
# Orchestrates PowerShell (PlatyPS), Python (Sphinx), and TypeScript (TypeDoc) documentation builds

[CmdletBinding()]
param(
    [string]$OutputPath = ".\site",
    [switch]$Force,
    [switch]$SkipPowerShell,
    [switch]$SkipPython,
    [switch]$SkipTypeScript,
    [switch]$Verbose,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize build tracking
$buildStart = Get-Date
$buildStats = @{
    PowerShell = @{ Success = $false; Duration = 0; Files = 0; Errors = @() }
    Python = @{ Success = $false; Duration = 0; Files = 0; Errors = @() }
    TypeScript = @{ Success = $false; Duration = 0; Files = 0; Errors = @() }
    Integration = @{ Success = $false; Duration = 0; Files = 0; Errors = @() }
}

# Logging function
function Write-BuildLog {
    param([string]$Message, [string]$Level = "INFO", [string]$Component = "BUILD")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Cyan" }
        "SUCCESS" { "Green" }
        "START" { "Magenta" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Component] [$Level] $Message" -ForegroundColor $color
}

Write-BuildLog "🚀 Starting Nova Bot Multi-Stack Documentation Build Pipeline" "START" "ORCHESTRATOR"
Write-BuildLog "Output directory: $OutputPath" "INFO" "ORCHESTRATOR"

try {
    # Clean output directory if requested
    if ($Clean -and (Test-Path $OutputPath)) {
        Write-BuildLog "🧹 Cleaning output directory..." "INFO" "ORCHESTRATOR"
        Remove-Item -Path $OutputPath -Recurse -Force
    }

    # Create main output directory structure
    $outputDir = New-Item -ItemType Directory -Path $OutputPath -Force
    $psOutputDir = New-Item -ItemType Directory -Path "$OutputPath\ps" -Force
    $pyOutputDir = New-Item -ItemType Directory -Path "$OutputPath\py" -Force
    $tsOutputDir = New-Item -ItemType Directory -Path "$OutputPath\ts" -Force
    $assetsDir = New-Item -ItemType Directory -Path "$OutputPath\assets" -Force

    Write-BuildLog "📁 Created output directory structure" "SUCCESS" "ORCHESTRATOR"

    # ============================================================================
    # PowerShell Documentation Build (PlatyPS)
    # ============================================================================
    if (-not $SkipPowerShell) {
        Write-BuildLog "📜 Building PowerShell documentation with PlatyPS..." "START" "POWERSHELL"
        $psStart = Get-Date
        
        try {
            # Check if PlatyPS build script exists
            $platyPSScript = ".\ps\Build-PlatyPS.ps1"
            if (-not (Test-Path $platyPSScript)) {
                throw "PowerShell build script not found: $platyPSScript"
            }

            # Execute PowerShell documentation build
            $psResult = & $platyPSScript -OutputPath $psOutputDir -Force:$Force -Verbose:$Verbose 2>&1
            
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
                # Count generated files
                $psFiles = Get-ChildItem -Path $psOutputDir -Recurse -File | Measure-Object | Select-Object -ExpandProperty Count
                $buildStats.PowerShell.Files = $psFiles
                $buildStats.PowerShell.Success = $true
                Write-BuildLog "✅ PowerShell documentation build completed ($psFiles files)" "SUCCESS" "POWERSHELL"
            } else {
                throw "PowerShell build failed with exit code: $LASTEXITCODE"
            }
        }
        catch {
            $buildStats.PowerShell.Errors += $_.Exception.Message
            Write-BuildLog "❌ PowerShell documentation build failed: $($_.Exception.Message)" "ERROR" "POWERSHELL"
        }
        finally {
            $buildStats.PowerShell.Duration = ((Get-Date) - $psStart).TotalSeconds
        }
    } else {
        Write-BuildLog "⏭️ Skipping PowerShell documentation build" "INFO" "POWERSHELL"
    }

    # ============================================================================
    # Python Documentation Build (Sphinx)
    # ============================================================================
    if (-not $SkipPython) {
        Write-BuildLog "🐍 Building Python documentation with Sphinx..." "START" "PYTHON"
        $pyStart = Get-Date
        
        try {
            # Check for Python and Sphinx
            $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonCmd) {
                $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
            }
            
            if (-not $pythonCmd) {
                throw "Python not found in PATH. Please install Python 3.8+ and Sphinx."
            }

            # Check for Sphinx installation
            $sphinxCheck = & $pythonCmd.Source -c "import sphinx; print('Sphinx version:', sphinx.__version__)" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildLog "Installing Sphinx and dependencies..." "INFO" "PYTHON"
                & $pythonCmd.Source -m pip install sphinx sphinx-rtd-theme myst-parser sphinx-copybutton sphinx-design
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install Sphinx dependencies"
                }
            }

            # Build Sphinx documentation
            Push-Location ".\py"
            try {
                Write-BuildLog "Running Sphinx build..." "INFO" "PYTHON"
                & $pythonCmd.Source -m sphinx -b html . $pyOutputDir -E -W --keep-going 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    # Count generated files
                    $pyFiles = Get-ChildItem -Path $pyOutputDir -Recurse -File | Measure-Object | Select-Object -ExpandProperty Count
                    $buildStats.Python.Files = $pyFiles
                    $buildStats.Python.Success = $true
                    Write-BuildLog "✅ Python documentation build completed ($pyFiles files)" "SUCCESS" "PYTHON"
                } else {
                    throw "Sphinx build failed with exit code: $LASTEXITCODE"
                }
            }
            finally {
                Pop-Location
            }
        }
        catch {
            $buildStats.Python.Errors += $_.Exception.Message
            Write-BuildLog "❌ Python documentation build failed: $($_.Exception.Message)" "ERROR" "PYTHON"
        }
        finally {
            $buildStats.Python.Duration = ((Get-Date) - $pyStart).TotalSeconds
        }
    } else {
        Write-BuildLog "⏭️ Skipping Python documentation build" "INFO" "PYTHON"
    }

    # ============================================================================
    # TypeScript Documentation Build (TypeDoc)
    # ============================================================================
    if (-not $SkipTypeScript) {
        Write-BuildLog "📘 Building TypeScript documentation with TypeDoc..." "START" "TYPESCRIPT"
        $tsStart = Get-Date
        
        try {
            # Check for Node.js and npm
            $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
            $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
            
            if (-not $nodeCmd -or -not $npmCmd) {
                throw "Node.js and npm not found in PATH. Please install Node.js 16+."
            }

            # Check for TypeScript/JavaScript files
            $tsFiles = Get-ChildItem -Path "..\.." -Include "*.ts", "*.js" -Recurse -File | 
                       Where-Object { $_.FullName -notmatch "(node_modules|dist|build|coverage|artifacts|\.git)" } |
                       Measure-Object | Select-Object -ExpandProperty Count

            if ($tsFiles -eq 0) {
                Write-BuildLog "⚠️ No TypeScript/JavaScript files found, creating placeholder documentation" "WARN" "TYPESCRIPT"
                
                # Create placeholder TypeScript documentation
                $placeholderContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nova Bot TypeScript Documentation</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; }
        .container { max-width: 800px; margin: 0 auto; }
        .notice { background: #f8f9fa; border: 1px solid #e9ecef; padding: 1rem; border-radius: 6px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔷 Nova Bot TypeScript Documentation</h1>
        <div class="notice">
            <h3>📋 Documentation Status</h3>
            <p><strong>Status:</strong> No TypeScript or JavaScript files found in the current workspace.</p>
            <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')</p>
        </div>
        <h2>📖 About</h2>
        <p>This documentation portal is automatically generated when TypeScript or JavaScript files are present in the Nova Bot workspace.</p>
        <h2>🔗 Other Documentation</h2>
        <ul>
            <li><a href="../ps/README.html">PowerShell Modules Documentation</a></li>
            <li><a href="../py/index.html">Python/Sphinx Documentation</a></li>
            <li><a href="../index.html">Main Documentation Portal</a></li>
        </ul>
    </div>
</body>
</html>
"@
                $placeholderContent | Out-File -FilePath "$tsOutputDir\index.html" -Encoding UTF8
                $buildStats.TypeScript.Files = 1
                $buildStats.TypeScript.Success = $true
            } else {
                Write-BuildLog "Found $tsFiles TypeScript/JavaScript files, proceeding with TypeDoc build..." "INFO" "TYPESCRIPT"

                # Check for TypeDoc installation
                $typedocCheck = & $npmCmd list -g typedoc 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-BuildLog "Installing TypeDoc globally..." "INFO" "TYPESCRIPT"
                    & $npmCmd install -g typedoc
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to install TypeDoc"
                    }
                }

                # Build TypeDoc documentation
                Push-Location ".\ts"
                try {
                    Write-BuildLog "Running TypeDoc build..." "INFO" "TYPESCRIPT"
                    & npx typedoc --options typedoc.json 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        # Count generated files
                        $generatedFiles = Get-ChildItem -Path $tsOutputDir -Recurse -File | Measure-Object | Select-Object -ExpandProperty Count
                        $buildStats.TypeScript.Files = $generatedFiles
                        $buildStats.TypeScript.Success = $true
                        Write-BuildLog "✅ TypeScript documentation build completed ($generatedFiles files)" "SUCCESS" "TYPESCRIPT"
                    } else {
                        throw "TypeDoc build failed with exit code: $LASTEXITCODE"
                    }
                }
                finally {
                    Pop-Location
                }
            }
        }
        catch {
            $buildStats.TypeScript.Errors += $_.Exception.Message
            Write-BuildLog "❌ TypeScript documentation build failed: $($_.Exception.Message)" "ERROR" "TYPESCRIPT"
        }
        finally {
            $buildStats.TypeScript.Duration = ((Get-Date) - $tsStart).TotalSeconds
        }
    } else {
        Write-BuildLog "⏭️ Skipping TypeScript documentation build" "INFO" "TYPESCRIPT"
    }

    # ============================================================================
    # Integration and Portal Creation
    # ============================================================================
    Write-BuildLog "🔗 Creating unified documentation portal..." "START" "INTEGRATION"
    $integStart = Get-Date
    
    try {
        # Create main documentation portal
        $portalContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nova Bot Documentation Portal</title>
    <link rel="stylesheet" href="assets/portal.css">
    <link rel="icon" type="image/x-icon" href="assets/favicon.ico">
</head>
<body>
    <div class="container">
        <header class="header">
            <div class="logo">
                <h1>🤖 Nova Bot</h1>
                <p class="tagline">Intelligent autonomous assistant built with PowerShell</p>
            </div>
            <div class="build-info">
                <span class="badge">Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')</span>
            </div>
        </header>

        <nav class="quick-nav">
            <a href="#docs" class="nav-link">📚 Documentation</a>
            <a href="#status" class="nav-link">📊 Build Status</a>
            <a href="#links" class="nav-link">🔗 Quick Links</a>
        </nav>

        <section id="docs" class="docs-grid">
            <div class="doc-card $(if($buildStats.PowerShell.Success){'success'}else{'error'})">
                <div class="doc-header">
                    <h3>⚡ PowerShell Modules</h3>
                    <span class="status-badge">$(if($buildStats.PowerShell.Success){'✅ Ready'}else{'❌ Failed'})</span>
                </div>
                <p>Auto-generated documentation for Nova Bot PowerShell modules using PlatyPS.</p>
                <div class="doc-stats">
                    <span>📁 $($buildStats.PowerShell.Files) files</span>
                    <span>⏱️ $([math]::Round($buildStats.PowerShell.Duration, 1))s</span>
                </div>
                <div class="doc-actions">
                    $(if($buildStats.PowerShell.Success){'<a href="ps/README.html" class="btn-primary">View Docs</a>'}else{'<span class="btn-disabled">Unavailable</span>'})
                </div>
            </div>

            <div class="doc-card $(if($buildStats.Python.Success){'success'}else{'error'})">
                <div class="doc-header">
                    <h3>🐍 Core Documentation</h3>
                    <span class="status-badge">$(if($buildStats.Python.Success){'✅ Ready'}else{'❌ Failed'})</span>
                </div>
                <p>Comprehensive user and developer documentation built with Sphinx and MyST.</p>
                <div class="doc-stats">
                    <span>📁 $($buildStats.Python.Files) files</span>
                    <span>⏱️ $([math]::Round($buildStats.Python.Duration, 1))s</span>
                </div>
                <div class="doc-actions">
                    $(if($buildStats.Python.Success){'<a href="py/index.html" class="btn-primary">View Docs</a>'}else{'<span class="btn-disabled">Unavailable</span>'})
                </div>
            </div>

            <div class="doc-card $(if($buildStats.TypeScript.Success){'success'}else{'error'})">
                <div class="doc-header">
                    <h3>🔷 TypeScript API</h3>
                    <span class="status-badge">$(if($buildStats.TypeScript.Success){'✅ Ready'}else{'❌ Failed'})</span>
                </div>
                <p>API documentation for TypeScript components and interfaces generated with TypeDoc.</p>
                <div class="doc-stats">
                    <span>📁 $($buildStats.TypeScript.Files) files</span>
                    <span>⏱️ $([math]::Round($buildStats.TypeScript.Duration, 1))s</span>
                </div>
                <div class="doc-actions">
                    $(if($buildStats.TypeScript.Success){'<a href="ts/index.html" class="btn-primary">View Docs</a>'}else{'<span class="btn-disabled">Unavailable</span>'})
                </div>
            </div>
        </section>

        <section id="status" class="build-status">
            <h2>📊 Build Status</h2>
            <div class="status-grid">
                <div class="status-item">
                    <h4>Overall Status</h4>
                    <span class="status-value $(if($buildStats.PowerShell.Success -or $buildStats.Python.Success -or $buildStats.TypeScript.Success){'success'}else{'error'})">
                        $(if($buildStats.PowerShell.Success -or $buildStats.Python.Success -or $buildStats.TypeScript.Success){'✅ Partial/Complete'}else{'❌ All Failed'})
                    </span>
                </div>
                <div class="status-item">
                    <h4>Total Duration</h4>
                    <span class="status-value">⏱️ $([math]::Round(((Get-Date) - $buildStart).TotalSeconds, 1))s</span>
                </div>
                <div class="status-item">
                    <h4>Total Files</h4>
                    <span class="status-value">📁 $($buildStats.PowerShell.Files + $buildStats.Python.Files + $buildStats.TypeScript.Files) files</span>
                </div>
            </div>
        </section>

        <section id="links" class="quick-links">
            <h2>🔗 Quick Links</h2>
            <div class="links-grid">
                <a href="https://github.com/NovaIntelligence/Nova" class="link-card">
                    <h4>🏠 GitHub Repository</h4>
                    <p>Source code, issues, and discussions</p>
                </a>
                <a href="https://github.com/NovaIntelligence/Nova/actions" class="link-card">
                    <h4>🔄 CI/CD Pipeline</h4>
                    <p>Build status and test results</p>
                </a>
                <a href="https://codecov.io/gh/NovaIntelligence/Nova" class="link-card">
                    <h4>📈 Code Coverage</h4>
                    <p>Test coverage reports</p>
                </a>
                <a href="https://github.com/NovaIntelligence/Nova/security" class="link-card">
                    <h4>🛡️ Security</h4>
                    <p>Security advisories and policies</p>
                </a>
            </div>
        </section>

        <footer class="footer">
            <p>&copy; $(Get-Date -Format 'yyyy') Nova Intelligence Team | Built with ❤️ using PowerShell, Python, and TypeScript</p>
        </footer>
    </div>

    <script src="assets/portal.js"></script>
</body>
</html>
"@

        # Write portal HTML
        $portalContent | Out-File -FilePath "$OutputPath\index.html" -Encoding UTF8

        # Create CSS for the portal
        $portalCSS = @"
/* Nova Bot Documentation Portal Styles */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', sans-serif;
    line-height: 1.6;
    color: #333;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
}

.header {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 12px;
    padding: 2rem;
    margin-bottom: 2rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
}

.logo h1 {
    font-size: 2.5rem;
    margin-bottom: 0.5rem;
    color: #2c3e50;
}

.tagline {
    color: #7f8c8d;
    font-size: 1.1rem;
}

.badge {
    background: #3498db;
    color: white;
    padding: 0.5rem 1rem;
    border-radius: 20px;
    font-size: 0.9rem;
    font-weight: 500;
}

.quick-nav {
    display: flex;
    gap: 1rem;
    margin-bottom: 2rem;
    justify-content: center;
}

.nav-link {
    background: rgba(255, 255, 255, 0.9);
    color: #2c3e50;
    padding: 0.75rem 1.5rem;
    border-radius: 25px;
    text-decoration: none;
    font-weight: 500;
    transition: all 0.3s ease;
}

.nav-link:hover {
    background: white;
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.docs-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
    gap: 2rem;
    margin-bottom: 3rem;
}

.doc-card {
    background: rgba(255, 255, 255, 0.95);
    border-radius: 12px;
    padding: 2rem;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
    transition: all 0.3s ease;
    border-left: 4px solid #ddd;
}

.doc-card:hover {
    transform: translateY(-4px);
    box-shadow: 0 12px 48px rgba(0, 0, 0, 0.15);
}

.doc-card.success {
    border-left-color: #27ae60;
}

.doc-card.error {
    border-left-color: #e74c3c;
}

.doc-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
}

.doc-header h3 {
    color: #2c3e50;
    font-size: 1.3rem;
}

.status-badge {
    font-size: 0.8rem;
    padding: 0.25rem 0.75rem;
    border-radius: 12px;
    font-weight: 600;
}

.doc-card.success .status-badge {
    background: #d5f4e6;
    color: #27ae60;
}

.doc-card.error .status-badge {
    background: #fdeaea;
    color: #e74c3c;
}

.doc-stats {
    display: flex;
    gap: 1rem;
    margin: 1rem 0;
    color: #7f8c8d;
    font-size: 0.9rem;
}

.doc-actions {
    margin-top: 1.5rem;
}

.btn-primary {
    background: #3498db;
    color: white;
    padding: 0.75rem 1.5rem;
    border-radius: 6px;
    text-decoration: none;
    font-weight: 500;
    transition: all 0.3s ease;
    display: inline-block;
}

.btn-primary:hover {
    background: #2980b9;
    transform: translateY(-1px);
}

.btn-disabled {
    background: #bdc3c7;
    color: #7f8c8d;
    padding: 0.75rem 1.5rem;
    border-radius: 6px;
    font-weight: 500;
    display: inline-block;
}

.build-status, .quick-links {
    background: rgba(255, 255, 255, 0.95);
    border-radius: 12px;
    padding: 2rem;
    margin-bottom: 2rem;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
}

.build-status h2, .quick-links h2 {
    color: #2c3e50;
    margin-bottom: 1.5rem;
    text-align: center;
}

.status-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1.5rem;
}

.status-item {
    text-align: center;
    padding: 1rem;
    background: #f8f9fa;
    border-radius: 8px;
}

.status-item h4 {
    color: #2c3e50;
    margin-bottom: 0.5rem;
}

.status-value {
    font-weight: 600;
    font-size: 1.1rem;
}

.status-value.success {
    color: #27ae60;
}

.status-value.error {
    color: #e74c3c;
}

.links-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1.5rem;
}

.link-card {
    background: #f8f9fa;
    border-radius: 8px;
    padding: 1.5rem;
    text-decoration: none;
    color: #2c3e50;
    transition: all 0.3s ease;
    border: 2px solid transparent;
}

.link-card:hover {
    background: white;
    border-color: #3498db;
    transform: translateY(-2px);
}

.link-card h4 {
    margin-bottom: 0.5rem;
    color: #2c3e50;
}

.link-card p {
    color: #7f8c8d;
    font-size: 0.9rem;
}

.footer {
    text-align: center;
    color: rgba(255, 255, 255, 0.8);
    margin-top: 3rem;
    padding-top: 2rem;
    border-top: 1px solid rgba(255, 255, 255, 0.2);
}

@media (max-width: 768px) {
    .container {
        padding: 1rem;
    }
    
    .header {
        flex-direction: column;
        text-align: center;
        gap: 1rem;
    }
    
    .docs-grid {
        grid-template-columns: 1fr;
    }
    
    .quick-nav {
        flex-wrap: wrap;
    }
}
"@

        $portalCSS | Out-File -FilePath "$assetsDir\portal.css" -Encoding UTF8

        # Create simple JavaScript for the portal
        $portalJS = @"
// Nova Bot Documentation Portal Scripts
document.addEventListener('DOMContentLoaded', function() {
    // Smooth scrolling for navigation links
    document.querySelectorAll('.nav-link').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });

    // Add loading animations
    const cards = document.querySelectorAll('.doc-card');
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    });

    cards.forEach(card => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(20px)';
        card.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(card);
    });

    // Show build timestamp
    console.log('Nova Bot Documentation Portal loaded at: ' + new Date().toISOString());
});
"@

        $portalJS | Out-File -FilePath "$assetsDir\portal.js" -Encoding UTF8

        # Count total integration files created
        $integrationFiles = Get-ChildItem -Path $OutputPath -Recurse -File | Measure-Object | Select-Object -ExpandProperty Count
        $buildStats.Integration.Files = $integrationFiles
        $buildStats.Integration.Success = $true
        $buildStats.Integration.Duration = ((Get-Date) - $integStart).TotalSeconds

        Write-BuildLog "✅ Documentation portal created successfully ($integrationFiles total files)" "SUCCESS" "INTEGRATION"
    }
    catch {
        $buildStats.Integration.Errors += $_.Exception.Message
        Write-BuildLog "❌ Integration failed: $($_.Exception.Message)" "ERROR" "INTEGRATION"
    }

    # ============================================================================
    # Build Summary and Reporting
    # ============================================================================
    $totalDuration = ((Get-Date) - $buildStart).TotalSeconds
    $successCount = ($buildStats.Values | Where-Object { $_.Success }).Count
    $totalStacks = 4 # PowerShell, Python, TypeScript, Integration

    Write-BuildLog "" "INFO" "SUMMARY"
    Write-BuildLog "📊 Multi-Stack Documentation Build Summary" "START" "SUMMARY"
    Write-BuildLog "⏱️  Total Duration: $([math]::Round($totalDuration, 1)) seconds" "INFO" "SUMMARY"
    Write-BuildLog "📁 Total Files Generated: $($buildStats.Values | Measure-Object -Property Files -Sum | Select-Object -ExpandProperty Sum)" "INFO" "SUMMARY"
    Write-BuildLog "✅ Successful Builds: $successCount/$totalStacks" "INFO" "SUMMARY"
    Write-BuildLog "" "INFO" "SUMMARY"

    # Individual stack results
    foreach ($stack in $buildStats.Keys) {
        $status = if ($buildStats[$stack].Success) { "✅ SUCCESS" } else { "❌ FAILED" }
        $duration = [math]::Round($buildStats[$stack].Duration, 1)
        $files = $buildStats[$stack].Files
        Write-BuildLog "$stack`: $status ($files files, ${duration}s)" "INFO" "SUMMARY"
        
        if ($buildStats[$stack].Errors.Count -gt 0) {
            foreach ($error in $buildStats[$stack].Errors) {
                Write-BuildLog "  Error: $error" "ERROR" "SUMMARY"
            }
        }
    }

    # Create build manifest
    $manifest = @{
        BuildDate = Get-Date -Format 'o'
        TotalDuration = $totalDuration
        SuccessfulBuilds = $successCount
        TotalBuilds = $totalStacks
        OutputPath = $outputDir.FullName
        BuildStats = $buildStats
        GitCommit = (git rev-parse HEAD 2>$null) -or "unknown"
        GitBranch = (git rev-parse --abbrev-ref HEAD 2>$null) -or "unknown"
    }

    $manifest | ConvertTo-Json -Depth 4 | Out-File -FilePath "$OutputPath\build-manifest.json" -Encoding UTF8

    Write-BuildLog "" "INFO" "SUMMARY"
    if ($successCount -eq $totalStacks) {
        Write-BuildLog "🎉 All documentation builds completed successfully!" "SUCCESS" "SUMMARY"
    } elseif ($successCount -gt 0) {
        Write-BuildLog "⚠️ Documentation build completed with partial success ($successCount/$totalStacks)" "WARN" "SUMMARY"
    } else {
        Write-BuildLog "💥 All documentation builds failed!" "ERROR" "SUMMARY"
        exit 1
    }

    Write-BuildLog "📖 Documentation portal available at: $OutputPath\index.html" "INFO" "SUMMARY"
    Write-BuildLog "🚀 Nova Bot Multi-Stack Documentation Pipeline Complete!" "SUCCESS" "ORCHESTRATOR"
}
catch {
    Write-BuildLog "💥 Fatal error in documentation build pipeline: $($_.Exception.Message)" "ERROR" "ORCHESTRATOR"
    Write-BuildLog "Stack trace: $($_.ScriptStackTrace)" "ERROR" "ORCHESTRATOR"
    exit 1
}