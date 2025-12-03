<#
    launcher.ps1
    Menu principale per selezionare quale script eseguire.
    Deve essere eseguito come amministratore.
#>

# Controllo privilegi admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Esegui come amministratore!" -ForegroundColor Red
    Pause
    exit
}

# Percorso della cartella contenente gli script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Run-Script {
    param([string]$ScriptName)
    $fullPath = Join-Path $scriptDir $ScriptName
    if (Test-Path $fullPath) {
        Write-Host "`nEsecuzione $ScriptName..." -ForegroundColor Cyan
        try {
            PowerShell -NoProfile -ExecutionPolicy Bypass -File $fullPath
        } catch {
            Write-Host "Errore durante l'esecuzione: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "$ScriptName non trovato!" -ForegroundColor Yellow
    }
}

# Menu principale
while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "         WINDOWS CLEAN - LAUNCHER" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1 - Ottimizzazione di sistema" -ForegroundColor Green
    Write-Host "2 - Backup & Restore (non ancora disponibile)" -ForegroundColor Red
    Write-Host "3 - Manutenzione avanzata (non ancora disponibile)" -ForegroundColor Magenta
    Write-Host "4 - Strumenti utili (non ancora disponibile)" -ForegroundColor Yellow
    Write-Host "Q - Esci" -ForegroundColor DarkGray
    Write-Host ""
    
    $choice = Read-Host "Scegli un'opzione"

    switch ($choice.ToUpper()) {
        "1" { Run-Script "clean.ps1"; Pause }
        "2" { Run-Script "restore.ps1"; Pause }
        "3" { Run-Script "maintenance.ps1"; Pause }
        "4" { Run-Script "tools.ps1"; Pause }
        "Q" { Write-Host "Chiusura launcher..." -ForegroundColor Cyan; Pause; exit }
        Default { Write-Host "Opzione non valida!" -ForegroundColor Yellow; Pause }
    }
}
