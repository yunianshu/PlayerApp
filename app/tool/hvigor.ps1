$ErrorActionPreference = 'Stop'
$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$ohosRoot = Join-Path $appRoot 'ohos'
$devecoRoot = $env:DEVECO_HOME
if (-not $devecoRoot) {
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ohos.local.json') -Raw | ConvertFrom-Json
    $devecoRoot = $config.deveco_home
}
$devecoRoot = (Resolve-Path -LiteralPath $devecoRoot).Path
$bundled = Join-Path $devecoRoot 'tools\hvigor'
$nodeRoot = Join-Path $appRoot '.hvigor-node'

function Assert-GeneratedPath([string]$path) {
    $full = [IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($appRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside workspace: $path" }
}

function Set-PackageLink([string]$link, [string]$target) {
    Assert-GeneratedPath $link
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # Delete the junction itself, never traverse the linked SDK directory.
            [IO.Directory]::Delete($link)
        } else {
            Remove-Item -LiteralPath $link -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $link) | Out-Null
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
}

foreach ($name in @('hvigor', 'hvigor-ohos-plugin')) {
    $target = (Resolve-Path -LiteralPath (Join-Path $bundled $name)).Path
    # Resolve CLI and plugin imports to the same physical package instance.
    Set-PackageLink (Join-Path $nodeRoot "@ohos\$name") $target
    Set-PackageLink (Join-Path $ohosRoot "node_modules\@ohos\$name") $target
}
$localPlugin = Join-Path $appRoot 'vendor\flutter-hvigor-plugin'
if (-not (Test-Path -LiteralPath $localPlugin)) {
    throw 'Run python tool/ohos_build.py --prepare-only, then open the generated HarmonyOS workspace.'
}
Set-PackageLink (Join-Path $ohosRoot 'node_modules\flutter-hvigor-plugin') $localPlugin
$env:NODE_PATH = $nodeRoot
$env:DEVECO_SDK_HOME = Join-Path $devecoRoot 'sdk'
$env:PATH = (Join-Path $devecoRoot 'tools\ohpm\bin') + ';' + $env:PATH
& node (Join-Path $bundled 'hvigor\bin\hvigor.js') @args
exit $LASTEXITCODE
