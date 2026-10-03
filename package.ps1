[CmdletBinding()]
param([string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
$files = @(
    '.gitignore', 'LICENSE', 'README.md', 'config.example.json',
    'start-harness.ps1', 'start-web.bat', 'start-desktop.bat',
    'package.ps1', 'tests/test-launcher.ps1'
)
# Fixed allowlist: never enumerate/copy the working directory recursively.
$patterns = @(
    'sk-[A-Za-z0-9_-]{16,}',
    '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    '(?i)(?:api[_-]?key|password|passwd|authorization)\s*[=:]\s*["''][^"'']{8,}["'']',
    '(?i)https?://[^\s/]+:[^\s/@]+@',
    '(?i)Bearer\s+[A-Za-z0-9_-]{20,}',
    '(?i)[A-Z]:[\\/]Users[\\/][^\\/\s"'']+'
)
foreach ($relative in $files) {
    $path = Join-Path $PSScriptRoot $relative
    $item = Get-Item -LiteralPath $path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked files cannot be packaged: $relative" }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    # The scanner itself contains pattern literals, not personal data.
    if ($relative -eq 'package.ps1') {
        $content = [regex]::Replace($content, '(?s)\$patterns = @\(.*?\r?\n\)', '')
    }
    foreach ($pattern in $patterns) {
        if ($content -match $pattern) { throw "Potential private data in $relative; packaging stopped. Review locally." }
    }
}
if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) ('deepseek-harness-easyconnect-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew)
try {
    $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($relative in $files) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, (Join-Path $PSScriptRoot $relative),
                ('deepseek-harness-easyconnect/' + $relative), [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally { $archive.Dispose() }
} finally { $stream.Dispose() }
Write-Host 'Packaged source files:'
$files | ForEach-Object { Write-Host "  $_" }
Write-Host "ZIP: $OutputPath"
Write-Host "SHA256: $((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash)"
