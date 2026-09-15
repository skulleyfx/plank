<#
.SYNOPSIS
  Prepares %ProgramData%\PLANK for the PLANK Windows host.

.DESCRIPTION
  Run by the PLANK Host MSI as LocalSystem after files are installed and before
  the service starts. It is safe to run again: existing state is kept.

  - Restricts %ProgramData%\PLANK to Administrators and SYSTEM (it holds the
    TLS private key, DUO secret and resume tickets).
  - Keeps a valid host certificate, or generates one matching the PLANK TLS
    profile: self-signed RSA 3072, DNS subject alternative name, no IP SAN.
    Clients pin the certificate, so an existing valid one is never replaced.
  - Keeps plank-state.json, or creates it with a new host unique ID.
    Clients pin this ID.
  - Writes host.conf on first install only. DUO settings passed in are
    applied to an existing host.conf as well.

  This mirrors packaging/host/linux/bin/plank-host-certificate and
  plank-host-state.
#>
param(
  [string] $DnsName = '',
  [string] $DuoIntegrationKey = '',
  [string] $DuoSecretKey = '',
  [string] $DuoApiHost = '',
  [string] $DefaultDomain = '',
  [string] $DataDirectory = (Join-Path $env:ProgramData 'PLANK')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Write-Step([string] $Message) {
  Write-Output "plank-host-setup: $Message"
}

function Test-DnsName([string] $Name) {
  return $Name -match '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$' -and
         $Name -notmatch '\.\.' -and
         $Name -notmatch '^[0-9.]+$'
}

function ConvertTo-Pem([byte[]] $Der, [string] $Label) {
  $base64 = [Convert]::ToBase64String($Der)
  $lines = for ($i = 0; $i -lt $base64.Length; $i += 64) {
    $base64.Substring($i, [Math]::Min(64, $base64.Length - $i))
  }
  return "-----BEGIN $Label-----`n" + ($lines -join "`n") + "`n-----END $Label-----`n"
}

function ConvertFrom-Pem([string] $Path, [string] $Label) {
  $text = [IO.File]::ReadAllText($Path)
  $pattern = "-----BEGIN $Label-----(.+?)-----END $Label-----"
  $match = [regex]::Match($text, $pattern, 'Singleline')
  if (-not $match.Success) { return $null }
  return [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
}

function Test-CertificateProfile([string] $CertificatePath, [string] $KeyPath) {
  if (-not (Test-Path $CertificatePath) -or -not (Test-Path $KeyPath)) { return $false }
  if ((Get-Item $CertificatePath).Length -eq 0 -or (Get-Item $KeyPath).Length -eq 0) { return $false }
  try {
    $der = ConvertFrom-Pem $CertificatePath 'CERTIFICATE'
    if ($null -eq $der) { return $false }
    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 (, $der)
    if ($certificate.NotAfter -le (Get-Date)) { return $false }
    if ($certificate.Subject -ne $certificate.Issuer) { return $false }
    $publicKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
    if ($null -eq $publicKey -or $publicKey.KeySize -lt 3072) { return $false }
    $san = $certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
    if ($null -eq $san) { return $false }
    $sanText = $san.Format($false)
    if ($sanText -notmatch 'DNS Name=' -or $sanText -match 'IP Address=') { return $false }

    # The private key must belong to the certificate. PKCS#8 keys are
    # checked; a key in another format is accepted as-is so an existing,
    # pinned certificate is never replaced because of its key encoding.
    $keyDer = ConvertFrom-Pem $KeyPath 'PRIVATE KEY'
    if ($null -ne $keyDer) {
      $cngKey = [System.Security.Cryptography.CngKey]::Import($keyDer, [System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
      try {
        $privateKey = New-Object System.Security.Cryptography.RSACng ($cngKey)
        $a = $privateKey.ExportParameters($false).Modulus
        $b = $publicKey.ExportParameters($false).Modulus
        if ([Convert]::ToBase64String($a) -ne [Convert]::ToBase64String($b)) { return $false }
      } finally {
        $cngKey.Dispose()
      }
    }
    return $true
  } catch {
    Write-Step "existing certificate could not be validated: $($_.Exception.Message)"
    return $false
  }
}

function New-HostCertificate([string] $CertificatePath, [string] $KeyPath, [string] $Name) {
  Add-Type -AssemblyName System.Security
  # An ephemeral key is never written to a Windows key store, and can be
  # exported without DPAPI (which is unavailable in some service and remote
  # sessions).
  $rsa = New-Object System.Security.Cryptography.RSACng 3072
  $cngKey = $rsa.Key
  try {
    $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest (
      "CN=$Name", $rsa,
      [System.Security.Cryptography.HashAlgorithmName]::SHA256,
      [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    $san = New-Object System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder
    $san.AddDnsName($Name)
    $request.CertificateExtensions.Add($san.Build($false))
    $request.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension ($true, $true, 0, $true)))
    $usage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]'DigitalSignature, KeyEncipherment, KeyCertSign'
    $request.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509KeyUsageExtension ($usage, $true)))
    $serverAuth = New-Object System.Security.Cryptography.OidCollection
    [void] $serverAuth.Add((New-Object System.Security.Cryptography.Oid '1.3.6.1.5.5.7.3.1'))
    $request.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension ($serverAuth, $false)))
    $request.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension ($request.PublicKey, $false)))

    $now = [DateTimeOffset]::UtcNow
    $certificate = $request.CreateSelfSigned($now.AddDays(-1), $now.AddDays(3650))

    $temporaryCertificate = "$CertificatePath.tmp"
    $temporaryKey = "$KeyPath.tmp"
    $encoding = New-Object System.Text.ASCIIEncoding
    [IO.File]::WriteAllText($temporaryCertificate, (ConvertTo-Pem $certificate.RawData 'CERTIFICATE'), $encoding)
    [IO.File]::WriteAllText($temporaryKey, (ConvertTo-Pem $cngKey.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob) 'PRIVATE KEY'), $encoding)

    if (-not (Test-CertificateProfile $temporaryCertificate $temporaryKey)) {
      Remove-Item $temporaryCertificate, $temporaryKey -Force -ErrorAction SilentlyContinue
      throw 'generated certificate failed the PLANK TLS profile'
    }
    Move-Item $temporaryKey $KeyPath -Force
    Move-Item $temporaryCertificate $CertificatePath -Force
    Write-Step "host_certificate=generated dns_name=$Name sha256=$([BitConverter]::ToString((New-Object System.Security.Cryptography.SHA256Managed).ComputeHash($certificate.RawData)) -replace '-', '')"
  } finally {
    $cngKey.Dispose()
  }
}

function Set-ConfigValue([string[]] $Lines, [string] $Key, [string] $Value) {
  # Replace key in [security], or append it right after the [security] header.
  $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
  $found = $false
  $result = foreach ($line in $Lines) {
    if ($line -match $pattern) { "$Key = $Value"; $found = $true } else { $line }
  }
  if (-not $found) {
    $result = foreach ($line in $result) {
      $line
      if ($line -match '^\s*\[security\]\s*$' -and -not $found) { "$Key = $Value"; $found = $true }
    }
  }
  if (-not $found) { $result = @($result) + '[security]' + "$Key = $Value" }
  return , @($result)
}

# --- Data directory -----------------------------------------------------------
$tlsDirectory = Join-Path $DataDirectory 'tls'
New-Item -ItemType Directory -Force $tlsDirectory | Out-Null
& icacls.exe $DataDirectory /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed on $DataDirectory" }
& icacls.exe "$DataDirectory\*" /reset /T /C /Q | Out-Null
Write-Step "data_directory=$DataDirectory (Administrators, SYSTEM)"

# --- Certificate --------------------------------------------------------------
$certificatePath = Join-Path $tlsDirectory 'cert.pem'
$keyPath = Join-Path $tlsDirectory 'key.pem'
if (Test-CertificateProfile $certificatePath $keyPath) {
  Write-Step 'host_certificate=valid'
} else {
  if (-not $DnsName) {
    try { $DnsName = ([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)).HostName.ToLowerInvariant() } catch { $DnsName = '' }
    if (-not (Test-DnsName $DnsName)) { $DnsName = $env:COMPUTERNAME.ToLowerInvariant() }
  }
  if (-not (Test-DnsName $DnsName)) { throw "unable to determine a valid DNS name for the host certificate: '$DnsName'" }
  New-HostCertificate $certificatePath $keyPath $DnsName
}

# --- Host identity ------------------------------------------------------------
$statePath = Join-Path $DataDirectory 'plank-state.json'
$uuidPattern = '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
$existingId = $null
if (Test-Path $statePath) {
  try { $existingId = (Get-Content $statePath -Raw | ConvertFrom-Json).root.uniqueid } catch { $existingId = $null }
}
if ($existingId -and $existingId -match $uuidPattern) {
  Write-Step "host_state=valid uuid=$($existingId.ToUpperInvariant())"
} elseif (Test-Path $statePath) {
  throw "$statePath exists but has no valid uniqueid; fix or remove it by hand so paired clients are not silently broken"
} else {
  $newId = [guid]::NewGuid().ToString().ToUpperInvariant()
  $json = "{`n    `"root`": {`n        `"uniqueid`": `"$newId`"`n    }`n}`n"
  [IO.File]::WriteAllText($statePath, $json, (New-Object System.Text.ASCIIEncoding))
  Write-Step "host_state=generated uuid=$newId"
}

# --- Configuration ------------------------------------------------------------
$configPath = Join-Path $DataDirectory 'host.conf'
$dataForward = $DataDirectory -replace '\\', '/'
if (-not (Test-Path $configPath)) {
  @"
# PLANK Host configuration.
# Written by the installer on first install. Upgrades keep this file.

[network]
port = 28989

[display]
startup_layout = physical

[security]
# DUO push after the Windows password. With second_factor = duo and no DUO
# keys set, every sign-in is refused.
second_factor = duo
second_factor_failmode = deny
allow_root_login = false
# Lock the workstation this many seconds after the last stream ends.
lock_on_disconnect = true
lock_on_disconnect_delay = 30
cert = $dataForward/tls/cert.pem
pkey = $dataForward/tls/key.pem
file_state = $dataForward/plank-state.json

[discovery]
mdns_discovery = false

[logging]
log_path = $dataForward/host.log
min_log_level = info
"@ | Set-Content -Path $configPath -Encoding Ascii
  Write-Step 'host_config=generated'
} else {
  Write-Step 'host_config=kept'
}

$lines = @(Get-Content $configPath)
$changed = @()
if ($DefaultDomain) { $lines = Set-ConfigValue $lines 'default_domain' $DefaultDomain; $changed += 'default_domain' }
if ($DuoApiHost) { $lines = Set-ConfigValue $lines 'duo_api_host' $DuoApiHost; $changed += 'duo_api_host' }
if ($DuoIntegrationKey) { $lines = Set-ConfigValue $lines 'duo_integration_key' $DuoIntegrationKey; $changed += 'duo_integration_key' }
if ($DuoSecretKey) { $lines = Set-ConfigValue $lines 'duo_secret_key' $DuoSecretKey; $changed += 'duo_secret_key' }
if ($changed.Count -gt 0) {
  $lines | Set-Content -Path $configPath -Encoding Ascii
  Write-Step "host_config_updated=$($changed -join ',')"
}
& icacls.exe "$DataDirectory\*" /reset /T /C /Q | Out-Null
