# sign-exe.ps1 — 为 GUI 生成自签名代码签名证书并签名 exe/dll（v1.3）
# 说明：自签名证书能让 Windows 验证“文件未被篡改 + 发布者一致”，但不会消除 SmartScreen 提示；
#       正式对外分发需购买 CA 签发的代码签名证书（OV/EV）。证书私钥（.pfx）只保存在本地、不要外传。
[CmdletBinding()]
param(
    [string]$ExePath = (Join-Path $PSScriptRoot 'dist-exe\WsDoctorGui.exe'),
    [string]$SigningDirectory = (Join-Path $PSScriptRoot 'signing'),
    [string]$PfxPassword = 'wsdoctor-local-pfx',
    [switch]$NewCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pfxPath = Join-Path $SigningDirectory 'WsDoctorGui-CodeSigning.pfx'
$cerPath = Join-Path $SigningDirectory 'WsDoctorGui-CodeSigning.cer'
New-Item -ItemType Directory -Path $SigningDirectory -Force | Out-Null

if ($NewCertificate -or -not (Test-Path $pfxPath)) {
    Write-Host '[sign] 生成自签名代码签名证书（不写证书存储）…'
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=WsDoctor GUI (Self-Signed)', $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true))
        $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
                [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
        $oids = [System.Security.Cryptography.OidCollection]::new()
        [void]$oids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))  # Code Signing EKU
        $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false))
        $certificate = $request.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-1), [DateTimeOffset]::Now.AddYears(5))
        try {
            [System.IO.File]::WriteAllBytes($pfxPath, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $PfxPassword))
            [System.IO.File]::WriteAllBytes($cerPath, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            Write-Host ('[sign] 证书指纹: ' + $certificate.Thumbprint)
        } finally {
            $certificate.Dispose()
        }
    } finally {
        $rsa.Dispose()
    }
}

$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $pfxPath, $PfxPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
try {
    $targets = @(
        $ExePath,
        (Join-Path (Split-Path $ExePath) 'WsDoctorGui.dll')
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($targets.Count -eq 0) { throw '找不到待签名文件（先运行 build-exe.ps1）' }

    foreach ($target in $targets) {
        $signature = Set-AuthenticodeSignature -FilePath $target -Certificate $cert -HashAlgorithm SHA256 -ErrorAction Stop
        Write-Host ('[sign] {0,-20} 状态={1}' -f (Split-Path $target -Leaf), $signature.Status)
    }

    Write-Host ''
    Write-Host '=== 校验 ===' -ForegroundColor Cyan
    foreach ($target in $targets) {
        $result = Get-AuthenticodeSignature -FilePath $target
        $signer = if ($result.SignerCertificate) { $result.SignerCertificate.Subject } else { '(无)' }
        Write-Host ('  {0,-20} Status={1}  Signer={2}' -f (Split-Path $target -Leaf), $result.Status, $signer)
        if ($result.Status -eq 'HashMismatch' -or $result.Status -eq 'NotSigned') {
            throw ('签名校验失败: ' + $target + ' -> ' + $result.Status)
        }
    }
    Write-Host ''
    Write-Host '[sign] 提示：自签名证书在未安装信任前，Windows 会显示“未知发布者”（Status=UnknownError/NotTrusted 属正常，签名本身有效）。'
    Write-Host ('[sign] 证书: ' + (Get-Item $cerPath).FullName)
} finally {
    $cert.Dispose()
}
