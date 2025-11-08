param([Parameter(Mandatory=$true)][string]$Id)
$ErrorActionPreference = 'Stop'
. "C:\Nova\tools\nova-ops\venv\Scripts\Activate.ps1"
$env:GOOGLE_CLOUD_PROJECT = 'bamboo-autumn-474404-e7'
python "C:\Nova\tools\nova-ops\approve_intent.py" ""
