<#
.SYNOPSIS
    Maakt een ondertekend Windows-installatiepakket (MSI) van Klimaatatlas.

.DESCRIPTION
    1. Zet het versienummer (in de projecten van de GUI en de CLI)
    2. Draait de tests
    3. Publiceert de app (self-contained win-x64); Klimaatatlas.exe en de eigen dll's worden ondertekend
    4. Bouwt de MSI (WiX, project installer\)
    5. Ondertekent de MSI en controleert alle handtekeningen
    Resultaat: dist\Klimaatatlas-<versie>-x64.msi

    Voor het ondertekenen moet SimplySign ingelogd zijn.

.EXAMPLE
    .\build-release.ps1 2.0.1
    Nieuwe versie 2.0.1 bouwen (het versienummer moet bij elke uitgave omhoog).

.EXAMPLE
    .\build-release.ps1 -NoSign
    Proefbouw met de huidige versie, zonder te ondertekenen (niet geschikt om te verspreiden).
#>
param(
    [Parameter(Position = 0)]
    [string]$Version,
    [switch]$SkipTests,
    [switch]$NoSign
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$GuiProject = 'src\Klimaatatlas.Gui\Klimaatatlas.Gui.csproj'
$VersionedProjects = @($GuiProject, 'src\Klimaatatlas.Cli\Klimaatatlas.Cli.csproj')
$InstallerProject = 'installer\Klimaatatlas.Installer.wixproj'
$PublishDir = 'src\Klimaatatlas.Gui\bin\Release\net10.0\win-x64\publish'
$CertThumbprint = 'D798C22C68365DAD22AA7422DC147DBCE1F5A7A7'   # Certum-certificaat Watercommunicatie B.V.
$TimestampUrl = 'http://time.certum.pl'
$SignTool = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe'

function Write-Step([string]$Text) { Write-Host "`n=== $Text" -ForegroundColor Cyan }
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Mislukt: $Exe $($Arguments -join ' ') (exitcode $LASTEXITCODE)" }
}

# --- 1. Versie -------------------------------------------------------------------------------
Write-Step 'Versie'
$projectText = [IO.File]::ReadAllText((Resolve-Path $GuiProject))
$currentVersion = [regex]::Match($projectText, '<Version>([^<]+)</Version>').Groups[1].Value
if (-not $Version) { $Version = $currentVersion }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Versie '$Version' is ongeldig; gebruik drie getallen, bv. 2.0.1" }
if ([version]$Version -lt [version]$currentVersion) {
    throw "Versie $Version is lager dan de huidige $currentVersion. Een installer met een lagere versie wordt door Windows geweigerd."
}
if ($Version -ne $currentVersion) {
    foreach ($project in $VersionedProjects) {
        $path = (Resolve-Path $project).Path
        $bytes = [IO.File]::ReadAllBytes($path)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [IO.File]::ReadAllText($path) -replace '<Version>[^<]+</Version>', "<Version>$Version</Version>"
        [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $hasBom))
    }
    Write-Host "Versie aangepast: $currentVersion -> $Version (GUI en CLI)"
} else {
    Write-Host "Versie: $Version (ongewijzigd; verhoog het nummer als deze versie al eens verspreid is)" -ForegroundColor Yellow
}

# --- Ondertekenen mogelijk? -------------------------------------------------------------------
if (-not $NoSign) {
    if (-not (Test-Path $SignTool)) { throw "signtool.exe niet gevonden op '$SignTool'. Installeer de Windows SDK." }
    # The certificate is always in the Windows store, but its key can only be used while SimplySign
    # is logged in. So test it with a test signature on a temporary file.
    $probe = Join-Path ([IO.Path]::GetTempPath()) "klimaatatlas-signprobe-$PID.ps1"
    Set-Content $probe '# probe' -Encoding ascii
    & $SignTool sign /sha1 $CertThumbprint /fd SHA256 /q $probe 2>&1 | Out-Null
    $probeOk = $LASTEXITCODE -eq 0
    Remove-Item $probe -ErrorAction SilentlyContinue
    if (-not $probeOk) {
        throw 'Ondertekenen lukt niet: log in bij SimplySign en probeer het opnieuw (of gebruik -NoSign voor een proefbouw).'
    }
    Write-Host 'Certificaat beschikbaar (SimplySign ingelogd).'
}

# --- 2. Tests ---------------------------------------------------------------------------------
if (-not $SkipTests) {
    Write-Step 'Tests'
    Invoke-Checked dotnet @('test', 'Klimaatatlas.slnx', '-c', 'Release', '--nologo', '-v', 'q')
}

# --- 3. Publiceren (ondertekent Klimaatatlas.exe en de eigen dll's) ------------------------
Write-Step 'App publiceren (win-x64, self-contained)'
$signFiles = if ($NoSign) { 'false' } else { 'true' }
Invoke-Checked dotnet @('publish', $GuiProject, '-p:PublishProfile=Installer-win-x64', "-p:SignPublishedFiles=$signFiles", '--nologo', '-v', 'q')

# --- 4. MSI bouwen ----------------------------------------------------------------------------
Write-Step 'MSI bouwen'
Invoke-Checked dotnet @('build', $InstallerProject, '-c', 'Release', "-p:Version=$Version", '--nologo', '-v', 'q')
$builtMsi = "installer\bin\Release\Klimaatatlas-$Version-x64.msi"
New-Item -ItemType Directory -Force dist | Out-Null
$msi = "dist\Klimaatatlas-$Version-x64.msi"
Copy-Item $builtMsi $msi -Force

# --- 5. MSI ondertekenen en alles controleren ----------------------------------------------
if (-not $NoSign) {
    Write-Step 'MSI ondertekenen'
    Invoke-Checked $SignTool @('sign', '/sha1', $CertThumbprint, '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256', '/d', 'Klimaatatlas', $msi)

    Write-Step 'Handtekeningen controleren'
    $toCheck = @($msi) + (@('Klimaatatlas.exe', 'Klimaatatlas.dll', 'Klimaatatlas.Core.dll') | ForEach-Object { Join-Path $PublishDir $_ })
    foreach ($file in $toCheck) {
        $sig = Get-AuthenticodeSignature $file
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Thumbprint -ne $CertThumbprint) {
            throw "Handtekening niet in orde: $file ($($sig.Status) $($sig.StatusMessage))"
        }
        Write-Host ("OK  {0}" -f (Split-Path $file -Leaf)) -ForegroundColor Green
    }
}

# --- Klaar ------------------------------------------------------------------------------------
$size = '{0:N0} MB' -f ((Get-Item $msi).Length / 1MB)
Write-Host "`nKlaar: $((Resolve-Path $msi).Path) ($size)" -ForegroundColor Green
if ($NoSign) { Write-Host 'Let op: NIET ondertekend - alleen om te testen, niet verspreiden.' -ForegroundColor Yellow }
Write-Host @"

Volgende stappen:
  1. Installeer de MSI zelf even en start Klimaatatlas.
  2. Leg de versie vast:
       git commit -am "Versie $Version"
       git tag v$Version
       git push --follow-tags
"@
