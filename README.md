# CleanWindows

**Script PowerShell modulare per ottimizzare, pulire e personalizzare Windows**

## 📌 Descrizione

`CleanWindows` è uno script avanzato che permette di:

* Rimuovere bloatware preinstallato
* Ridurre telemetria e tracking
* Pulire file temporanei
* Ottimizzare servizi come SysMain (Superfetch)
* Migliorare performance e stabilità
* Applicare ottimizzazioni specifiche per gaming
* Ripristinare le modifiche tramite backup automatici

Include controllo privilegi amministrativi, backup del registro, salvataggio stato servizi e log dettagliato.

---

## 📂 Funzionalità principali

### 🔹 Modalità disponibili

All’avvio viene mostrato un menu:

| Modalità           | Descrizione                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------------- |
| **S – Safe**       | Nessuna modifica invasiva. Solo pulizia file temporanei, privacy sicura e manutenzione.                 |
| **B – Balanced**   | Consigliata per uso quotidiano: rimozioni moderate, privacy aumentata, servizi non critici ottimizzati. |
| **A – Aggressive** | Rimuove più app, limita telemetria al minimo, disabilita servizi non indispensabili. Più rischiosa.     |
| **G – Gaming**     | Ottimizzazioni per latenze, pulizia, power plan ad alte prestazioni, rimozione minima bloatware.        |
| **R – Restore**    | Ripristina backup, servizi e impostazioni registry ove possibile.                                       |
| **Q – Quit**       | Esci.                                                                                                   |

---

## 🔧 Operazioni eseguite dallo script

### ✔ Controllo amministratore

Lo script verifica se è avviato con privilegi elevati, altrimenti termina.

### ✔ Creazione punto di ripristino

Se la Protezione Sistema è attiva.

### ✔ Backup chiavi di registro

Le principali chiavi modificate vengono salvate in:

```
dir\data\backup\
```

### ✔ Salvataggio stato servizi

Viene generato:

```
services_state.json
```

con info su StartType e stato al momento della modifica.

### ✔ Rimozione bloatware

In base alla modalità: Safe < Balanced < Aggressive.

### ✔ Privacy / Telemetria

* Disattivazione ricerca web
* Disattivazione contenuti sponsorizzati
* Livello telemetria (1 Balanced, 0 Aggressive)
* Arresto servizi telemetria in Aggressive

### ✔ Ottimizzazioni SSD / SysMain

SysMain può essere disattivato (utile su SSD più lenti).

### ✔ Gaming Tweaks

* Attivazione High Performance (se disponibile)
* Pulizia minore
* Privacy bilanciata

### ✔ Pulizia file temporanei

Cancella contenuto di:

* `%TEMP%`
* `C:\Windows\Temp`

### ✔ Pulizia voci di avvio approvate

Rimuove voci nascoste non necessarie.

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
