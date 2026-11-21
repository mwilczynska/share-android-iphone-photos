<#
.SYNOPSIS
Download the newest published build for a cable install with iloader or Sideloadly.

.DESCRIPTION
Fetches Shortlist.ipa and source.json from the rolling GitHub release for the chosen
channel into build\<channel>\ (gitignored), and prints the build details and the
SideStore links for over-the-air installs.

The repository is read from the git remote "origin", so the script works in any clone.

.EXAMPLE
.\scripts\get-build.ps1

.EXAMPLE
.\scripts\get-build.ps1 -Channel latest
#>
[CmdletBinding()]
param(
    [ValidateSet("test", "latest")]
    [string]$Channel = "test"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = Split-Path -Parent $PSScriptRoot
$remote = git -C $repoRoot remote get-url origin
if ($remote -notmatch 'github\.com[/:]([^/]+)/([^/.]+?)(\.git)?$') {
    throw "Could not read a GitHub owner and repository from the origin remote."
}
$repository = "$($Matches[1])/$($Matches[2])"
$base = "https://github.com/$repository/releases/download/$Channel-build"

$outDir = Join-Path $repoRoot "build\$Channel"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

foreach ($name in "source.json", "Shortlist.ipa") {
    $target = Join-Path $outDir $name
    try {
        Invoke-WebRequest -Uri "$base/$name" -OutFile $target -UseBasicParsing
    }
    catch {
        throw "No $Channel build is published yet ($base/$name): $($_.Exception.Message)"
    }
}

$source = Get-Content -Raw -Path (Join-Path $outDir "source.json") | ConvertFrom-Json
$version = $source.apps[0].versions[0]
$ipa = Get-Item (Join-Path $outDir "Shortlist.ipa")

Write-Host ""
Write-Host "Downloaded $Channel build $($version.version) ($($version.buildVersion)), built $($version.date)" -ForegroundColor Green
Write-Host ("  {0}  ({1:N1} MB)" -f $ipa.FullName, ($ipa.Length / 1MB))
if ($ipa.Length -ne $version.size) {
    Write-Warning "File size $($ipa.Length) does not match the size in source.json ($($version.size)). Download again."
}
Write-Host ""
Write-Host "Cable install: connect the iPhone and open the file above in iloader or Sideloadly."
Write-Host ""
Write-Host "Over the air, paste into Safari on the iPhone:"
Write-Host "  sidestore://source?url=$base/source.json   (once; later builds appear as updates)"
Write-Host "  sidestore://install?url=$base/Shortlist.ipa"
