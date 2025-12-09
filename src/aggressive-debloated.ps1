<#
.SYNOPSIS
  CleanWindows - Aggressive ma con tutele: disattiva telemetria, widget/mete o-app comuni, task di tracking, servizi non critici.
.DESCRIPTION
  Esegue backup, crea punto di ripristino, disabilita servizi e task, rimuove app UWP non critiche e alcune feature di telemetria.
.PARAMETER DryRun
  Se true non apporta modifiche, mostra solo le azioni.
.NOTES
  Richiede powershell eseguito come Administrator.
#>

param(
    [switch]$DryRun = $false,
    [switch]$SkipRestorePoint = $false
)

#region -- configurazione --
$LogDir = "$env:ProgramData\CleanWindowsAggressive"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}
$LogFile = Join-Path $LogDir "run_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
function Log { param($msg) $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; $line = "$t`t$msg"; Add-Content -Path $LogFile -Value $line; Write-Output $msg }

# Lista di app / pacchetti che vogliamo rimuovere se presenti (non core). Aggiungi/rimuovi secondo necessità.
$RemoveAppxCandidates = @(
    "MicrosoftWindows.Client.WebExperience",   # Widgets / Meteo
    "Microsoft.BingWeather",                  # vecchio package meteo
    "Microsoft.GetHelp", 
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxApp",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameCallableUI",
    "Microsoft.People",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo"
)

# White-list per NON rimuovere assolutamente
$AppxWhitelist = @(
    "Microsoft.WindowsCalculator",
    "Microsoft.WindowsStore",
    "Microsoft.DesktopAppInstaller"
)

# Servizi considerati non critici ma utili da disabilitare
$ServiceDisableList = @(
    "DiagTrack",                    # Connected User Experiences and Telemetry
    "dmwappushservice",             # WNS push
    "dmwappushsvc",                 # possible alias
    "DiagTrack"                     # sometimes duplicate naming
)

# Registry keys da esportare e modificare per telemetria/privacy
$RegistryBackups = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
    "HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack"
)

# Task scheduler patterns da disabilitare
$TaskPatterns = @(
    "DiagTrack*",
    "Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "Microsoft\Windows\Customer Experience Improvement Program\*",
    "Microsoft\Windows\Autochk\*",
    "Microsoft\Windows\Maps\*",
    "Microsoft\Windows\Feedback\*"
)
#endregion

#region -- helper functions --
function Ensure-Administrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Esegui PowerShell come Amministratore prima di eseguire questo script."
    }
}

function Create-RestorePoint {
    param([string]$Description = "CleanWindows Aggressive Backup")
    if ($SkipRestorePoint) { Log "SkipRestorePoint true => non creo punto di ripristino"; return }
    try {
        # Checkpoint-Computer disponibile su client/desktop
        if (Get-Command -Name Checkpoint-Computer -ErrorAction SilentlyContinue) {
            if ($DryRun) { Log "[DryRun] Creerei punto di ripristino: $Description"; return }
            Log "Creazione punto di ripristino: $Description"
            Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS"
            Log "Punto di ripristino creato."
        } else {
            Log "Checkpoint-Computer non disponibile sulla macchina; saltando punto di ripristino."
        }
    } catch {
        Log "Errore creando punto di ripristino:"
    }
}

function Backup-RegistryKeys {
    foreach ($key in $RegistryBackups) {
        $safeName = ($key -replace '[:\\]','_').Trim('_')
        $exportFile = Join-Path $LogDir "regbak_$safeName.reg"
        if ($DryRun) {
            Log "[DryRun] Esporterei chiave registro: $key -> $exportFile"
        } else {
            try {
                Log "Esportando $key -> $exportFile"
                reg export $key $exportFile /y | Out-Null
                Log "Export OK: $exportFile"
            } catch {
                Log ("Impossibile esportare {0}: {1}" -f $key, $_)
            }
        }
    }
}

function Disable-ServiceSafely {
    param([string]$svcName)
    if ($DryRun) { Log "[DryRun] Disabiliterei servizio: $svcName"; return }
    try {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            Log "Servizio non trovato: $svcName"
            return
        }
        # Stop only if running and service is stoppable
        if ($svc.Status -ne 'Stopped') {
            try {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                Log "Servizio $svcName fermato."
            } catch {
                Log ("Impossibile fermare servizio {0}: {1}" -f $svcName, $_)
            }
        }
        Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
        Log "Servizio $svcName impostato a Disabled."
    } catch {
        Log "Errore durante Disable-ServiceSafely($svcName): $_"
    }
}

function Disable-ScheduledTasksByPattern {
    param([string[]]$patterns)
    $sched = Get-ScheduledTask -ErrorAction SilentlyContinue
    if ($null -eq $sched) { Log "Nessun task pianificato trovato / permessi insufficienti."; return }
    foreach ($p in $patterns) {
        $matched = $sched | Where-Object { $_.TaskName -like $p -or $_.TaskPath -like $p }
        foreach ($t in $matched) {
            if ($DryRun) {
                Log "[DryRun] Disabiliterei task: $($t.TaskPath)$($t.TaskName)"
            } else {
                try {
                    Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
                    Log "Task disabilitato: $($t.TaskPath)$($t.TaskName)"
                } catch {
                    Log "Impossibile disabilitare task $($t.TaskPath)$($t.TaskName): $_"
                }
            }
        }
    }
}

function Remove-AppxIfSafe {
    param([string[]]$candidates, [string[]]$whitelist)
    $removed = @()
    foreach ($pkgName in $candidates) {
        try {
            # Ricerca pacchetti installati matching
            $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$pkgName*" } -ErrorAction SilentlyContinue
            foreach ($p in $pkgs) {
                if ($whitelist -contains $p.Name) {
                    Log "Pacchetto nella whitelist, non rimuovere: $($p.Name)"
                    continue
                }
                $entry = "$($p.Name) - $($p.PackageFullName)"
                if ($DryRun) {
                    Log "[DryRun] Rimuoverei AppxPackage: $entry"
                    $removed += $entry
                } else {
                    Log "Rimuovendo AppxPackage: $entry"
                    try {
                        Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
                        # Tentativo di rimuovere anche provisioning (affinché non ricompaia per nuovi utenti)
                        try {
                            $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*$($p.Name)*" }
                            if ($prov) {
                                foreach ($pr in $prov) {
                                    Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction SilentlyContinue
                                    Log "Rimosso provisioning: $($pr.PackageName)"
                                }
                            }
                        } catch {
                            Log "Impossibile rimuovere provisioning per $($p.Name): $_"
                        }
                        Log "Rimozione riuscita: $entry"
                        $removed += $entry
                    } catch {
                        Log ("Errore rimuovendo {0}: {1}" -f $entry, $_)
                    }
                }
            }
        } catch {
            Log ("Errore in Remove-AppxIfSafe per {0}: {1}" -f $pkgName, $_)
        }
    }
    return $removed
}

function Set-TelemetryToMinimal {
    # Imposta alcune chiavi note a valore minimo. Non tutte le chiavi sono garantite.
    $actions = @()
    $dcKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    if ($DryRun) {
        Log "[DryRun] Imposterei le chiavi di telemetria a livello minimo in $dcKey"
        return
    }
    try {
        if (-not (Test-Path $dcKey)) {
            New-Item -Path $dcKey -Force | Out-Null
        }
        New-ItemProperty -Path $dcKey -Name "AllowTelemetry" -Value 0 -PropertyType DWord -Force | Out-Null
        Log "Impostato AllowTelemetry = 0"
        # Disabilita Advertising ID per tutti gli utenti via policy (se applicabile)
        $advKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force | Out-Null }
        New-ItemProperty -Path $advKey -Name "DisabledByGroupPolicy" -Value 1 -PropertyType DWord -Force | Out-Null
        Log "Disabilitato Advertising ID via policy."
    } catch {
        Log "Errore impostando telemetria: $_"
    }
}

function Apply-FirewallBlocklist {
    param([string[]]$addresses)
    foreach ($addr in $addresses) {
        if ($DryRun) {
            Log "[DryRun] Creerei regola firewall per bloccare: $addr"
        } else {
            try {
                New-NetFirewallRule -DisplayName "CleanWindows_Block_$addr" -Direction Outbound -Action Block -RemoteAddress $addr -Profile Any -Enabled True -ErrorAction Stop
                Log "Regola firewall creata per bloccare: $addr"
            } catch {
                Log ("Impossibile creare regola firewall per {0}: {1}" -f $addr, $_)
            }
        }
    }
}
#endregion

# Main
try {
    Ensure-Administrator
    Log "=== CleanWindows AggressiveSafe START ==="
    Log "DryRun = $DryRun"
    Create-RestorePoint -Description "CleanWindows AggressiveSafe snapshot"

    Log "Step: backup chiavi di registro"
    Backup-RegistryKeys

    Log "Step: disabilitazione servizi selezionati"
    foreach ($s in $ServiceDisableList) {
        Disable-ServiceSafely -svcName $s
    }

    Log "Step: disabilitazione task pianificati (pattern)"
    Disable-ScheduledTasksByPattern -patterns $TaskPatterns

    Log "Step: impostazioni telemetria"
    Set-TelemetryToMinimal

    Log "Step: rimozione app candidate"
    $removedApps = Remove-AppxIfSafe -candidates $RemoveAppxCandidates -whitelist $AppxWhitelist
    if ($removedApps.Count -gt 0) {
        $removedFile = Join-Path $LogDir "removed_apps_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $removedApps | Out-File -FilePath $removedFile -Encoding UTF8
        Log "Lista applicazioni rimosse salvata in $removedFile"
    } else {
        Log "Nessuna app rimossa."
    }

    Log "Step: blocchi firewall (telemetria Microsoft: esempio di indirizzi pubblici) - attenzione: qui mettiamo solo esempi. Modifica a piacere."
    # Nota: bloccare IP Microsoft può avere impatti su aggiornamenti/servizi. Qui solo regola d'esempio (non bloccare tutto).
    $sampleBlockList = @("13.107.4.0/24","13.107.128.0/22")  # Esempio — NON è esaustivo.
    Apply-FirewallBlocklist -addresses $sampleBlockList

    Log "=== Operazioni completate. Controlla il log: $LogFile ==="
    if ($DryRun) { Log "Eseguito in modalità DryRun: nessuna modifica persistente applicata." }
} catch {
    Log "Errore generale: $_"
} finally {
    Log "=== CleanWindows AggressiveSafe END ==="
}
