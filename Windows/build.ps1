param([ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64', [string]$Output = '../publish')
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot $Output
& dotnet publish (Join-Path $PSScriptRoot 'OpenWall.Windows.csproj') -c Release -r $Runtime --self-contained true -o $target
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
Copy-Item (Join-Path $target 'OpenWall.exe') (Join-Path $target 'OpenWall.scr') -Force
Copy-Item (Join-Path $PSScriptRoot '../LICENSE') $target
Write-Output "Built OpenWall and screen saver for $Runtime in $target"
