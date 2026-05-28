# Claude Code + DeepSeek one-click install (Windows)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Claude Code + DeepSeek Install"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Claude Code + DeepSeek One-Click Install" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

function Test-Command($cmd) {
    try { Get-Command $cmd -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

# -- Admin check --

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [Notice] Please run as Administrator" -ForegroundColor Yellow
    Write-Host "  Right-click install.bat -> Run as Administrator" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# -- 1. API Key --

Write-Host "[1/9] Configure DeepSeek API Key" -ForegroundColor Yellow
Write-Host "(Register and create at platform.deepseek.com, then paste here)"
Write-Host ""
$apiKey = Read-Host "Enter DeepSeek API Key"
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Host "  [Error] API Key cannot be empty" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
$maskLen = [Math]::Min(8, $apiKey.Length)
$masked = $apiKey.Substring(0, $maskLen) + "****"
Write-Host "  API Key set: $masked" -ForegroundColor Green

# -- 2. License Key --

Write-Host ""
Write-Host "[2/9] Configure License Key" -ForegroundColor Yellow
Write-Host "(Obtained after purchase, looks like DS-CNDS-XXXX-XXXX)"
Write-Host ""
$licenseKey = Read-Host "Enter License Key"
if ([string]::IsNullOrWhiteSpace($licenseKey)) {
    Write-Host "  [Error] License Key cannot be empty" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  License Key set: $($licenseKey.Substring(0, [Math]::Min(8, $licenseKey.Length)))****"

# -- 3. Validate License (one machine one code) --

Write-Host ""
Write-Host "[3/9] Validating License..." -ForegroundColor Yellow

# Collect machine fingerprint
try {
    $machineId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography").MachineGuid
    if ([string]::IsNullOrWhiteSpace($machineId)) {
        throw "Empty MachineGuid"
    }
}
catch {
    Write-Host "  [Error] Cannot get machine identifier" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  Machine ID: $($machineId.Substring(0, [Math]::Min(16, $machineId.Length)))****"

# Query Supabase for license
$supabaseUrl = "https://onzyjumuidejsxzgzwit.supabase.co"
$supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uenlqdW11aWRlanN4emd6d2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTU0NDIsImV4cCI6MjA5NTEzMTQ0Mn0.DuFex3z0ID_BFNTpYkbd7jBeoFwmThXge98H0v63Xo8"

try {
    $queryUrl = "$supabaseUrl/rest/v1/licenses?license_key=eq.$([uri]::EscapeDataString($licenseKey))&select=*"
    $headers = @{
        "apikey" = $supabaseAnonKey
        "Authorization" = "Bearer $supabaseAnonKey"
    }
    $response = Invoke-RestMethod -Uri $queryUrl -Headers $headers -TimeoutSec 10

    if (-not $response -or $response.Count -eq 0) {
        Write-Host "  [Error] License Key not found" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    $lic = $response[0]

    # Check revoked
    if ($lic.status -eq "revoked") {
        Write-Host "  [Error] License Key has been revoked" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Check expired status
    if ($lic.status -eq "expired") {
        Write-Host "  [Error] License Key has expired" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Check expires_at date
    if ($lic.expires_at) {
        $expiresDate = [datetime]::Parse($lic.expires_at)
        if ($expiresDate -lt (Get-Date)) {
            Write-Host "  [Error] License Key has expired ($($expiresDate.ToString('yyyy-MM-dd')))" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    # Check machine binding (one machine one code)
    # "active" + no fingerprint → first activation, proceed
    # "activated" + fingerprint matches → re-install, OK
    # "activated" + fingerprint mismatch → reject
    $alreadyActivated = $false
    if ($lic.status -eq "activated") {
        if ($lic.fingerprint) {
            if ($lic.fingerprint -ne $machineId) {
                Write-Host "  [Error] License Key has been bound to another device" -ForegroundColor Red
                Read-Host "Press Enter to exit"
                exit 1
            }
            $alreadyActivated = $true
        }
    }

    Write-Host "  License validated" -ForegroundColor Green
}
catch {
    Write-Host "  [Error] License validation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Check network or contact support" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# -- 4. Update DB License --

Write-Host ""
Write-Host "[4/9] Activating License..." -ForegroundColor Yellow

$activatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

if ($alreadyActivated) {
    # Re-install on same machine: only update actived_at
    $updateBody = @{
        actived_at = $activatedAt
    } | ConvertTo-Json
}
else {
    # First activation: bind fingerprint + set status to activated
    $updateBody = @{
        fingerprint = $machineId
        actived_at = $activatedAt
        status = "activated"
    } | ConvertTo-Json
}

try {
    $patchUrl = "$supabaseUrl/rest/v1/licenses?license_key=eq.$([uri]::EscapeDataString($licenseKey))"
    $patchHeaders = @{
        "apikey" = $supabaseAnonKey
        "Authorization" = "Bearer $supabaseAnonKey"
        "Content-Type" = "application/json"
        "Prefer" = "return=minimal"
    }
    Invoke-RestMethod -Uri $patchUrl -Method PATCH -Headers $patchHeaders -Body $updateBody -TimeoutSec 10 | Out-Null
    Write-Host "  License activated" -ForegroundColor Green
}
catch {
    Write-Host "  [Warning] License activation record failed, continuing..." -ForegroundColor Yellow
}

# -- 5. Node.js --

Write-Host ""
Write-Host "[5/9] Checking Node.js..." -ForegroundColor Yellow

if (Test-Command "node") {
    $nodeVer = & node -v
    Write-Host "  Node.js installed: $nodeVer" -ForegroundColor Green
}
else {
    Write-Host "  Node.js not found, installing automatically..." -ForegroundColor Yellow

    $installed = $false

    $nodeUrl = "https://registry.npmmirror.com/-/binary/node/v20.18.1/node-v20.18.1-x64.msi"
    $msiPath = $env:TEMP + "\node-install.msi"
    Write-Host "  Downloading Node.js (mirror, ~30MB)..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $nodeUrl -OutFile $msiPath -TimeoutSec 120
        $msiArgs = "/i " + [char]34 + $msiPath + [char]34 + " /quiet /norestart"
        Start-Process msiexec.exe -ArgumentList $msiArgs -Wait
        Remove-Item $msiPath -Force
        $installed = $true
    }
    catch {
        Write-Host "  Mirror download failed, trying winget..." -ForegroundColor Yellow
        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
    }

    if (-not $installed -and (Test-Command "winget")) {
        try {
            winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
            $installed = $true
        }
        catch { }
    }

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = $machinePath + ";" + $userPath

    if (-not (Test-Command "node")) {
        Write-Host "  [Error] Node.js install failed: https://nodejs.org" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "  Node.js install done: $(node -v)" -ForegroundColor Green
}

# npm mirror check
try {
    $null = Invoke-WebRequest -Uri "https://registry.npmjs.org" -TimeoutSec 3 -UseBasicParsing
}
catch {
    Write-Host "  Network restricted, switching to npmmirror..." -ForegroundColor Yellow
    npm config set registry https://registry.npmmirror.com
}

# -- 6. Git --

Write-Host ""
Write-Host "[6/9] Checking Git..." -ForegroundColor Yellow

if (Test-Command "git") {
    $gitVer = & git --version
    Write-Host "  Git installed: $gitVer" -ForegroundColor Green
}
else {
    Write-Host "  Git not found, installing automatically..." -ForegroundColor Yellow

    $gitInstalled = $false

    $gitUrl = "https://registry.npmmirror.com/-/binary/git-for-windows/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
    $gitPath = $env:TEMP + "\git-install.exe"
    Write-Host "  Downloading Git (mirror, ~50MB)..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitPath -TimeoutSec 180
        Start-Process $gitPath -ArgumentList "/VERYSILENT /NORESTART" -Wait
        Remove-Item $gitPath -Force
        $gitInstalled = $true
    }
    catch {
        Write-Host "  Mirror download failed, trying winget..." -ForegroundColor Yellow
        Remove-Item $gitPath -Force -ErrorAction SilentlyContinue
    }

    if (-not $gitInstalled -and (Test-Command "winget")) {
        try {
            winget install Git.Git --silent --accept-package-agreements --accept-source-agreements
            $gitInstalled = $true
        }
        catch { }
    }

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = $machinePath + ";" + $userPath

    if (-not (Test-Command "git")) {
        Write-Host "  [Warning] Git install failed: https://git-scm.com" -ForegroundColor Yellow
        Write-Host "  Make sure to check 'Add to system PATH' when installing Git" -ForegroundColor Yellow
        Read-Host "Press Enter to continue (skip Git)"
    }
    else {
        Write-Host "  Git install done: $(git --version)" -ForegroundColor Green
    }
}

# -- 7. Claude Code --

Write-Host ""
Write-Host "[7/9] Installing Claude Code CLI..." -ForegroundColor Yellow

npm install -g @anthropic-ai/claude-code
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [Error] Claude Code install failed, check network" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  Claude Code install done" -ForegroundColor Green

# Allow PowerShell script execution (claude is a .ps1 file)
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "  PowerShell execution policy set" -ForegroundColor Green
}
catch {
    Write-Host "  [Warning] Cannot set execution policy, use cmd to run claude" -ForegroundColor Yellow
}

# -- 8. Config --

Write-Host ""
Write-Host "[8/9] Writing Claude Code config..." -ForegroundColor Yellow

$ccConfigDir = $env:USERPROFILE + "\.claude"
if (-not (Test-Path $ccConfigDir)) {
    New-Item -ItemType Directory -Path $ccConfigDir -Force | Out-Null
}

# Create .claude.json to skip first-run OAuth (MUST exist, or settings.json is ignored)
$claudeJsonPath = $env:USERPROFILE + "\.claude.json"
'{"hasCompletedOnboarding": true}' | Set-Content -Path $claudeJsonPath -Encoding ASCII
Write-Host ("  Created: " + $claudeJsonPath) -ForegroundColor Green

# Claude Code connects directly to DeepSeek, no proxy needed
$settingsObj = @{
    env = @{
        ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic"
        ANTHROPIC_API_KEY = $apiKey
        ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-v4-pro"
        ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-v4-pro"
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-v4-flash"
        ANTHROPIC_MODEL = "deepseek-v4-pro"
        API_TIMEOUT_MS = "600000"
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
    }
}
$settingsJson = $settingsObj | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText(($ccConfigDir + "\settings.json"), $settingsJson, [System.Text.UTF8Encoding]::new($false))

Write-Host ("  Config written: " + $ccConfigDir + "\settings.json") -ForegroundColor Green

# -- 9. Verify --

Write-Host ""
Write-Host "[9/9] Verifying installation..." -ForegroundColor Yellow

$testBody = '{"model":"deepseek-chat","max_tokens":10,"messages":[{"role":"user","content":"Reply OK"}]}'
try {
    $result = Invoke-RestMethod -Uri "https://api.deepseek.com/anthropic/v1/messages" `
        -Method POST -Body $testBody -ContentType "application/json" `
        -Headers @{"x-api-key"=$apiKey} -TimeoutSec 30
    Write-Host "  Connectivity test passed" -ForegroundColor Green
}
catch {
    Write-Host "  Connectivity test failed, check API Key" -ForegroundColor Yellow
    Write-Host "  Manual test: claude -p 'Reply OK'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Installation Complete!" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Usage:" -ForegroundColor White
Write-Host "    claude                      Start Claude Code" -ForegroundColor White
Write-Host ""
Read-Host "Press Enter to exit"
