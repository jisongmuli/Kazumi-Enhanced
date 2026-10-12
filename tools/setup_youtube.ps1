param([string]$NodePath = '', [string]$Proxy = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot 'windows\youtube_engine'
New-Item -ItemType Directory -Force -Path $engine | Out-Null
$version = '2026.08.19'
$expected = '66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a'
$download = Join-Path $engine 'yt-dlp.exe.download'
$curlArgs = @('-fL', '--retry', '2', '--connect-timeout', '15', '--max-time', '180')
if ($Proxy) { $curlArgs += @('--proxy', $Proxy) }
& curl.exe @curlArgs "https://github.com/yt-dlp/yt-dlp/releases/download/$version/yt-dlp.exe" '-o' $download
if ($LASTEXITCODE -ne 0) { throw 'yt-dlp download failed.' }
if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'yt-dlp SHA256 mismatch; the downloaded file was not installed.'
}
Move-Item -LiteralPath $download -Destination (Join-Path $engine 'yt-dlp.exe') -Force
if (-not $NodePath) {
    $existing = Join-Path $projectRoot 'windows\danmaku_engine\node.exe'
    if (Test-Path -LiteralPath $existing) { $NodePath = $existing }
    else {
        $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($nodeCommand) { $NodePath = $nodeCommand.Source }
    }
}
if (-not $NodePath -or -not (Test-Path -LiteralPath $NodePath)) {
    throw 'Provide a Node.js 22+ executable using -NodePath.'
}
$nodeVersion = & $NodePath --version
if ($LASTEXITCODE -ne 0 -or [int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 22) {
    throw 'Node.js 22 or newer is required.'
}
Copy-Item -LiteralPath $NodePath -Destination (Join-Path $engine 'node.exe') -Force
foreach ($license in @('LICENSE', 'THIRD_PARTY_LICENSES.txt')) {
    & curl.exe @curlArgs "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$version/$license" '-o' (Join-Path $engine "yt-dlp-$license")
    if ($LASTEXITCODE -ne 0) { throw "License download failed: $license" }
}
& curl.exe @curlArgs "https://raw.githubusercontent.com/nodejs/node/$nodeVersion/LICENSE" '-o' (Join-Path $engine 'node-LICENSE')
if ($LASTEXITCODE -ne 0) { throw 'Node license download failed.' }
Write-Host "YouTube runtime installed. Rebuild Kazumi to include it. yt-dlp $version; Node $nodeVersion"
