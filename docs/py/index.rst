Nova Bot Documentation
=======================

Welcome to **Nova Bot**, an intelligent autonomous assistant built with PowerShell.

Nova Bot is a comprehensive framework that provides advanced metrics collection, sandboxed action execution, and robust failure handling capabilities.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   overview
   getting-started
   modules/index
   api/index
   deployment
   security
   troubleshooting
   contributing

Features
--------

Core Systems
~~~~~~~~~~~~

* **📊 Metrics Collection**: Real-time performance monitoring with Prometheus export
* **🔒 Skills & Actions**: Sandboxed execution system with approval workflows  
* **⚡ Dashboard**: HTTP-based monitoring interface on ``localhost:8765``
* **🧪 Testing Suite**: Comprehensive failure injection tests with 100% pass rate
* **🛡️ Security**: PathGuard protection and input validation

Advanced Capabilities
~~~~~~~~~~~~~~~~~~~~~

* **Automated Learning**: Nightly learning loops with lesson archival
* **Failure Recovery**: Robust error handling and graceful degradation
* **Action Queue**: Secure action submission, review, and execution pipeline
* **CI/CD Integration**: GitHub Actions with PowerShell 7 and Pester v5

Quick Start
-----------

Installation
~~~~~~~~~~~~

1. **Clone the repository**:

   .. code-block:: powershell

      git clone https://github.com/NovaIntelligence/Nova.git
      cd Nova

2. **Run preflight checks**:

   .. code-block:: powershell

      powershell -ExecutionPolicy Bypass -File tools\Preflight.ps1

3. **Start Nova Bot**:

   .. code-block:: powershell

      .\bot\nova-bot.ps1 --health

Basic Usage
~~~~~~~~~~~

**Health Check**

.. code-block:: powershell

   # Basic health check
   .\bot\nova-bot.ps1 --health

   # Detailed health check with metrics
   .\bot\nova-bot.ps1 --health --metrics --verbose

**Dashboard Access**

.. code-block:: powershell

   # Start the monitoring dashboard
   .\bot\nova-bot.ps1 --dashboard

   # Access via browser: http://localhost:8765

**Metrics Collection**

.. code-block:: powershell

   # Enable Prometheus metrics export
   .\bot\nova-bot.ps1 --prometheus --metrics-port 9090

   # View metrics: http://localhost:9090/metrics

Architecture
------------

Nova Bot is built on a modular architecture with the following core components:

.. mermaid::

   graph TB
       A[Nova Bot Core] --> B[Metrics System]
       A --> C[Skills Framework] 
       A --> D[State Machine]
       A --> E[Dashboard]
       
       B --> B1[Counters]
       B --> B2[Gauges] 
       B --> B3[Histograms]
       B --> B4[Prometheus Export]
       
       C --> C1[Action Queue]
       C --> C2[Approval Workflow]
       C --> C3[Sandboxed Execution]
       C --> C4[Skill Modules]
       
       D --> D1[State Transitions]
       D --> D2[Event Handling]
       D --> D3[Persistence]
       
       E --> E1[HTTP Server]
       E --> E2[Real-time Monitoring]
       E --> E3[Control Interface]

Requirements
------------

System Requirements
~~~~~~~~~~~~~~~~~~~

* **PowerShell 5.1+** (PowerShell 7 recommended for CI)
* **Pester v5+** for testing framework
* **Git** for version control
* **Windows** environment (primary target)

Optional Dependencies
~~~~~~~~~~~~~~~~~~~~

* **Python 3.8+** for Sphinx documentation
* **Node.js 16+** for TypeScript documentation
* **Docker** for containerized deployment

Module Overview
---------------

Core Modules
~~~~~~~~~~~~

* **Nova.Metrics** - Comprehensive metrics collection and export
* **Nova.StateMachine** - Deterministic state management and transitions
* **Nova.Skills** - Extensible action and workflow execution framework

Utility Modules
~~~~~~~~~~~~~~~

* **Nova.Dashboard** - Real-time monitoring and control interface
* **Nova.Security** - Security scanning and compliance checking
* **Nova.Testing** - Quality assurance and testing utilities

Development
-----------

Testing
~~~~~~~

Nova Bot includes comprehensive test suites built with Pester v5:

.. code-block:: powershell

   # Run all unit tests
   Invoke-Pester -Path "tests\Unit\*.Tests.ps1" -Output Detailed

   # Run with coverage reporting
   Invoke-Pester -Path "tests\Unit\*.Tests.ps1" -CodeCoverage "modules\*.ps1"

   # Run E2E smoke tests
   Invoke-Pester -Path "tests\E2E\Bot.Smoke.Tests.ps1"

Quality Assurance
~~~~~~~~~~~~~~~~~

.. code-block:: powershell

   # Run quality scorecard
   .\tools\Quality-Scorecard.ps1 -Verbose

   # Security audit
   .\tools\Security-Audit.ps1 -FullScan

   # Generate coverage report
   .\tests\Coverage-Report.ps1 -OutputFormat HTML

Contributing
------------

Please read our `Contributing Guide <contributing.html>`_ for details on our code of conduct and the process for submitting pull requests.

License
-------

This project is licensed under the MIT License - see the LICENSE file for details.

Support
-------

* **Documentation**: https://NovaIntelligence.github.io/Nova
* **Issues**: https://github.com/NovaIntelligence/Nova/issues
* **Discussions**: https://github.com/NovaIntelligence/Nova/discussions

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`