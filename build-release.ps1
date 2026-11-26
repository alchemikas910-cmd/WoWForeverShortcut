# Builds dist\WoW-Forever-Shortcut.zip for a GitHub release: the installer and its files only.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$out = Join-Path $dist 'WoW-Forever-Shortcut.zip'
if (Test-Path $out) { Remove-Item -Force $out }
$zip = [IO.Compression.ZipFile]::Open($out, 'Create')
try {
    foreach ($rel in @('Install.vbs', 'install.ps1', 'README.md', 'LICENSE', 'files\launch.ps1', 'files\WoW Forever.vbs')) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root $rel), 'WoW Forever Shortcut/' + ($rel -replace '\\', '/'))
    }
} finally { $zip.Dispose() }
Write-Output "$out : $([math]::Round((Get-Item $out).Length / 1KB, 1)) KB"
