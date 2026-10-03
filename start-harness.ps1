[CmdletBinding()]
param(
    [ValidateSet('Web', 'Desktop')][string]$Mode = 'Web',
    [string]$Config = '',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'config.local.json' }
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    throw 'Copy config.example.json to config.local.json and set your Harness path first.'
}
$settings = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$allowed = @('ProxyUrl', 'DesktopPath', 'DshPath', 'Workspace', 'WebPort')
foreach ($property in $settings.PSObject.Properties.Name) {
    if ($property -notin $allowed) { throw "Unknown configuration field: $property. Do not put credentials in this file." }
}
$proxy = $null
if (-not [Uri]::TryCreate([string]$settings.ProxyUrl, [UriKind]::Absolute, [ref]$proxy) -or
    $proxy.Scheme -ne 'http' -or $proxy.Host -notin @('127.0.0.1', 'localhost', '[::1]') -or
    $proxy.UserInfo -or $proxy.AbsolutePath -ne '/' -or $proxy.Query -or $proxy.Fragment) {
    throw 'ProxyUrl must be a local HTTP proxy, for example http://127.0.0.1:18888, without credentials.'
}
$workspace = [string]$settings.Workspace
if (-not $workspace -or -not (Test-Path -LiteralPath $workspace -PathType Container)) {
    throw 'Workspace must point to an existing directory for your own Harness work.'
}
$port = 3080
if ($null -ne $settings.WebPort) {
    if ([string]$settings.WebPort -notmatch '^\d+$') { throw 'WebPort must be an integer.' }
    $port = [int]$settings.WebPort
}
if ($port -lt 1024 -or $port -gt 65535) { throw 'WebPort must be between 1024 and 65535.' }

function Test-LocalPort([string]$Address, [int]$PortNumber) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Address, $PortNumber)
        if (-not $task.Wait(2000)) { return $false }
        return $client.Connected
    } catch { return $false } finally { $client.Dispose() }
}
if (-not (Test-LocalPort $proxy.DnsSafeHost $proxy.Port)) {
    throw 'EasyConnect HTTP proxy is unavailable. Start your Docker container, log in to campus VPN, and check the published HTTP port.'
}

if ($Mode -eq 'Desktop') {
    $target = [string]$settings.DesktopPath
    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Leaf) -or
        [IO.Path]::GetExtension($target) -ne '.exe') { throw 'Set DesktopPath to your installed DeepSeek Harness.exe.' }
    $target = (Resolve-Path -LiteralPath $target).Path
    $processName = [IO.Path]::GetFileNameWithoutExtension($target)
    if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
        throw 'Close Harness completely (including the tray) before starting it with the proxy.'
    }
} else {
    $target = [string]$settings.DshPath
    if (-not $target) {
        $command = Get-Command dsh.cmd, dsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $target = $command.Source }
    }
    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw 'Set DshPath to your installed dsh.cmd (use a CLI version compatible with your desktop app).'
    }
    $target = (Resolve-Path -LiteralPath $target).Path
    if (Test-LocalPort '127.0.0.1' $port) {
        throw 'The web port is already in use. Stop the existing server yourself or choose another WebPort.'
    }
}
if ($CheckOnly) {
    Write-Host "Ready: $Mode launcher and local proxy port. VPN login and model access have not been verified."
    return
}

# Only the current process and its child inherit these values. Restore on return.
$names = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy')
$saved = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    [Environment]::SetEnvironmentVariable('HTTP_PROXY', $proxy.AbsoluteUri.TrimEnd('/'), 'Process')
    [Environment]::SetEnvironmentVariable('HTTPS_PROXY', $proxy.AbsoluteUri.TrimEnd('/'), 'Process')
    [Environment]::SetEnvironmentVariable('NO_PROXY', 'localhost,127.0.0.1,::1', 'Process')
    Push-Location -LiteralPath $workspace
    try {
        if ($Mode -eq 'Desktop') {
            Start-Process -FilePath $target -WorkingDirectory (Split-Path -Parent $target) -WindowStyle Normal
        } else {
            # Harness opens its own authenticated browser URL. No token log is collected here.
            & $target web --port $port
            if ($LASTEXITCODE -ne 0) { throw 'Harness exited with an error. Review the message above locally.' }
        }
    } finally { Pop-Location }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    foreach ($name in $names) {
        if ($null -ne $saved[$name]) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}
