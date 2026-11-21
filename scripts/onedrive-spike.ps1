<#
.SYNOPSIS
Phase 0b test: sign in to a personal Microsoft account with the device-code flow and
upload one file to the app's own OneDrive folder through an upload session.

.DESCRIPTION
Answers the open questions from docs/iphone-app-plan.md before any app code depends on them:
  - Does device-code sign-in work for a "personal accounts only" app registration?
  - Is the Files.ReadWrite.AppFolder scope enough to create an upload session?
  - Does the pre-authenticated upload URL accept fragments without an Authorization header?
  - Are the capture timestamps we send kept by OneDrive?
  - What does a second upload of the same name return?

Nothing is written to disk. Tokens stay in memory and are never printed.

The client ID comes from -ClientId, then the SHORTLIST_ONEDRIVE_CLIENT_ID environment
variable, then private/onedrive.local.json ({"clientId": "..."}). The private/ folder
is gitignored. Do not put the client ID in any committed file.

.EXAMPLE
.\scripts\onedrive-spike.ps1 -FilePath C:\Temp\sample.heic

.EXAMPLE
.\scripts\onedrive-spike.ps1 -FilePath C:\Temp\clip.mov -Scope "Files.ReadWrite offline_access"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string]$ClientId,

    # Folder inside the app folder (Apps/<app name>/).
    [string]$RemoteFolder = "spike",

    # Defaults to the local file name.
    [string]$RemoteName,

    [string]$Scope = "Files.ReadWrite.AppFolder offline_access",

    # Timestamp to store as the file's created and modified time. Defaults to the
    # local file's last write time.
    [datetime]$CaptureDate,

    # Must be a multiple of 320 KiB and below 60 MiB. 10 MiB is 32 x 320 KiB.
    [ValidateRange(1, 59)]
    [int]$FragmentSizeMiB = 10
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$authority = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
$graph = "https://graph.microsoft.com/v1.0"

function Get-HttpErrorInfo {
    param($ErrorRecord)
    $status = $null
    $body = $null
    $response = $ErrorRecord.Exception.Response
    if ($response) {
        try { $status = [int]$response.StatusCode } catch { }
    }
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $body = $ErrorRecord.ErrorDetails.Message
    }
    elseif ($response -and ($response | Get-Member -Name GetResponseStream -MemberType Method)) {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $body = $reader.ReadToEnd()
    }
    $json = $null
    if ($body) {
        try { $json = $body | ConvertFrom-Json } catch { }
    }
    [pscustomobject]@{ Status = $status; Body = $body; Json = $json }
}

function Resolve-ClientId {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    if ($env:SHORTLIST_ONEDRIVE_CLIENT_ID) { return $env:SHORTLIST_ONEDRIVE_CLIENT_ID }
    $configPath = Join-Path (Split-Path -Parent $PSScriptRoot) "private\onedrive.local.json"
    if (Test-Path $configPath) {
        $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        if ($config.clientId) { return $config.clientId }
    }
    throw "No client ID. Pass -ClientId, set SHORTLIST_ONEDRIVE_CLIENT_ID, or create private\onedrive.local.json with {""clientId"": ""...""}."
}

function Get-AccessToken {
    param([string]$Client, [string]$Scopes)

    $device = Invoke-RestMethod -Method Post -Uri "$authority/devicecode" -Body @{
        client_id = $Client
        scope     = $Scopes
    }
    Write-Host ""
    Write-Host $device.message -ForegroundColor Cyan
    Write-Host ""

    $interval = [int]$device.interval
    if ($interval -lt 1) { $interval = 5 }
    $deadline = (Get-Date).AddSeconds([int]$device.expires_in)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            return Invoke-RestMethod -Method Post -Uri "$authority/token" -Body @{
                grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
                client_id   = $Client
                device_code = $device.device_code
            }
        }
        catch {
            $info = Get-HttpErrorInfo $_
            $code = if ($info.Json) { $info.Json.error } else { $null }
            switch ($code) {
                "authorization_pending" { continue }
                "slow_down" { $interval += 5; continue }
                "authorization_declined" { throw "Sign-in was declined." }
                "expired_token" { throw "The sign-in code expired. Run the script again." }
                default { throw "Token request failed (HTTP $($info.Status)): $($info.Body)" }
            }
        }
    }
    throw "The sign-in code expired. Run the script again."
}

function ConvertTo-GraphPath {
    param([string[]]$Segments)
    ($Segments | Where-Object { $_ } | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/"
}

# --- Inputs -----------------------------------------------------------------

$file = Get-Item -LiteralPath $FilePath
if ($file.PSIsContainer) { throw "$FilePath is a folder. Pass a single file." }
if (-not $RemoteName) { $RemoteName = $file.Name }
if (-not $PSBoundParameters.ContainsKey("CaptureDate")) { $CaptureDate = $file.LastWriteTimeUtc }
$captureIso = $CaptureDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$fragmentSize = $FragmentSizeMiB * 1MB
if ($fragmentSize % 327680 -ne 0) {
    throw "Fragment size must be a multiple of 320 KiB. Use 5, 10, 15, 20 ... MiB."
}

$client = Resolve-ClientId $ClientId
$results = [ordered]@{}

# --- Sign in ----------------------------------------------------------------

$token = Get-AccessToken -Client $client -Scopes $Scope
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$results["Device-code sign-in"] = "worked"
$results["Scopes granted"] = $token.scope
$results["Refresh token issued"] = [bool]$token.refresh_token

# --- App folder -------------------------------------------------------------

$appRoot = Invoke-RestMethod -Method Get -Uri "$graph/me/drive/special/approot" -Headers $headers
$results["App folder name"] = $appRoot.name

# --- Upload session ---------------------------------------------------------

$remotePath = ConvertTo-GraphPath @($RemoteFolder, $RemoteName)
$sessionBody = @{
    item = @{
        "@microsoft.graph.conflictBehavior" = "fail"
        fileSystemInfo                      = @{
            createdDateTime      = $captureIso
            lastModifiedDateTime = $captureIso
        }
    }
} | ConvertTo-Json -Depth 5

$session = $null
try {
    $session = Invoke-RestMethod -Method Post `
        -Uri "$graph/me/drive/special/approot:/${remotePath}:/createUploadSession" `
        -Headers $headers -ContentType "application/json" -Body $sessionBody
    $results["Create upload session"] = "worked with scope '$Scope'"
}
catch {
    $info = Get-HttpErrorInfo $_
    if ($info.Status -eq 409) {
        $results["Create upload session"] = "409 conflict: a file with this name already exists (expected on a repeat run)"
    }
    else {
        $results["Create upload session"] = "FAILED (HTTP $($info.Status)): $($info.Body)"
    }
}

# --- Upload fragments -------------------------------------------------------

$item = $null
if ($session) {
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromMinutes(10)
    $stream = [System.IO.File]::OpenRead($file.FullName)
    try {
        $total = $stream.Length
        $buffer = New-Object byte[] $fragmentSize
        $offset = [long]0
        $fragments = 0
        while ($offset -lt $total) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $content = [System.Net.Http.ByteArrayContent]::new($buffer, 0, $read)
            $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
            $content.Headers.ContentRange = [System.Net.Http.Headers.ContentRangeHeaderValue]::new($offset, $offset + $read - 1, $total)

            # No Authorization header: the upload URL is pre-authenticated.
            $response = $http.PutAsync($session.uploadUrl, $content).GetAwaiter().GetResult()
            $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            $fragments++
            $offset += $read
            Write-Host ("  fragment {0}: {1:N0} of {2:N0} bytes, HTTP {3}" -f $fragments, $offset, $total, $status)

            if ($status -eq 200 -or $status -eq 201) {
                $item = $responseBody | ConvertFrom-Json
                break
            }
            if ($status -eq 409) {
                $results["Upload"] = "409 conflict on the final fragment: name already exists"
                break
            }
            if ($status -ne 202) {
                $results["Upload"] = "FAILED (HTTP $status): $responseBody"
                break
            }
        }
        if ($item) {
            $results["Upload"] = "worked without an Authorization header, $fragments fragment(s)"
        }
    }
    finally {
        $stream.Dispose()
        $http.Dispose()
    }
}

# --- Read back --------------------------------------------------------------

if ($item) {
    $select = "name,size,fileSystemInfo,photo,video,file"
    $check = Invoke-RestMethod -Method Get -Uri "$graph/me/drive/items/$($item.id)?`$select=$select" -Headers $headers
    $results["Size matches"] = ($check.size -eq $file.Length)
    $results["Sent capture time"] = $captureIso
    $results["Stored created time"] = $check.fileSystemInfo.createdDateTime
    $results["Stored modified time"] = $check.fileSystemInfo.lastModifiedDateTime
    $results["Photo taken time (from EXIF)"] = if ($check.photo -and $check.photo.takenDateTime) { $check.photo.takenDateTime } else { "not extracted" }
    $results["Hashes available"] = if ($check.file -and $check.file.hashes) { ($check.file.hashes.PSObject.Properties.Name -join ", ") } else { "none" }
}

Write-Host ""
Write-Host "Results" -ForegroundColor Green
$results.GetEnumerator() | ForEach-Object { "{0,-30} {1}" -f $_.Key, $_.Value }
Write-Host ""
Write-Host "Run the same command again to see how a duplicate name is reported."
