<#
    WindowsPulito_Advanced.ps1
    Descrizione: Script modulare per pulizia/ottimizzazione Windows.
    Modalita: Balanced (B), Aggressive (A), Gaming (G), Safe (S), Restore (R)
    NOTE:
      - Eseguire come Amministratore.
      - Salvare con codifica UTF-8.
      - Alcune funzioni (checkpoint) potrebbero fallire se Protezione Sistema disabilitata.
#>

#region Utility & Setup
Clear-Host

$scriptName = "clean.ps1"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$logDir = Join-Path $scriptDir "..\data"

if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$logFile = Join-Path $logDir ("log_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Function Log {
    param([string]$Text)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Text"
    Add-Content -Path $logFile -Value $entry
    Write-Host $Text
}

# Check admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRORE: esegui lo script come Amministratore." -ForegroundColor Red
    Log "Uscita: non eseguito come amministratore."
    Pause
    exit 1
}

Log "Avvio script."

# Ensure scripts allowed for this session
Try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Log "Set-ExecutionPolicy Process: Bypass"
} Catch {
    Log "Impossibile impostare ExecutionPolicy per la sessione: $_"
}
#endregion

#region Backup / Restore helpers
$backupDir = Join-Path $logDir "backup"
if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory | Out-Null }

Function Create-RestorePoint {
    Log "Creazione punto di ripristino (se supportato)..."
    Try {
        # Checkpoint-Computer requires system protection enabled and account privileges
        Checkpoint-Computer -Description "WindowsPulito_PreChange" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Log "Punto di ripristino creato con successo."
    } Catch {
        Log "Impossibile creare punto di ripristino: $_. Verrà effettuato backup registro come fallback."
    }
}

Function Backup-RegistryKeys {
    Log "Backup chiavi di registro importanti..."
    $keys = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    )
    foreach ($k in $keys) {
        $safeName = ($k -replace '[:\\]','_').TrimStart('_')
        $exportPath = Join-Path $backupDir ("regbackup_{0}.reg" -f $safeName)
        Try {
            reg export $k $exportPath /y 2>$null
            Log "  Backup $k -> $exportPath"
        } Catch {
            Log "  Impossibile esportare ${k}: $_"
        }
    }
}

Function Save-ServiceStates {
    Log "Salvataggio stato servizi..."
    $svcFile = Join-Path $backupDir "services_state.json"
    $services = Get-Service | Select-Object Name,Status,StartType
    $services | ConvertTo-Json | Out-File -FilePath $svcFile -Encoding UTF8
    Log "  Stato servizi salvato in $svcFile"
}
#endregion

#region Core Actions
Function Remove-Bloatware {
    param([switch]$Aggressive)

    Log "Rimozione bloatware (Aggressive = $Aggressive)..."
    # Lista comune (balanced). Aggressive aggiunge altre app.
    $apps = @(
        "*3DBuilder*",
        "*CandyCrush*",
        "*MicrosoftSolitaireCollection*",
        "*Xbox*",
        "*Netflix*",
        "*Spotify*"
    )
    if ($Aggressive) {
        $apps += @(
            "*Facebook*",
            "*Twitter*",
            "*Minecraft*",
            "*MarchofEmpires*",
            "*DisneyMagicKingdoms*",
            "*HiddenCity*"
        )
    }

    foreach ($app in $apps) {
        Try {
            Log "  Tentativo rimozione: $app"
            Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        } Catch {
            Log "    Errore rimozione ${app}: $_"
        }
    }
    Log "Rimozione bloatware completata."
    Write-Host ""
}

Function Reduce-Telemetry {
    param([switch]$Balanced)

    Log "Riduzione telemetria (Balanced = $Balanced)..."
    Try {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
        if ($Balanced) {
            # Balanced: set to basic (1) to avoid breaking update scenarios
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Type DWord
            Log "  AllowTelemetry = 1 (Balanced)"
        } else {
            # Aggressive: set to 0
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord
            Log "  AllowTelemetry = 0 (Aggressive)"
        }
    } Catch {
        Log "  Errore impostazione telemetria: $_"
    }

    # ContentDelivery Manager user keys (affect suggestions)
    Try {
        $cdm = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        New-Item -Path $cdm -Force | Out-Null
        Set-ItemProperty -Path $cdm -Name "ContentDeliveryAllowed" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $cdm -Name "OemPreInstalledAppsEnabled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $cdm -Name "SilentInstalledAppsEnabled" -Value 0 -ErrorAction SilentlyContinue
        Log "  ContentDeliveryManager impostato."
    } Catch {
        Log "  Errore ContentDeliveryManager: $_"
    }

    # Disable web search in Balanced mode (set policy)
    Try {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1 -Type DWord
        Log "  DisableWebSearch = 1"
    } Catch {
        Log "  Errore DisableWebSearch: $_"
    }

    # Stop telemetry services only in aggressive mode
    if (-not $Balanced) {
        $svcList = @("DiagTrack","dmwappushservice")
        foreach ($s in $svcList) {
            Try {
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
                Log "  Servizio $s arrestato e disabilitato."
            } Catch {
                Log "  Errore gestione servizio ${s}: $_"
            }
        }
    } else {
        Log "  Balanced: non si modificano servizi telemetria critici."
    }
}

Function Clean-Temp {
    Log "Pulizia file temporanei..."
    Try {
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Log "  TEMP utente: tentativo eseguito."
    } Catch {
        Log "  Errore pulizia TEMP utente: $_"
    }
    Try {
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Log "  C:\Windows\Temp: tentativo eseguito."
    } Catch {
        Log "  Errore pulizia C:\Windows\Temp: $_"
    }
}

Function Optimize-SysMain {
    param([switch]$Disable)

    if ($Disable) {
        Log "Disattivazione SysMain (Superfetch)..."
        Try {
            Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
            Log "  SysMain disattivato."
        } Catch {
            Log "  Errore disattivazione SysMain: $_"
        }
    } else {
        Log "Nessuna modifica a SysMain."
    }
}

Function Clean-StartupEntries {
    Log "Pulizia voci di avvio approvate per l'utente corrente..."
    Try {
        cmd /c "reg delete \"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run\" /va /f" | Out-Null
        Log "  Voci StartupApproved\Run rimosse (se presenti)."
    } Catch {
        Log "  Errore cancellazione voci avvio: $_"
    }
}
#endregion

#region Restore function
Function Restore-Defaults {
    Log "Avvio procedura di ripristino configurazioni (tentativo)..."

    # Restore registry from backups if present
    $regFiles = Get-ChildItem -Path $backupDir -Filter "regbackup_*.reg" -ErrorAction SilentlyContinue
    foreach ($f in $regFiles) {
        Try {
            reg import $f.FullName 2>$null
            Log "  Importato $($f.FullName)"
        } Catch {
            Log "  Errore import $($f.FullName): $_"
        }
    }

    # Re-enable common services
    $servicesToEnable = @("DiagTrack","dmwappushservice","SysMain")
    foreach ($s in $servicesToEnable) {
        Try {
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service -Name $s -ErrorAction SilentlyContinue
            Log "  Tentativo riabilitazione servizio $s"
        } Catch {
            Log "  Errore riabilitazione ${s}: $_"
        }
    }

    # Telemetry default (set to 1 to be safe)
    Try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Log "  AllowTelemetry impostato a 1 (default consigliato)."
    } Catch {
        Log "  Impossibile settare AllowTelemetry: $_"
    }

    Log "Ripristino completato (alcune modifiche, come la reinstallazione di app UWP, richiedono azioni manuali o Microsoft Store)."
}
#endregion

#region Menu & Flow
Function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   OTTIMIZZAZIONE DI SISTEMA - MENU" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "S - Safe (solo pulizia sicura, nessuna rimozione d'app o servizi)" -ForegroundColor Yellow
    Write-Host "B - Balanced (rimozione moderata, telemetria ridotta, ottimizzazioni sicure)" -ForegroundColor Green
    Write-Host "A - Aggressive (rimozione estesa, telemetria disabilitata, servizi stoppati)" -ForegroundColor Red
    Write-Host "G - Gaming (ottimizzazioni orientate prestazioni)" -ForegroundColor Magenta
    Write-Host "R - Restore (ripristina impostazioni da backup)" -ForegroundColor Cyan
    Write-Host "Q - Esci" -ForegroundColor DarkGray
    Write-Host ""
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Scegli un'opzione (S/B/A/G/R/Q)"
    switch ($choice.ToUpper()) {
        "S" {
            Log "Selezione: Safe"
            Create-RestorePoint
            Backup-RegistryKeys
            Save-ServiceStates
            Clean-Temp
            Clean-StartupEntries
            Write-Host "`nSafe mode completata. Riavvia il sistema se desideri." -ForegroundColor Green
            Log "Safe mode completata."
            Pause
        }
        "B" {
            Log "Selezione: Balanced"
            Create-RestorePoint
            Backup-RegistryKeys
            Save-ServiceStates
            Remove-Bloatware -Aggressive:$false
            Reduce-Telemetry -Balanced:$true
            Clean-Temp
            Optimize-SysMain -Disable:$true
            Clean-StartupEntries
            Write-Host "`nBalanced ottimizzazioni completate. Riavvia il sistema." -ForegroundColor Green
            Log "Balanced completato."
            Pause
        }
        "A" {
            Write-Host "ATTENZIONE: modalità Aggressive può rimuovere app e disabilitare servizi." -ForegroundColor Red
            $confirmA = Read-Host "Vuoi procedere? (S o N)"
            if ($confirmA.ToUpper() -eq "S") {
                Log "Selezione: Aggressive"
                Create-RestorePoint
                Backup-RegistryKeys
                Save-ServiceStates
                Remove-Bloatware -Aggressive:$true
                Reduce-Telemetry -Balanced:$false
                Clean-Temp
                Optimize-SysMain -Disable:$true
                Clean-StartupEntries
                Write-Host "`nAggressive completata. Riavvia il sistema." -ForegroundColor Green
                Log "Aggressive completata."
            } else {
                Write-Host "Operazione Aggressive annullata." -ForegroundColor Yellow
                Log "Aggressive annullata dall'utente."
            }
            Pause
        }
        "G" {
            Log "Selezione: Gaming"
            Create-RestorePoint
            Backup-RegistryKeys
            Save-ServiceStates
            # Gaming: rimozione leggera + tweak rete/latency suggestions
            Remove-Bloatware -Aggressive:$false
            Reduce-Telemetry -Balanced:$true
            Clean-Temp
            # Esempio tweak: impostare priorita processo (nota: non persistente dopo riavvio)
            Try {
                # set power plan to high performance if available
                $plan = powercfg -list | Select-String -Pattern "High performance" -SimpleMatch
                if ($plan) {
                    $guid = ($plan -split '\s+')[3]
                    powercfg -setactive $guid
                    Log "  Power plan impostato su High performance"
                }
            } Catch {
                Log "  Impossibile cambiare power plan: $_"
            }
            Write-Host "`nGaming tweaks applicati. Riavvia il sistema." -ForegroundColor Green
            Log "Gaming completata."
            Pause
        }
        "R" {
            Log "Selezione: Restore"
            Restore-Defaults
            Write-Host "`nRipristino tentato. Verifica i backup in $backupDir" -ForegroundColor Green
            Log "Restore eseguito."
            Pause
        }
        "Q" {
            Log "Uscita dal menu."
            Pause
            exit
        }
        Default {
            Write-Host "Opzione non valida. Riprova." -ForegroundColor Yellow
        }
    }
}
#endregion

Write-Host "`nScript terminato. Log in: $logFile" -ForegroundColor Cyan
Log "Script terminato."
Pause