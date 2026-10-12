param([string]$Proxy = '', [string]$CacheDirectory = '', [string]$Destination = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $CacheDirectory) { $CacheDirectory = Join-Path $PSScriptRoot '.downloads' }
if (-not $Destination) { $Destination = Join-Path $projectRoot 'local_overrides\media_kit_video\windows\ANGLE' }
New-Item -ItemType Directory -Force -Path $CacheDirectory, $Destination | Out-Null
$archive = Join-Path $CacheDirectory 'ANGLE.7z'
$expected = 'cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a'
if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    $curlArgs = @('-fL', '--retry', '2', '--connect-timeout', '15', '--max-time', '180')
    if ($Proxy) { $curlArgs += @('--proxy', $Proxy) }
    & curl.exe @curlArgs 'https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z' '-o' $archive
    if ($LASTEXITCODE -ne 0) { throw 'ANGLE download failed.' }
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'ANGLE SHA256 mismatch.' }
$cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
if (-not $cmakeCommand) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        $cmakeCandidate = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        if (Test-Path -LiteralPath $cmakeCandidate) { $cmakeCommand = Get-Command -Name $cmakeCandidate }
    }
}
if (-not $cmakeCommand) { throw 'Install Visual Studio Desktop development with C++ / CMake.' }
Push-Location -LiteralPath $Destination
try {
    & $cmakeCommand.Source -E tar xf $archive
    if ($LASTEXITCODE -ne 0) { throw 'ANGLE extraction failed.' }
} finally { Pop-Location }
foreach ($required in @('libEGL.dll', 'libGLESv2.dll', 'lib\libEGL.dll.lib', 'include\EGL\egl.h')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Destination $required))) { throw "Missing ANGLE component: $required" }
}
Write-Host "Verified ANGLE v1.0.1 installed: $Destination"
