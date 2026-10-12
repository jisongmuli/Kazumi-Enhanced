param([string]$NodePath = '', [string]$Proxy = '', [string]$Destination = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $NodePath) { $NodePath = (Get-Command node.exe -ErrorAction Stop).Source }
if ([int]((& $NodePath --version).TrimStart('v').Split('.')[0]) -lt 22) { throw 'Node.js 22 or newer is required.' }
$nodeFolder = Split-Path -Parent $NodePath
$npmPath = Join-Path $nodeFolder 'npm.cmd'
if (-not (Test-Path -LiteralPath $npmPath)) { $npmPath = (Get-Command npm.cmd -ErrorAction Stop).Source }
$engine = if ($Destination) { [IO.Path]::GetFullPath($Destination) } else { Join-Path $projectRoot 'windows\danmaku_engine' }
New-Item -ItemType Directory -Force -Path $engine | Out-Null
$revision = 'f47b786876f2ab51ef69518e5e0b1c0574664589'
$gitArguments = @()
if ($Proxy) { $gitArguments += @('-c', "http.proxy=$Proxy") }
$source = Join-Path $PSScriptRoot '.downloads\danmu_api'
if (Test-Path -LiteralPath (Join-Path $source '.git')) {
    & git @gitArguments -C $source fetch --depth 1 origin $revision
    if ($LASTEXITCODE -ne 0) { throw 'Danmaku source fetch failed.' }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $source) | Out-Null
    & git @gitArguments clone --no-checkout 'https://github.com/huangxd-/danmu_api.git' $source
    if ($LASTEXITCODE -ne 0) { throw 'Danmaku source download failed.' }
}
& git -C $source checkout --detach $revision
if ($LASTEXITCODE -ne 0) { throw 'Cannot select pinned danmaku revision.' }
foreach ($entry in Get-ChildItem -LiteralPath $source -Force | Where-Object { $_.Name -ne '.git' }) {
    Copy-Item -LiteralPath $entry.FullName -Destination $engine -Recurse -Force
}
Copy-Item -LiteralPath $NodePath -Destination (Join-Path $engine 'node.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'kazumi-danmaku-launcher.mjs') -Destination (Join-Path $engine 'kazumi-launcher.mjs') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'danmaku-package-lock.json') -Destination (Join-Path $engine 'package-lock.json') -Force
Push-Location -LiteralPath $engine
try {
    $npmArguments = @('ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund')
    if ($Proxy) { $npmArguments += @('--proxy', $Proxy, '--https-proxy', $Proxy) }
    & $npmPath @npmArguments
    if ($LASTEXITCODE -ne 0) { throw 'Danmaku dependency installation failed.' }
} finally { Pop-Location }
$nodeVersion = & $NodePath --version
$curlArguments = @('-fL', '--retry', '2', '--connect-timeout', '15', '--max-time', '60')
if ($Proxy) { $curlArguments += @('--proxy', $Proxy) }
& curl.exe @curlArguments "https://raw.githubusercontent.com/nodejs/node/$nodeVersion/LICENSE" '-o' (Join-Path $engine 'node-LICENSE')
if ($LASTEXITCODE -ne 0) { throw 'Node license download failed.' }
Write-Host "Danmaku runtime installed from $revision. Rebuild the Windows app."
