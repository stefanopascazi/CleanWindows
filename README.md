# CleanWindows

**Script PowerShell modulare per ottimizzare, pulire e personalizzare Windows**

## 📌 Descrizione

`CleanWindows` è uno script avanzato che permette di:

* Ottimizzare il tuo sistema
* Backup & Restore (under construction)
* Manutenzione avanzata (under construction)
* Strumenti utili (under construction)

Include controllo privilegi amministrativi, backup del registro, salvataggio stato servizi e log dettagliato.

---

CleanWindows - Script PowerShell modulare per pulizia, ottimizzazione e privacy su Windows. Rimuove bloatware, riduce telemetria, pulisce file temporanei e ottimizza servizi, con modalità Safe / Balanced / Aggressive / Gaming e possibilità di ripristino. Tutto contenuto nella cartella dello script, pronto per utenti non esperti tramite file .bat

---

| Documenti disponibili  | Link                                   |
| ---------------------- | -------------------------------------- |
| Ottimizzazione sistema | [Apri](docs/ottimizzazione-sistema.md) |
| Backup & Restore       | [Apri](docs/restore.md)                |
| Manutenzione avanzata  | [Apri](docs/maintenance.md)            |
| Strumenti utili        | [Apri](docs/tools.md)                  |


---

## 🔄 Funzione di ripristino

La modalità **Restore** prova a ripristinare:

* Registro di sistema dai file `.reg` salvati
* Servizi importanti alle impostazioni originali
* Telemetria a valore standard
* Configurazioni Start/Privacy dove possibile

> ❗ Le app UWP rimosse NON vengono reinstallate automaticamente: possono essere recuperate via Microsoft Store.

---

## 📝 Log dettagliato

Ogni operazione viene registrata in:

```
dir\data\log_<data>.txt
```

---

## ▶️ Come eseguirlo

1. **Accedi al file** `CleanWindows.bat`
2. Tasto destro -> **Esegui come Amministratore**
3. Seleziona una modalità ed attendi il completamento automatico

---

## ⚠️ Avvertenze

* Le modalità **Aggressive** e **Gaming** modificano servizi e caratteristiche che potrebbero impattare alcune funzionalità Windows.
* Alcune modifiche non sono reversibili al 100% (es. rimozione app UWP).
* Verifica il log per eventuali errori o operazioni non riuscite.

---

## ✔ Raccomandazioni

* Usare la modalità **Balanced** nella maggior parte dei casi.
* Usare **Aggressive** solo su PC personali e non di produzione.
* Salvare i dati prima di applicare modifiche significative.
* Riavviare sempre al termine.
* E' consigliabile testare lo script su una VM con Windows 10/11 installato per testare le varie modalità e capirne gli impatti
