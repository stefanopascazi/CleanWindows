<#
CleanWindows - Aggressive-Safe (Variant B)
Scopo: rimuovere bloatware, disattivare telemetria, rimuovere Copilot, pulire Start Menu e ottimizzare performance.
Modalità consigliata: eseguire prima con -DryRun, poi lanciare senza DryRun.
Requisiti: PowerShell eseguito come Amministratore.
#>

param(
    [switch]$DryRun = $false,
    [switch]$SkipRestorePoint = $false
)

# Config
$LogDir = "$env:ProgramData\CleanWindowsAggressive"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $LogDir ("run_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
function Log { param($msg) $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; $line = "{0}`t{1}" -f $t, $msg; Add-Content -Path $LogFile -Value $line; Write-Output $msg }

# Lists
$RemoveAppxCandidates = @(
    "MicrosoftWindows.Client.WebExperience",    # Widgets / Copilot-related web experience
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxApp",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameCallableUI",
    "Microsoft.People",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.MSPaint",
    "Microsoft.Print3D",
    "Microsoft.SolitaireCollection",
    "Microsoft.Wallet",
    "Microsoft.YourPhone",                       # Phone Link
    "Microsoft.Microsoft3DViewer",
    "Microsoft.549981C3F5F10"                    # common Copilot / suggested package id prefix - best-effort
)

# Keep these
$AppxWhitelist = @(
    "Microsoft.WindowsStore",
    "Microsoft.DesktopAppInstaller",
    "Microsoft.WindowsCalculator"
)

$ServiceDisableList = @(
    'DiagTrack',
    'dmwappushservice'
)

$TaskPatterns = @(
    '\Microsoft\\Windows\\Customer Experience Improvement Program\\*',
    'Microsoft\\Windows\\Application Experience\\*',
    'Microsoft\\Windows\\Maps\\*',
    'Microsoft\\Windows\\Feedback\\*'
)

# Firewall telemetry hosts (example/minimal). Blocking many Microsoft endpoints can break updates, so they're illustrative.
$TelemetryHosts = @('vortex.data.microsoft.com','telemetry.microsoft.com')

# Helper functions
function Ensure-Administrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Esegui PowerShell come Amministratore prima di eseguire questo script."
    }
}

function Create-RestorePoint {
    param([string]$Description = "CleanWindows Aggressive-Safe B Restore")
    if ($SkipRestorePoint) { Log "SkipRestorePoint true => non creo punto di ripristino"; return }
    try {
        if (Get-Command -Name Checkpoint-Computer -ErrorAction SilentlyContinue) {
            if ($DryRun) { Log "[DryRun] Creerei punto di ripristino: $Description"; return }
            Log "Creazione punto di ripristino: $Description"
            Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS"
            Log "Punto di ripristino creato."
        } else {
            Log "Checkpoint-Computer non disponibile; saltando punto di ripristino."
        }
    } catch {
        Log ("Errore creando punto di ripristino: {0}" -f $_)
    }
}

function Backup-RegistryKeys {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    )
    foreach ($k in $keys) {
        $safeName = ($k -replace '[:\\]','_').Trim('_')
        $exportFile = Join-Path $LogDir ("regbak_{0}.reg" -f $safeName)
        if ($DryRun) { Log ("[DryRun] Esporterei chiave registro: {0} -> {1}" -f $k, $exportFile); continue }
        try {
            Log ("Esportando {0} -> {1}" -f $k, $exportFile)
            reg export $k $exportFile /y | Out-Null
            Log ("Export OK: {0}" -f $exportFile)
        } catch {
            Log ("Impossibile esportare {0}: {1}" -f $k, $_)
        }
    }
}

function Save-AppxList {
    $file = Join-Path $LogDir "appx_list_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    if ($DryRun) { Log ("[DryRun] Salverei la lista Appx in {0}" -f $file); return }
    try {
        Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
        Log ("Lista Appx salvata in {0}" -f $file)
    } catch {
        Log ("Errore salvando lista Appx: {0}" -f $_)
    }
}

function Save-ServiceStates {
    $file = Join-Path $LogDir "services_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    if ($DryRun) { Log ("[DryRun] Salverei stato servizi in {0}" -f $file); return }
    try {
        Get-Service | Select-Object Name, Status, StartType | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
        Log ("Stato servizi salvato in {0}" -f $file)
    } catch {
        Log ("Errore salvando stato servizi: {0}" -f $_)
    }
}

function Disable-ServiceSafely {
    param([string]$svcName)
    try {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -eq $svc) { Log ("Servizio non trovato: {0}" -f $svcName); return }
        if ($DryRun) { Log ("[DryRun] Disabiliterei servizio: {0}" -f $svcName); return }
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Log ("Servizio {0} fermato." -f $svcName)
        }
        # Impostare a Disabled
        Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
        Log ("Servizio {0} impostato a Disabled." -f $svcName)
    } catch {
        Log ("Impossibile fermare servizio {0}: {1}" -f $svcName, $_)
    }
}

function Disable-ScheduledTasksByPattern {
    param([string[]]$patterns)
    try {
        $sched = Get-ScheduledTask -ErrorAction SilentlyContinue
        if ($null -eq $sched) { Log "Nessun task pianificato trovato / permessi insufficienti."; return }
        foreach ($p in $patterns) {
            $matched = $sched | Where-Object { ($_.TaskName -like $p) -or ($_.TaskPath -like $p) }
            foreach ($t in $matched) {
                if ($DryRun) { Log ("[DryRun] Disabiliterei task: {0}{1}" -f $t.TaskPath, $t.TaskName); continue }
                try {
                    Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
                    Log ("Task disabilitato: {0}{1}" -f $t.TaskPath, $t.TaskName)
                } catch {
                    Log ("Impossibile disabilitare task {0}{1}: {2}" -f $t.TaskPath, $t.TaskName, $_)
                }
            }
        }
    } catch {
        Log ("Errore enumerando task: {0}" -f $_)
    }
}

function Set-TelemetryToMinimal {
    try {
        if ($DryRun) { Log "[DryRun] Imposterei telemetria a livello minimo"; return }
        $dcKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
        if (-not (Test-Path $dcKey)) { New-Item -Path $dcKey -Force | Out-Null }
        New-ItemProperty -Path $dcKey -Name 'AllowTelemetry' -Value 0 -PropertyType DWord -Force | Out-Null
        Log "Impostato AllowTelemetry = 0"

        $advKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'
        if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force | Out-Null }
        New-ItemProperty -Path $advKey -Name 'DisabledByGroupPolicy' -Value 1 -PropertyType DWord -Force | Out-Null
        Log "Disabilitato Advertising ID via policy"

        # Disabilita alcune impostazioni UX per tutti gli utenti
        $cdm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        if (-not (Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }
        New-ItemProperty -Path $cdm -Name 'DisableCloudOptimizedContent' -Value 1 -PropertyType DWord -Force | Out-Null
        Log "Disabilitato Cloud Optimized Content"

        # Disable Tips and Suggestions (per current user e policy)
        $uiKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        New-ItemProperty -Path $uiKey -Name 'DisablePrelaunch' -Value 1 -PropertyType DWord -Force | Out-Null
    } catch {
        Log ("Errore impostando telemetria: {0}" -f $_)
    }
}

function Remove-AppxIfSafe {
    param([string[]]$candidates, [string[]]$whitelist)
    $removed = @()
    foreach ($pkgName in $candidates) {
        try {
            $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$pkgName*" } -ErrorAction SilentlyContinue
            foreach ($p in $pkgs) {
                if ($whitelist -contains $p.Name) { Log ("Pacchetto nella whitelist, non rimuovere: {0}" -f $p.Name); continue }
                $entry = "{0} - {1}" -f $p.Name, $p.PackageFullName
                if ($DryRun) { Log ("[DryRun] Rimuoverei AppxPackage: {0}" -f $entry); $removed += $entry; continue }
                Log ("Rimuovendo AppxPackage: {0}" -f $entry)
                try {
                    Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                    # Remove provisioning
                    try {
                        $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*$($p.Name)*" }
                        if ($prov) {
                            foreach ($pr in $prov) {
                                Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction SilentlyContinue
                                Log ("Rimosso provisioning: {0}" -f $pr.PackageName)
                            }
                        }
                    } catch {
                        Log ("Impossibile rimuovere provisioning per {0}: {1}" -f $p.Name, $_)
                    }
                    Log ("Rimozione riuscita: {0}" -f $entry)
                    $removed += $entry
                } catch {
                    Log ("Errore rimuovendo {0}: {1}" -f $entry, $_)
                }
            }
        } catch {
            Log ("Errore in Remove-AppxIfSafe per {0}: {1}" -f $pkgName, $_)
        }
    }
    return $removed
}

function Clean-StartMenuStubs {
    # Rimuove collegamenti residui nelle cartelle Start Menu AllUsers e CurrentUser
    $paths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    foreach ($p in $paths) {
        try {
            if ($DryRun) { Log ("[DryRun] Esaminerei Start Menu: {0}" -f $p); continue }
            Get-ChildItem -Path $p -Recurse -Include *.lnk,*.url -ErrorAction SilentlyContinue | Where-Object {
                # heuristics: link pointing to AppX stub folders or to Store
                ($_.FullName -match 'WindowsApps') -or ($_.Name -match 'Xbox|Shopping|Bing|Solitaire|Get Help|Tips')
            } | ForEach-Object {
                Log ("Rimuovo collegamento Start Menu: {0}" -f $_.FullName)
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Log ("Errore pulizia StartMenu {0}: {1}" -f $p, $_)
        }
    }
}

function Remove-Copilot {
    # Tentativo multi-pronged per disabilitare/rimuovere Copilot
    try {
        if ($DryRun) { Log "[DryRun] Disabiliterei Copilot (chiavi di policy, pacchetti, icone)."; return }

        # 1) Policy registry: disabilita Copilot via Policy (se supportato)
        $copKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
        if (-not (Test-Path $copKey)) { New-Item -Path $copKey -Force | Out-Null }
        New-ItemProperty -Path $copKey -Name 'Enable' -Value 0 -PropertyType DWord -Force | Out-Null
        Log "Impostata policy WindowsCopilot Enable=0"

        # 2) Explorer registry tweak per nascondere icona (per versioni dove applicabile)
        $explKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
        if (-not (Test-Path $explKey)) { New-Item -Path $explKey -Force | Out-Null }
        New-ItemProperty -Path $explKey -Name 'HideCopilot' -Value 1 -PropertyType DWord -Force | Out-Null
        Log "Impostato HideCopilot=1 in Policies\\Explorer"

        # 3) Rimuovere appx correlate (heuristic)
        $copCandidates = @('Microsoft.549981C3F5F10*','MicrosoftWindows.Client.WebExperience')
        foreach ($c in $copCandidates) {
            try {
                $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.PackageFullName -like $c } -ErrorAction SilentlyContinue
                foreach ($p in $pkgs) {
                    Log ("Rimozione Copilot-related package: {0}" -f $p.PackageFullName)
                    Remove-AppxPackage -Package $p.PackageFullName -ErrorAction SilentlyContinue
                    # remove provisioning
                    try { Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*$($p.Name)*" } | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue } } catch { }
                }
            } catch {
                Log ("Errore rimuovendo candidate {0}: {1}" -f $c, $_)
            }
        }

        # 4) Rimuovi voci di shell / Taskbar
        try {
            # Rimuove Copilot dal taskbar settings via registry per current user
            $cuExplorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            New-ItemProperty -Path $cuExplorer -Name 'TaskbarMn' -Value 0 -PropertyType DWord -Force | Out-Null
        } catch { }

        Log "Operazioni Copilot tentate (policy + pacchetti + explorer). Riavvia per applicare completamente."
    } catch {
        Log ("Errore Remove-Copilot: {0}" -f $_)
    }
}

function Apply-FirewallBlocklist {
    param([string[]]$hosts)
    foreach ($h in $hosts) {
        try {
            if ($DryRun) { Log ("[DryRun] Creerei regola firewall per bloccare host: {0}" -f $h); continue }
            New-NetFirewallRule -DisplayName ("CleanWindows_Block_{0}" -f $h) -Direction Outbound -Action Block -RemoteAddress $h -Profile Any -Enabled True -ErrorAction SilentlyContinue
            Log ("Regola firewall creata per bloccare: {0}" -f $h)
        } catch {
            Log ("Impossibile creare regola firewall per {0}: {1}" -f $h, $_)
        }
    }
}

function Optimize-Performance {
    try {
        if ($DryRun) { Log "[DryRun] Applicherei ottimizzazioni prestazioni (performance mode, disabilita core parking, ecc.)"; return }
        # Performance mode (Windows 11 PowerModeOveride)
        try { powercfg /setactive SCHEME_MIN | Out-Null; Log "Power scheme impostato a High Performance (SCHEME_MIN)." } catch { }

        # Disabilita Memory Compression (attenzione: può influenzare in alcuni scenari)
        try { Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 1 -Force -ErrorAction SilentlyContinue; Log "DisablePagingExecutive=1" } catch { }

        # Disabilita Search Indexing (opzionale)
        try { Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue; Set-Service -Name 'WSearch' -StartupType Disabled -ErrorAction SilentlyContinue; Log "WSearch disabilitato" } catch { }

        # Disabilita SysMain (Superfetch) se presente
        try { Stop-Service -Name 'SysMain' -Force -ErrorAction SilentlyContinue; Set-Service -Name 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue; Log "SysMain disabilitato" } catch { }

    } catch {
        Log ("Errore Optimize-Performance: {0}" -f $_)
    }
}

# Main
try {
    Ensure-Administrator
    Log "=== CleanWindows Aggressive-Safe Variant B START ==="
    Log ("DryRun = {0}" -f $DryRun)

    Create-RestorePoint -Description 'CleanWindows Aggressive-Safe B snapshot'

    Log "Step: backup configurazioni"
    Backup-RegistryKeys
    Save-AppxList
    Save-ServiceStates

    Log "Step: disabilitazione servizi select"
    foreach ($s in $ServiceDisableList) { Disable-ServiceSafely -svcName $s }

    Log "Step: disabilitazione task pianificati"
    Disable-ScheduledTasksByPattern -patterns $TaskPatterns

    Log "Step: impostazioni telemetria"
    Set-TelemetryToMinimal

    Log "Step: rimozione app candidate (Appx)"
    $removedApps = Remove-AppxIfSafe -candidates $RemoveAppxCandidates -whitelist $AppxWhitelist
    if ($removedApps.Count -gt 0) {
        $removedFile = Join-Path $LogDir ("removed_apps_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $removedApps | Out-File -FilePath $removedFile -Encoding UTF8
        Log ("Lista applicazioni rimosse salvata in {0}" -f $removedFile)
    } else { Log "Nessuna app rimossa." }

    Log "Step: pulizia Start Menu stubs"
    Clean-StartMenuStubs

    Log "Step: rimozione Copilot"
    Remove-Copilot

    Log "Step: blocchi firewall (esempio)"
    Apply-FirewallBlocklist -hosts $TelemetryHosts

    Log "Step: ottimizzazioni prestazioni"
    Optimize-Performance

    Log "=== Operazioni completate. Controlla il log: {0} ===" -f $LogFile
    if ($DryRun) { Log "Eseguito in modalità DryRun: nessuna modifica persistente applicata." }

} catch {
    Log ("Errore generale: {0}" -f $_)
} finally {
    Log "=== CleanWindows Aggressive-Safe Variant B END ==="
}

# Istruzioni rapide:
# 1) Salva questo file e lanciarlo da PowerShell come amministratore.
# 2) Prima esegui: .\aggressive-debloated.ps1 -DryRun
# 3) Controlla i log in %ProgramData%\CleanWindowsAggressive
# 4) Se OK, esegui senza -DryRun
# 5) Se qualcosa va storto: usa il punto di ripristino o importa i .reg creati nella cartella di backup.
