# MailKit Library Directory

This directory is for optional MailKit and MimeKit DLLs to enable modern SMTP functionality.

## Why MailKit?

Microsoft has marked `System.Net.Mail.SmtpClient` as obsolete and recommends using MailKit instead. MailKit is:
- Actively maintained
- More secure with modern authentication methods
- Better standards compliance
- More reliable error handling

## Setup Instructions

To enable MailKit support in the Outbound-Deal-Machine script:

### Option 1: PowerShell Package Management (Recommended)

```powershell
# Install MailKit via NuGet
Install-Package MailKit -Source nuget.org -Scope CurrentUser -SkipDependencies -Force

# Find the installation path
$package = Get-Package MailKit
$packagePath = Split-Path $package.Source

# Copy DLLs to this directory
Copy-Item "$packagePath/lib/net6.0/MailKit.dll" -Destination ./
Copy-Item "$packagePath/lib/net6.0/MimeKit.dll" -Destination ./

# Also need to copy dependencies
Install-Package BouncyCastle.Cryptography -Source nuget.org -Scope CurrentUser -Force
$bcPackage = Get-Package BouncyCastle.Cryptography
$bcPath = Split-Path $bcPackage.Source
Copy-Item "$bcPath/lib/net6.0/BouncyCastle.Cryptography.dll" -Destination ./
```

### Option 2: Manual Download

1. Download the latest MailKit NuGet package from https://www.nuget.org/packages/MailKit
2. Download the latest MimeKit NuGet package from https://www.nuget.org/packages/MimeKit
3. Download the latest BouncyCastle.Cryptography package from https://www.nuget.org/packages/BouncyCastle.Cryptography
4. Extract the `.nupkg` files (they are zip files)
5. Copy the following DLLs to this directory:
   - `MailKit.dll` (from `lib/net6.0/` or appropriate framework folder)
   - `MimeKit.dll` (from `lib/net6.0/` or appropriate framework folder)
   - `BouncyCastle.Cryptography.dll` (from `lib/net6.0/` or appropriate framework folder)

### Verification

After setup, run the Outbound-Deal-Machine script. It will automatically detect and use MailKit if the DLLs are present. Check the logs for confirmation.

## Fallback Behavior

If MailKit is not available, the script will automatically fall back to using `System.Net.Mail.SmtpClient`. While this is marked obsolete, it still works for basic SMTP operations. However, you may see compiler warnings, and it lacks some modern security features.
