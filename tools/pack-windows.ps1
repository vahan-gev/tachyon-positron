<#
.SYNOPSIS
  Package a compiled Positron program into a self-contained Windows app folder
  (and a .zip), optionally bundling node.exe and the WebView2 loader, and
  optionally code-signing with signtool. Run this on Windows.

.EXAMPLE
  pwsh tools/pack-windows.ps1 -Bin target/release/myapp.exe -Name "My App" `
    -Resources web,server.js -Node -WebView2Loader "C:\path\WebView2Loader.dll"

.PARAMETER Bin        The compiled Tachyon executable (required).
.PARAMETER Name       App display name (required).
.PARAMETER Resources  Files/folders to copy into the app (app runs with its
                      working dir set here, so bundled assets resolve as-is).
.PARAMETER Node       Bundle the current node.exe (self-contained).
.PARAMETER WebView2Loader  Path to WebView2Loader.dll to bundle (needed at
                      runtime; the SDK ships it under runtimes\win-x64\native).
.PARAMETER Icon       .ico file for the app. It is embedded into the .exe with
                      rcedit if rcedit(.exe) is on PATH (install via scoop/choco
                      or from github.com/electron/rcedit); otherwise it is just
                      bundled alongside and a warning is printed.
.PARAMETER Sign       Code-sign with signtool. Pass a certificate subject name
                      (uses /n) or thumbprint (uses /sha1). Requires the Windows
                      SDK signtool.exe on PATH.
.PARAMETER Out        Output directory (default: current directory).
#>
param(
  [Parameter(Mandatory=$true)][string]$Bin,
  [Parameter(Mandatory=$true)][string]$Name,
  [string[]]$Resources = @(),
  [switch]$Node,
  [string]$WebView2Loader = "",
  [string]$Icon = "",
  [string]$Sign = "",
  [string]$Out = "."
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Bin)) { throw "binary not found: $Bin" }

$dir = Join-Path $Out $Name
Write-Host "==> building $dir"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# executable (ensure .exe)
$exe = Join-Path $dir ("{0}.exe" -f $Name)
Copy-Item $Bin $exe -Force

# resources
foreach ($r in $Resources) {
  if ([string]::IsNullOrWhiteSpace($r)) { continue }
  Write-Host "   + resource $r"
  Copy-Item $r $dir -Recurse -Force
}

# bundled node
if ($Node) {
  $node = (Get-Command node -ErrorAction SilentlyContinue)
  if (-not $node) { throw "-Node given but node.exe not on PATH" }
  Copy-Item $node.Source (Join-Path $dir "node.exe") -Force
  Write-Host ("   + bundled node ({0})" -f (& node --version))
}

# WebView2 loader (required at runtime)
if ($WebView2Loader -ne "") {
  if (-not (Test-Path $WebView2Loader)) { throw "WebView2Loader not found: $WebView2Loader" }
  Copy-Item $WebView2Loader (Join-Path $dir "WebView2Loader.dll") -Force
  Write-Host "   + WebView2Loader.dll"
} else {
  Write-Warning "no -WebView2Loader given; the app needs WebView2Loader.dll beside the .exe at runtime"
}

# icon — bundle it and embed it into the .exe (Windows keeps the icon inside
# the PE binary, so a copy alongside isn't enough; rcedit injects it)
if ($Icon -ne "") {
  if (-not (Test-Path $Icon)) { throw "icon not found: $Icon" }
  Copy-Item $Icon $dir -Force
  $rcedit = Get-Command rcedit -ErrorAction SilentlyContinue
  if (-not $rcedit) { $rcedit = Get-Command rcedit.exe -ErrorAction SilentlyContinue }
  if (-not $rcedit) { $rcedit = Get-Command rcedit-x64.exe -ErrorAction SilentlyContinue }
  if ($rcedit) {
    Write-Host "   + embedding icon into $Name.exe"
    & $rcedit.Source $exe --set-icon $Icon
    if ($LASTEXITCODE -ne 0) { throw "rcedit failed to set the icon (exit $LASTEXITCODE)" }
  } else {
    Write-Warning "icon bundled but not embedded: rcedit not found on PATH. Install it (scoop install rcedit, choco install rcedit, or github.com/electron/rcedit) to set the .exe icon."
  }
}

# launcher that sets the working dir + PATH (so bundled node and relative
# asset paths resolve), then starts the app without a console window
$cmd = @"
@echo off
cd /d "%~dp0"
set "PATH=%~dp0;%PATH%"
start "" "%~dp0$Name.exe" %*
"@
Set-Content -Path (Join-Path $dir ("Start {0}.cmd" -f $Name)) -Value $cmd -Encoding ASCII

# code signing
if ($Sign -ne "") {
  $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue)
  if (-not $signtool) { throw "-Sign given but signtool.exe not on PATH (install the Windows SDK)" }
  $selector = if ($Sign -match '^[0-9A-Fa-f]{40}$') { @("/sha1", $Sign) } else { @("/n", $Sign) }
  Write-Host "==> signing $exe"
  & signtool.exe sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 @selector $exe
  if ($Node)                     { & signtool.exe sign /fd SHA256 @selector (Join-Path $dir "node.exe") }
}

# zip it
$zip = Join-Path $Out ("{0}.zip" -f $Name)
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip
Write-Host "==> done: $dir  and  $zip"
