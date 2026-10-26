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

$nodeDirectory = Join-Path $PSScriptRoot 'node'
$nodeExecutable = Join-Path $nodeDirectory 'node.exe'
$npmLauncher = Join-Path $nodeDirectory 'npm.cmd'
if ((Test-Path -LiteralPath $nodeExecutable -PathType Leaf) -and
    (Test-Path -LiteralPath $npmLauncher -PathType Leaf)) {
    Write-Host "Node.js is already installed in $nodeDirectory. Skipping download and extraction."
}
else {
    $nodeTempDirectory = Join-Path ([IO.Path]::GetTempPath()) ('node-install-' + [guid]::NewGuid().ToString('N'))
    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Host 'Finding the latest Node.js LTS release (Windows x64)...'
        $nodeReleases = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
        $nodeRelease = $nodeReleases | Where-Object { $_.lts -and ($_.files -contains 'win-x64-zip') } | Select-Object -First 1
        if (-not $nodeRelease) {
            throw 'No Node.js LTS release with a Windows x64 ZIP was found.'
        }

        $nodeArchiveName = "node-$($nodeRelease.version)-win-x64.zip"
        $nodeReleaseUrl = "https://nodejs.org/dist/$($nodeRelease.version)"
        New-Item -ItemType Directory -Path $nodeTempDirectory | Out-Null
        $nodeArchivePath = Join-Path $nodeTempDirectory $nodeArchiveName
        Write-Host "Downloading Node.js $($nodeRelease.version)..."
        Invoke-WebRequest -Uri "$nodeReleaseUrl/$nodeArchiveName" -OutFile $nodeArchivePath -UseBasicParsing

        $nodeChecksums = (Invoke-WebRequest -Uri "$nodeReleaseUrl/SHASUMS256.txt" -UseBasicParsing).Content
        if ($nodeChecksums -is [byte[]]) {
            $nodeChecksums = [Text.Encoding]::UTF8.GetString($nodeChecksums)
        }
        $nodeHashPattern = '(?im)^([a-f0-9]{64})\s+' + [regex]::Escape($nodeArchiveName) + '\s*$'
        if ([string]$nodeChecksums -notmatch $nodeHashPattern) {
            throw 'The Node.js archive SHA256 checksum was not found.'
        }
        $nodeExpectedHash = $Matches[1]
        if ((Get-FileHash -LiteralPath $nodeArchivePath -Algorithm SHA256).Hash -ine $nodeExpectedHash) {
            throw 'Node.js archive SHA256 verification failed.'
        }

        Write-Host "Extracting Node.js to $nodeDirectory..."
        Expand-Archive -LiteralPath $nodeArchivePath -DestinationPath $nodeTempDirectory -Force
        $nodeExtractedDirectory = Join-Path $nodeTempDirectory "node-$($nodeRelease.version)-win-x64"
        New-Item -ItemType Directory -Path $nodeDirectory -Force | Out-Null
        Get-ChildItem -LiteralPath $nodeExtractedDirectory -Force | Copy-Item -Destination $nodeDirectory -Recurse -Force
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
        if (Test-Path -LiteralPath $nodeTempDirectory) {
            $resolvedNodeTempDirectory = [IO.Path]::GetFullPath($nodeTempDirectory)
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
            if (-not $resolvedNodeTempDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove a Node.js temporary directory outside the system temp directory.'
            }
            Remove-Item -LiteralPath $resolvedNodeTempDirectory -Recurse -Force
        }
    }
}

# Put this project's Node.js first in the current session's PATH.
$env:PATH = "$nodeDirectory;$env:PATH"
& $nodeExecutable --version
if ($LASTEXITCODE -ne 0) {
    throw "node --version failed with exit code $LASTEXITCODE."
}
& $npmLauncher --version
if ($LASTEXITCODE -ne 0) {
    throw "npm --version failed with exit code $LASTEXITCODE."
}
