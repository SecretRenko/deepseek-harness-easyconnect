$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('harness-proxy-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Start()
$proxyPort = $listener.LocalEndpoint.Port
$webSocket = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$webSocket.Start()
$webPort = $webSocket.LocalEndpoint.Port
$webSocket.Stop()
$configPath = Join-Path $temporary 'config.local.json'
$fakeDsh = Join-Path $temporary 'dsh.cmd'
$mock = Join-Path $temporary 'capture.ps1'
$capture = Join-Path $temporary 'capture.json'
$oldProxy = [Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process')

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Expect-Failure([scriptblock]$Action, [string]$Expected) {
    $failed = $false
    try { & $Action } catch {
        $failed = $true
        Assert ($_.Exception.Message -like "*$Expected*") 'Unexpected rejection reason'
    }
    Assert $failed "Expected rejection: $Expected"
}
function Save-Settings {
    $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
}
try {
    @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture.ps1" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath $fakeDsh -Encoding ASCII
    @'
@{
    Http = $env:HTTP_PROXY
    Https = $env:HTTPS_PROXY
    All = $env:ALL_PROXY
    NoProxy = $env:NO_PROXY
    Arguments = @($args)
    Directory = (Get-Location).Path
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'capture.json') -Encoding UTF8
'@ | Set-Content -LiteralPath $mock -Encoding UTF8
    $settings = [ordered]@{
        ProxyUrl = "http://127.0.0.1:$proxyPort"
        DesktopPath = ''
        DshPath = $fakeDsh
        Workspace = $temporary
        WebPort = $webPort
    }
    Save-Settings
    $env:HTTP_PROXY = 'http://127.0.0.1:1'
    & (Join-Path $root 'start-harness.ps1') -Config $configPath -CheckOnly
    Assert (-not (Test-Path -LiteralPath $capture)) 'CheckOnly launched a child'
    & (Join-Path $root 'start-harness.ps1') -Config $configPath
    $observed = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
    Assert ($observed.Http -eq $settings.ProxyUrl) 'Child HTTP proxy was not inherited'
    Assert ($observed.Https -eq $settings.ProxyUrl) 'Child HTTPS proxy was not inherited'
    Assert (-not $observed.All) 'Inherited ALL_PROXY was not cleared'
    Assert ($observed.NoProxy -eq 'localhost,127.0.0.1,::1') 'Local bypass mismatch'
    Assert (($observed.Arguments -join ' ') -eq "web --port $webPort") 'Web CLI arguments mismatch'
    Assert ($observed.Directory -eq $temporary) 'Workspace mismatch'
    Assert ($env:HTTP_PROXY -eq 'http://127.0.0.1:1') 'Parent environment was not restored'
    # Mock only process creation; exercise desktop validation and child environment.
    $desktopStub = Join-Path $temporary ('harness-test-' + [Guid]::NewGuid().ToString('N') + '.exe')
    Set-Content -LiteralPath $desktopStub -Value 'test executable placeholder'
    $settings.DesktopPath = $desktopStub
    Save-Settings
    function Start-Process {
        param($FilePath, $WorkingDirectory, $WindowStyle)
        @{
            Http = $env:HTTP_PROXY
            Https = $env:HTTPS_PROXY
            File = $FilePath
            Directory = $WorkingDirectory
            Style = $WindowStyle
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $temporary 'desktop.json')
    }
    try {
        & (Join-Path $root 'start-harness.ps1') -Config $configPath -Mode Desktop
        $desktop = Get-Content (Join-Path $temporary 'desktop.json') -Raw | ConvertFrom-Json
        Assert ($desktop.Http -eq $settings.ProxyUrl -and $desktop.Https -eq $settings.ProxyUrl) 'Desktop proxy mismatch'
        Assert ($desktop.File -eq $desktopStub -and $desktop.Style -eq 'Normal') 'Desktop launch mismatch'
        Assert ($env:HTTP_PROXY -eq 'http://127.0.0.1:1') 'Desktop parent environment restoration failed'
    } finally { Remove-Item Function:\Start-Process }
    $settings.ProxyUrl = 'socks5://127.0.0.1:1080'
    Save-Settings
    Expect-Failure { & (Join-Path $root 'start-harness.ps1') -Config $configPath } 'local HTTP proxy'
    $settings.ProxyUrl = 'http://192.0.2.1:8888'
    Save-Settings
    Expect-Failure { & (Join-Path $root 'start-harness.ps1') -Config $configPath } 'local HTTP proxy'
    $settings.ProxyUrl = "http://127.0.0.1:$proxyPort"
    $settings['SecretField'] = 'test-placeholder'
    Save-Settings
    Expect-Failure { & (Join-Path $root 'start-harness.ps1') -Config $configPath } 'Unknown configuration field'
    $settings.Remove('SecretField')
    $busySocket = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $webPort)
    $busySocket.Start()
    try {
        Save-Settings
        Expect-Failure { & (Join-Path $root 'start-harness.ps1') -Config $configPath } 'already in use'
    } finally { $busySocket.Stop() }
    $listener.Stop()
    Expect-Failure { & (Join-Path $root 'start-harness.ps1') -Config $configPath } 'proxy is unavailable'
    Write-Host 'PASS: web child proxy inheritance, mocked desktop launch, parent restoration, local bypass, workspace, check-only and invalid/unavailable/occupied port rejection.'
} finally {
    $listener.Stop()
    [Environment]::SetEnvironmentVariable('HTTP_PROXY', $oldProxy, 'Process')
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
