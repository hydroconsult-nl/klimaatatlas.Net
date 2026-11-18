# Een nieuwe versie uitbrengen (Windows-installer)

## Kort: één opdracht

1. Start **SimplySign Desktop** en log in.
2. Voer in PowerShell in de hoofdmap van de repo uit (met het nieuwe versienummer):
   ```bash
   .\build-release.ps1 2.0.1
   ```
3. Installeer `dist\Klimaatatlas-2.0.1-x64.msi` één keer zelf en start de Klimaatatlas.
4. Leg de versie vast; het script toont aan het eind de opdrachten (`git commit`, `git tag`, `git push`).

Het script doet de rest:
* het zet het versienummer in de GUI en de CLI;
* het draait de tests;
* het publiceert de app (self-contained win-x64) en ondertekent `Klimaatatlas.exe` en de eigen dll's;
* het bouwt de MSI (WiX-project `installer\`) en ondertekent die;
* het controleert alle handtekeningen.

Visual Studio is daarvoor niet nodig. Is SimplySign niet ingelogd, dan stopt het script meteen met een melding.

Opties:
* `-NoSign`: een proefbouw zonder ondertekening, niet om te verspreiden;
* `-SkipTests`: de tests overslaan.

De installer is gemaakt met **WiX Toolset 5**: gratis, MS-RL-licentie, als NuGet-pakket, en te bouwen met `dotnet build`. Hij installeert:
* in `C:\Program Files\Watercommunicatie B.V\Klimaatatlas`;
* voor alle gebruikers;
* met een snelkoppeling in het Startmenu en op het bureaublad.

Hij heeft dezelfde *UpgradeCode* als het oude setup-project. Een nieuwe versie vervangt daardoor automatisch de vorige, ook een versie die met `SetupKlimaatAtlas` is geïnstalleerd. Het versienummer moet daarvoor wel elke keer omhoog. Wijzig de UpgradeCode in `installer\Package.wxs` nooit.

De rest van deze handleiding beschrijft de handmatige route via het setup-project in Visual Studio (§1–6) en het **MSIX-pakket** via de wizard (§7). Die heb je normaal niet meer nodig.

---

> **Open in Visual Studio `Klimaatatlas.Installers.slnx`.** Alleen die solution bevat de installer-projecten
> (`SetupKlimaatAtlas` voor de MSI, `SetupKlimaatAtlas2` voor de MSIX). Ze zijn alleen met Visual Studio
> op Windows te bouwen – en het MSI-project alleen vanuit het Visual Studio-venster, niet vanaf de
> opdrachtregel. Voor al het andere werk (bouwen, testen, ook op macOS/Linux) is er `Klimaatatlas.slnx`.

Resultaat: `SetupKlimaatAtlas\Release\SetupKlimaatAtlas.msi` – één bestand, ± 46 MB, met .NET erin
(gebruikers hoeven niets apart te installeren). De MSI zelf én `Klimaatatlas.exe`, `Klimaatatlas.dll` en
`Klimaatatlas.Core.dll` erin zijn ondertekend door **Watercommunicatie B.V.** (Certum), met tijdstempel.
Windows toont bij installeren *"Geverifieerde uitgever: Watercommunicatie B.V."*.

---

## 1. Per nieuwe versie (handmatig, in Visual Studio)

1. **Versienummer ophogen** – op drie plekken hetzelfde nummer, bijv. `2.0.1`:
   * `src/Klimaatatlas.Gui/Klimaatatlas.Gui.csproj` → `<Version>2.0.1</Version>`
   * `src/Klimaatatlas.Cli/Klimaatatlas.Cli.csproj` → `<Version>2.0.1</Version>`
   * Setup-project: selecteer **SetupKlimaatAtlas** in Solution Explorer, **F4** → **Version** → `2.0.1`.
     Visual Studio vraagt of de *ProductCode* mag veranderen: kies **Ja**. Daardoor vervangt de nieuwe
     versie bij installeren automatisch de oude (*RemovePreviousVersions* staat aan).
2. **SimplySign Desktop** starten en inloggen (code uit de app).
3. In Visual Studio: configuratie **Release**, rechtermuisknop op **SetupKlimaatAtlas** → **Rebuild**.
   In de uitvoer hoort te staan:
   ```
   Successfully signed: ...\obj\Release\net10.0\win-x64\apphost.exe
   Successfully signed: ...\obj\Release\net10.0\win-x64\Klimaatatlas.dll
   Successfully signed: ...\Klimaatatlas.Core\bin\Release\net10.0\Klimaatatlas.Core.dll
   Packaging file 'Klimaatatlas.exe'...            (en ± 230 andere bestanden)
   Successfully signed: ...\SetupKlimaatAtlas\Release\SetupKlimaatAtlas.msi
   ```
4. **Controleren** (zie §3) en de MSI één keer zelf installeren en starten via het Startmenu.
5. **Committen en taggen**, zodat je later weet welke code bij welke MSI hoort:
   ```bash
   git commit -am "Versie 2.0.1"
   ```
   ```bash
   git tag v2.0.1
   ```
   ```bash
   git push --follow-tags
   ```
6. **Verspreiden**: alleen `SetupKlimaatAtlas.msi`. Eventueel als *Release* op GitHub
   (*Releases → Draft a new release*, tag `v2.0.1`, MSI als bijlage).

De MSI zelf gaat **niet** in git (het is build-uitvoer).

---

## 2. Hoe het is ingericht (en waarom)

| Onderdeel | Waar | Wat het doet |
| --- | --- | --- |
| Publicatieprofiel | `src/Klimaatatlas.Gui/Properties/PublishProfiles/Installer-win-x64.pubxml` | Publiceert de app *self-contained* (met .NET) en alleen voor 64-bit Windows, zodat er geen bibliotheken voor Linux/macOS meekomen. |
| Ondertekenen van exe en dll's | `src/Klimaatatlas.Gui/Klimaatatlas.Gui.csproj`, target `SignPublishedFiles` | Ondertekent `Klimaatatlas.exe`, `Klimaatatlas.dll` en `Klimaatatlas.Core.dll` zodra de lijst met te publiceren bestanden bekend is – precies de bestanden die het setup-project inpakt. Draait alleen bij Release + `win-x64`, dus niet bij gewoon bouwen of debuggen. |
| Setup-project | `SetupKlimaatAtlas/SetupKlimaatAtlas.vdproj` | Pakt **Publish Items** van `Klimaatatlas.Gui` (met het profiel hierboven) in een MSI, met snelkoppelingen in het Startmenu en op het bureaublad. Geen `.NET`-voorwaarde en geen `setup.exe`: .NET zit al in de app. |
| Ondertekenen van de MSI | Setup-project → eigenschap **PostBuildEvent** | Roept `signtool` aan op de gebouwde MSI (`$(BuiltOuputPath)`, met die spelfout – zo heet de variabele in setup-projecten). |

Beide ondertekenstappen gebruiken dezelfde instellingen:

* certificaat: **vingerafdruk** `D798C22C68365DAD22AA7422DC147DBCE1F5A7A7` (Watercommunicatie B.V., Certum EV,
  geldig t/m **20 november 2027**). Met de vingerafdruk (`/sha1`) wordt nooit per ongeluk een ander
  certificaat gekozen; gebruik dus niet `/a`.
* tijdstempel: `http://time.certum.pl`. Daardoor blijft de handtekening geldig, ook na het verlopen van
  het certificaat.
* signtool: `C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe`.

Ondertekenen overslaan (bijv. op een pc zonder het certificaat): `dotnet publish ... -p:SignPublishedFiles=false`.

---

## 3. Controleren

Handtekening van de MSI:

```bash
powershell -c "Get-AuthenticodeSignature 'SetupKlimaatAtlas\Release\SetupKlimaatAtlas.msi' | Format-List Status, SignerCertificate, TimeStamperCertificate"
```

Goed is: `Status : Valid`, `SignerCertificate` met `CN=Watercommunicatie B.V.`, en een `TimeStamperCertificate`.

Handtekeningen van de bestanden **in** de MSI (pakt de MSI uit naar een tijdelijke map, installeert niets):

```bash
powershell -c "$x=\"$env:TEMP\msi-check\"; Remove-Item $x -Recurse -Force -EA 0; Start-Process msiexec -ArgumentList \"/a `\"$PWD\SetupKlimaatAtlas\Release\SetupKlimaatAtlas.msi`\" /qn TARGETDIR=`\"$x`\"\" -Wait; Get-ChildItem $x -Recurse -Include Klimaatatlas*.exe,Klimaatatlas*.dll | Get-AuthenticodeSignature | Format-Table Status, Path -AutoSize"
```

Alle drie moeten `Valid` zijn.

---

## 4. Eenmalig per computer

* **Visual Studio** met de workload *.NET desktop development* en de extensie
  *Microsoft Visual Studio Installer Projects* (voor het setup-project).
* **Windows SDK** (voor `signtool.exe`); wordt meestal met Visual Studio geïnstalleerd. Staat het in een
  andere versiemap dan `10.0.22621.0`, pas dan het pad aan in de csproj (`SignToolPath`) en in de
  PostBuildEvent van het setup-project.
* **SimplySign Desktop** van Certum, ingelogd met je account. Het certificaat verschijnt dan in de
  certificaatopslag van Windows.
* Geen zelfgemaakte certificaten met dezelfde naam in de opslag laten staan (bijv. het eerder door
  Visual Studio aangemaakte `CN=HydroConsult`): verwijder ze via `certmgr.msc` → *Persoonlijk → Certificaten*.

---

## 5. Problemen en oplossingen

| Melding / symptoom | Oorzaak | Oplossing |
| --- | --- | --- |
| *Uitgever: onbekend* bij installeren | Ondertekend met een zelfgemaakt certificaat, of niet ondertekend | Controleer met §3 welk certificaat is gebruikt; moet Watercommunicatie B.V. zijn. |
| `SignTool Error: File not found:` (zonder bestandsnaam) | Verkeerde variabele in de PostBuildEvent, bijv. `$(TargetPath)` | In setup-projecten is het `$(BuiltOuputPath)`. |
| `No certificates were found that met all the given criteria` | SimplySign niet ingelogd, of certificaat verlopen | SimplySign Desktop starten en inloggen. |
| `Invalid or unspecified target for shortcut ...` | Snelkoppeling verwijst naar een verwijderde projectuitvoer | In het setup-project: *View → File System*, de snelkoppeling verwijderen en opnieuw maken via *Create Shortcut to Publish Items*. |
| MSI is maar enkele honderden KB | Setup-project gebruikt *Primary output* i.p.v. *Publish Items* | *Publish Items* van Klimaatatlas.Gui met profiel `Installer-win-x64.pubxml`. |
| Installatie weigert: .NET ontbreekt | Er staat een *.NET Core*-voorwaarde in het setup-project | *View → Launch Conditions* → verwijderen (.NET zit in de app). |
| `Skipped Rebuild: Project: SetupKlimaatAtlas` | Setup-project staat in *Configuration Manager* niet aangevinkt om te bouwen | *Build → Configuration Manager* → bij Release het vinkje *Build* aanzetten. |
| `Expected 3 files to sign, found: ...` | Bestandsnamen van de app zijn veranderd | Pas de lijst in target `SignPublishedFiles` in `Klimaatatlas.Gui.csproj` aan. |

---

## 6. Als het certificaat verloopt (20 november 2027)

Nieuw certificaat aanvragen bij Certum, inloggen in SimplySign, en de **vingerafdruk** opzoeken:

```bash
powershell -c "Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-Table Thumbprint, Subject, NotAfter"
```

Vervang de oude vingerafdruk op twee plekken: `SignCertificateThumbprint` in
`src/Klimaatatlas.Gui/Klimaatatlas.Gui.csproj` en `/sha1 ...` in de PostBuildEvent van het setup-project.
Eerder uitgebrachte MSI's blijven geldig dankzij de tijdstempel.

---

## 7. Alternatief: MSIX-pakket via de wizard

Naast de MSI kan de app als **MSIX** worden verpakt. Het ondertekenen gaat dan via een wizard in Visual
Studio, zonder signtool-regels. Gebruikers dubbelklikken het `.msix`-bestand en zien
*"Uitgever: Watercommunicatie B.V."* met een Installeren-knop; verwijderen laat niets achter.

> Deze route is (nog) niet uitgevoerd in dit project; menunamen kunnen in nieuwere Visual Studio-versies
> iets afwijken. Houd de MSI als terugval: sommige organisaties blokkeren MSIX-installaties buiten de
> Microsoft Store – vraag het na bij de IT van de klant.

**Benodigd:** in de Visual Studio Installer, onder de workload *.NET desktop development*, het optionele
onderdeel **MSIX Packaging Tools**. (Het zoekveld bij *Individual components* vindt het niet; het staat
alleen onder de workload.)

### Eenmalig inrichten

> In deze repository is dit al gedaan: het verpakkingsproject heet **`SetupKlimaatAtlas2`** en staat in
> `Klimaatatlas.Installers.slnx` (altijd als x64). Stappen 1–3 zijn hier ter naslag; ga verder bij
> *Per nieuwe versie*.

1. **Verpakkingsproject toevoegen** – rechtermuisknop op de solution → *Add* → *New Project…* →
   **Windows Application Packaging Project**, naam `SetupKlimaatAtlas2` (of een betere naam), minimumversie
   *Windows 10, version 1809*. Visual Studio voegt daarbij de platforms ARM, ARM64, x64 en x86 aan de
   solution toe; laat alleen *Any CPU* staan en zet het verpakkingsproject in *Configuration Manager*
   op **x64** (anders wordt de app als 32-bit gebouwd).
2. **App koppelen**
   * In `SetupKlimaatAtlas2`: rechtermuisknop op **Dependencies** → *Add Project Reference* →
     **Klimaatatlas.Gui**.
   * Onder *Dependencies → Applications*: rechtermuisknop op *Klimaatatlas.Gui* → **Set as Entry Point**.
   * *Build → Configuration Manager*: platform van `SetupKlimaatAtlas2` op **x64**.
   * In `src/Klimaatatlas.Gui/Klimaatatlas.Gui.csproj`, in de eerste `<PropertyGroup>`, zodat .NET in het
     pakket meegaat (een MSIX installeert .NET niet zelf):
     ```xml
     <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
     <SelfContained Condition="'$(RuntimeIdentifier)' != ''">true</SelfContained>
     ```
     en in `src/Klimaatatlas.Core/Klimaatatlas.Core.csproj` ook `<RuntimeIdentifiers>win-x64</RuntimeIdentifiers>`
     (anders: fout *NETSDK1047 … doesn't have a target for 'net10.0/win-x64'*).
3. **Manifest** – dubbelklik `Package.appxmanifest`:
   * *Application*: Display name `Klimaatatlas`.
   * *Packaging*: Publisher display name `Watercommunicatie B.V.`; bij **Publisher** →
     **Choose Certificate…** → *Select from Store* → **Watercommunicatie B.V.** Zo komt de uitgever in het
     pakket exact overeen met het certificaat; anders weigert Windows het pakket.
   * *Visual Assets*: bij *Asset Generator* een logo kiezen (PNG, minstens 400×400) → *Generate*.
4. **Proef** – rechtermuisknop op `SetupKlimaatAtlas2` → *Deploy*; de app verschijnt in het Startmenu.

### Per nieuwe versie

1. SimplySign Desktop starten en inloggen.
2. Rechtermuisknop op `SetupKlimaatAtlas2` → **Publish** → **Create App Packages…**
3. **Sideloading** kiezen (niet de Microsoft Store); *Enable automatic updates* uit, tenzij er een
   netwerkschijf of website voor updates is.
4. **Signing method**: *Yes, select a certificate* → *Select From Store* → **Watercommunicatie B.V.**;
   *Timestamp server URL* `http://time.certum.pl`.
5. Versie **Automatically increment**; architectuur alleen **x64**, configuratie *Release*;
   *Generate app bundle*: **Never**.
6. **Create** – SimplySign vraagt om bevestiging.

De wizard maakt een map als `AppPackages\SetupKlimaatAtlas2_2.0.1.0_x64_Test\`. Verspreid **alleen het
`.msix`-bestand**; de scripts (`Install.ps1`) en de map `Dependencies` zijn alleen nodig bij een
zelfgemaakt testcertificaat. De map `AppPackages` gaat niet in git.

Controleren:

```bash
powershell -c "Get-AuthenticodeSignature (Get-ChildItem AppPackages -Recurse -Filter *.msix | Select-Object -Last 1).FullName | Format-List Status, SignerCertificate, TimeStamperCertificate"
```

Goed is `Status : Valid` met `CN=Watercommunicatie B.V.` en een tijdstempel.

Aandachtspunten:

* Fout dat de uitgever niet overeenkomt met het certificaat → in het manifest het certificaat opnieuw
  kiezen (stap 3).
* Een MSIX-app bewaart zijn instellingen (zoals de laatst gebruikte config) in een eigen afgeschermde map;
  geopackages en configbestanden lezen en schrijven werkt gewoon.
* Bij een nieuw certificaat (§6): in het manifest opnieuw **Choose Certificate…**, en in de wizard het
  nieuwe certificaat kiezen.

---

## Wat we bewust níet gebruiken

* **ClickOnce** – levert altijd een map met `setup.exe`, een manifest en versiemappen op, geen enkel bestand.
* **`setup.exe` van het setup-project** – installeert alleen ontbrekende onderdelen (zoals .NET), die hier al
  in de app zitten; en hij wordt niet ondertekend.
