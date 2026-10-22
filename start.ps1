#requires -Version 5.1

$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This script requires 64-bit Windows.'
}

$phpDirectory = Join-Path $PSScriptRoot 'php'
$phpExecutable = Join-Path $phpDirectory 'php.exe'
if (Test-Path -LiteralPath $phpExecutable -PathType Leaf) {
    Write-Host "PHP is already installed in $phpDirectory. Skipping download and extraction."
}
else {
    $downloadUrl = 'https://downloads.php.net/~windows/releases/latest/php-8.3-nts-Win32-vs16-x64-latest.zip'
    $archivePath = Join-Path ([IO.Path]::GetTempPath()) ('php-8.3-' + [guid]::NewGuid().ToString('N') + '.zip')

    # Enable TLS 1.2 for Windows PowerShell 5.1 downloads.
    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Host 'Downloading the latest PHP 8.3 (Windows x64 NTS)...'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing

        Write-Host "Extracting PHP to $phpDirectory..."
        Expand-Archive -LiteralPath $archivePath -DestinationPath $phpDirectory -Force
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
    }
}

# Put this project's PHP first in the current session's PATH.
$env:PATH = "$phpDirectory;$env:PATH"
php -v
if ($LASTEXITCODE -ne 0) {
    throw "php -v failed with exit code $LASTEXITCODE."
}

# Configure extensions for PHP and Composer.
$phpIni = Join-Path $phpDirectory 'php.ini'
$extensionDirectory = (Join-Path $phpDirectory 'ext').Replace('\', '/')
if (-not (Test-Path -LiteralPath $phpIni -PathType Leaf)) {
    @"
extension_dir = "$extensionDirectory"
extension=openssl
"@ | Set-Content -LiteralPath $phpIni -Encoding UTF8
}

$phpIniContent = [IO.File]::ReadAllText($phpIni)
if ($phpIniContent -notmatch '(?im)^\s*extension_dir\s*=') {
    $phpIniContent += "`r`nextension_dir = `"$extensionDirectory`"`r`n"
}
foreach ($extension in @('mbstring', 'curl', 'fileinfo', 'pdo_sqlite')) {
    $extensionPattern = '(?im)^\s*extension\s*=\s*"?(?:php_)?' + [regex]::Escape($extension) + '(?:\.dll)?"?\s*(?:;[^\r\n]*)?$'
    if ($phpIniContent -notmatch $extensionPattern) {
        $phpIniContent += "`r`nextension=$extension`r`n"
    }
}
[IO.File]::WriteAllText($phpIni, $phpIniContent, [Text.UTF8Encoding]::new($false))

foreach ($extension in @('mbstring', 'curl', 'fileinfo', 'pdo_sqlite')) {
    & $phpExecutable -c $phpIni -r "exit(extension_loaded('$extension') ? 0 : 1);"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enable the PHP $extension extension."
    }
}

$composerPhar = Join-Path $phpDirectory 'composer.phar'
if (Test-Path -LiteralPath $composerPhar -PathType Leaf) {
    Write-Host 'Composer is already installed. Skipping installation.'
}
else {
    $installerPath = Join-Path ([IO.Path]::GetTempPath()) ('composer-setup-' + [guid]::NewGuid().ToString('N') + '.php')
    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Host 'Downloading and verifying the Composer installer...'
        $signatureContent = (Invoke-WebRequest -Uri 'https://composer.github.io/installer.sig' -UseBasicParsing).Content
        if ($signatureContent -is [byte[]]) {
            $signatureContent = [Text.Encoding]::UTF8.GetString($signatureContent)
        }
        $expectedHash = ([string]$signatureContent).Trim()
        if ($expectedHash -notmatch '^[a-fA-F0-9]{96}$') {
            throw 'The Composer installer signature is not a valid SHA384 hash.'
        }
        Invoke-WebRequest -Uri 'https://getcomposer.org/installer' -OutFile $installerPath -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA384).Hash
        if ($actualHash -ine $expectedHash) {
            throw 'Composer installer SHA384 verification failed.'
        }

        & $phpExecutable $installerPath "--install-dir=$phpDirectory" '--filename=composer.phar'
        if ($LASTEXITCODE -ne 0) {
            throw "Composer installation failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
        if (Test-Path -LiteralPath $installerPath) {
            Remove-Item -LiteralPath $installerPath -Force
        }
    }
}

# The PHP directory is already on PATH, so composer is available in this session.
$composerLauncher = Join-Path $phpDirectory 'composer.bat'
'@echo off', '"%~dp0php.exe" "%~dp0composer.phar" %*' |
    Set-Content -LiteralPath $composerLauncher -Encoding ASCII

& $composerLauncher --version
if ($LASTEXITCODE -ne 0) {
    throw "composer --version failed with exit code $LASTEXITCODE."
}
