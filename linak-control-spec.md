# Linak DPG1C macOS Desk Control – Specification

## 1. Ziel und Scope

Dieses Dokument beschreibt das **spec-driven Design** einer macOS‑Lösung zur Steuerung eines höhenverstellbaren Schreibtischs mit LINAK‑Motoren und DPG1C‑Bedienteil per Bluetooth. [cite:16][web:3]

Die Lösung umfasst:

- Menüleisten‑App (Menu Bar App)
- Command‑Line Interface (CLI)
- Optional: Widget (Desktop/Notification Widget)

Die Anwendung ist für **private Nutzung** konzipiert und soll nach Möglichkeit **ohne kostenpflichtige Apple Developer Lizenz** nutzbar sein (lokaler Build, Gatekeeper‑Workaround). [web:25]

---

## 2. Randbedingungen & Annahmen

- Zielplattform: macOS (Apple Silicon). [web:2]
- Kommunikation ausschließlich lokal, keine Cloud‑Abhängigkeiten.
- Bluetooth Low Energy (BLE) Verbindung direkt zum DPG1C Desk Panel. [web:3][web:23]
- Das DPG1C kann immer nur eine Bluetooth‑Verbindung gleichzeitig halten (iPhone/Mac/Home Assistant etc.). [web:20]
- App ist für persönlichen Gebrauch gedacht, Verteilung über Source‑Code, nicht über App Store.

---

## 3. Systemarchitektur (High Level)

### 3.1 Komponentenübersicht

1. **Core Service (Daemon / Hintergrundprozess)**  
   - Implementiert:
     - BLE‑Handling (Scan, Pairing, Connect, Disconnect). [web:11][web:18]
     - Desk‑Protokoll (Up/Down, Presets, Höhe lesen, Auto‑Run‑Verhalten).
     - Ownership/Profile‑Logik (Owner/Guest).
     - Persistenz von Settings und Profilen.
   - Bietet eine **lokale JSON‑basierte API** (z.B. über Unix‑Socket oder localhost‑HTTP).

2. **Menüleisten‑App (Menu Bar App)**  
   - UI‑Client für den Core Service.
   - Anzeige:
     - Verbindungsstatus.
     - Aktuelle Höhe.
     - Einheit (cm/Zoll).
   - Steuerung:
     - Hoch/Runter (manuell/auto).
     - Presets 1–4.
     - Modus Owner/Guest, Einheiten, Auto‑Run‑Konfiguration.

3. **CLI‑Tool (deskctl)**  
   - Kommandozeilentool, das die gleiche interne JSON‑API des Core Service nutzt.
   - Für Skripting, Automatisierung, Integration in andere Tools.

4. **Widget (optional)**  
   - Widget‑Extension, die über die JSON‑API Daten vom Core Service bezieht.
   - Fokus auf Anzeige der Höhe und einfache Aktionen (Preset oder Auto‑Move).

---

## 4. Funktionale Anforderungen

### 4.1 Bluetooth & Verbindung

**Funktionen:**

- Desk Discovery:
  - Scan nach BLE‑Geräten mit LINAK‑typischen Services (laut Reverse‑Engineering der Open‑Source‑Projekte). [web:11][web:18]
  - Anzeige gefundener Desks mit Name/Adresse in der Menüleisten‑App.

- Pairing & Speicherung:
  - Einmaliges Pairing mit ausgewähltem Desk (DPG1C).
  - Speicherung von Identität/Adresse im Benutzerprofil (z.B. in einer lokalen Config).

- Reconnect:
  - Automatische Wiederverbindung beim Start des Core Service.
  - Manuelle „Reconnect“-Aktion via Menüleisten‑App oder CLI.

- Konflikterkennung:
  - Erkennung, wenn Desk bereits mit einem anderen Client verbunden ist (DPG1C „busy“), und Anzeige eines entsprechenden Status. [web:20][web:19]

### 4.2 Steuerung Hoch / Runter

**Aktionen:**

- Manuelles Fahren:
  - `startUp`, `stopUp`, `startDown`, `stopDown`.
  - Implementiert als BLE‑Writes auf bestimmte Characteristics gemäß Protokoll der Community‑Projekte. [web:11][web:18][web:24]

- Automatisches Fahren (Auto‑Run):
  - Modi:
    - `manual` (Hold): fährt nur, solange Befehl aktiv ist.
    - `auto` (Tap): fährt durchgehend, bis Ziel erreicht oder gestoppt.
  - Konfiguration:
    - Pro Richtung (hoch/runter) definierbar, ob `auto` oder `manual` bevorzugt wird.
    - Speichern in lokaler Settings‑Datei; ggf. Mapping auf Desk‑seitige Optionen, falls verfügbar. [web:15]

**UI/CLI:**

- Menüleisten‑App:
  - Buttons „▲“ und „▼“ mit konfigurierbarem Verhalten (auto/manual).1
- CLI:
  - `deskctl up [--auto|--manual]`
  - `deskctl down [--auto|--manual]`

### 4.3 Presets (4 Speicherpositionen)

**Funktionen:**

- Presets 1–4 anfahren:
  - `goPreset(1..4)` – fährt auf definierte Höhenpositionen. [web:11][web:22]
- Presets speichern (falls Protokoll bekannt):
  - `savePreset(1..4)` – speichert aktuelle Höhe auf Preset.

**UI/CLI:**

- Menüleisten‑App:
  - Buttons „1“, „2“, „3“, „4“. bzw mit Höhenangaben aus Presets
- CLI:
  - `deskctl preset <1-4>` → fährt Preset an.
  - `deskctl preset <1-4> --save` → speichert aktuelle Höhe als Preset (optional).

### 4.4 Höhenanzeige & Einheiten

**Basis:**

- Desk liefert Höhe typischerweise in interner Einheit (vermutlich mm oder steps). [web:11][web:18]
- Core Service konvertiert in gewünschte Anzeigeeinheit.

**Anforderungen:**

- Periodische oder eventbasierte Höhenaktualisierung (Polling z.B. alle 1s, wenn verbunden).
- Konfigurierbare Anzeigeeinheit:
  - `cm` (Standard).
  - `inch`.

**Umrechnung:**

- Intern:
  - `height_mm` als Basiseinheit.
- Darstellung:
  - cm: `height_cm = height_mm / 10.0`.
  - inch: `height_in = height_mm / 25.4`.

**UI/CLI:**

- Menüleisten‑App:
  - Anzeige z.B. „110.5 cm“ bzw. „43.5 in“.
- CLI:
  - `deskctl height` → Textausgabe.
  - `deskctl height --json` → JSON mit numerischer Höhe und Einheit.

### 4.5 Owner/Guest‑Konzept

Da das Desk‑Panel selbst keine echten Benutzerrollen kennt, wird dieses Konzept **lokal** in der Anwendung modelliert.
Im Desk-Panel wird die Software immer als Owner geführt.

**Profile:**

- Owner:
  - Hat volle Kontrolle über:
    - Preset‑Definitionen (lokale Metadaten).
    - Default‑Einstellungen (Einheit, Auto‑Run, gewählte Desks).
  - Kann Presets als „shared“ für Gäste markieren.

- Guest:
  - Darf:
    - Tisch hoch/runter bewegen.
    - Freigegebene Presets anwählen.
  - Darf nicht:
    - Owner‑Settings verändern, außer explizit erlaubt.

**Persistenz:**

- Lokale Profile (z.B. `profiles.json`) im Benutzerverzeichnis.
- Struktur (Beispiel):
  ```json
  {
    "profiles": [
      {
        "name": "Marcus",
        "role": "owner",
        "defaultDesk": "Desk-1234",
        "unit": "cm",
        "autoRun": { "up": "manual", "down": "auto" }
      },
      {
        "name": "Guest",
        "role": "guest",
        "unit": "cm"
      }
    ],
    "activeProfile": "Marcus"
  }
  ```

**CLI/GUI:**

- `deskctl profile list`
- `deskctl profile set <name>`
- Menüleisten‑App: Dropdown „Owner / Guest / Profile wählen“.

### 4.6 Automatisches Verfahren konfigurierbar

**Anforderungen:**

- Nutzer kann pro Aktion entscheiden, ob:
  - Auto‑Run (Tap) oder
  - Manuell (Hold)
  verwendet wird, sofern dies mit dem DPG‑Verhalten kompatibel ist. [web:15][web:23]

**Design:**

- Globale Default‑Settings (Owner‑only).
- Pro CLI‑Aufruf und UI‑Aktion kann Modus temporär überschrieben werden (z.B. Button „Auto Up“).

---

## 5. Nicht‑funktionale Anforderungen

- **Keine kostenpflichtige Apple Developer Lizenz notwendig:**
  - Projekt soll lokal aus Source mit Xcode gebaut werden können.
  - App darf unsigniert bleiben; Nutzung ist über Gatekeeper‑Bypass möglich. [web:25]
- **Robustheit:**
  - Saubere Fehlerbehandlung bei:
    - Verbindungsabbrüchen.
    - Nicht erreichten Desks.
    - Wake‑Up‑Problemen (manche DPG1C‑Desks gehen schlafen und müssen „geweckt“ werden). [web:20][web:19]
- **Performanz:**
  - Ressourcenschonende Pollingintervalle.
  - Core Service als leichter Hintergrundprozess.
- **Logging:**
  - Konfigurierbare Log‑Level (Error, Info, Debug).
  - Optionales Logging der BLE‑Frames zu Entwicklungszwecken. [web:11][web:24]

---

## 6. Interne JSON‑API (Entwurf, High Level)

Die folgenden Endpoints sind als Vorschlag zu verstehen und können später formell in eine OpenAPI‑artige Spezifikation überführt werden.

**Basis:**

- Transport:
  - Lokal: Unix‑Socket oder `http://127.0.0.1:<port>`.
- Format:
  - JSON für Requests und Responses.

### 6.1 Beispiele

#### GET /status

- Antwort:
  ```json
  {
    "connected": true,
    "deskName": "LINAK DPG1C",
    "height_mm": 1105,
    "height_display": "110.5 cm",
    "unit": "cm",
    "profile": "Marcus",
    "role": "owner"
  }
  ```

#### POST /move

- Request:
  ```json
  {
    "direction": "up",
    "mode": "auto"
  }
  ```
- Response:
  ```json
  { "ok": true }
  ```

#### POST /preset

- Request (fahren):
  ```json
  {
    "index": 1,
    "action": "go"
  }
  ```
- Request (speichern):
  ```json
  {
    "index": 2,
    "action": "save"
  }
  ```

#### POST /settings

- Request:
  ```json
  {
    "unit": "inch",
    "autoRun": {
      "up": "manual",
      "down": "auto"
    }
  }
  ```

---

## 7. CLI‑Spezifikation (Entwurf)

Command‑Line‑Tool `deskctl`:

- `deskctl status`
  - Zeigt Verbindung, aktive Profile, Höhe.

- `deskctl height [--json]`
  - Gibt aktuelle Höhe aus.

- `deskctl up [--auto|--manual]`
- `deskctl down [--auto|--manual]`

- `deskctl preset <1-4> [--save]`

- `deskctl unit cm|inch`

- `deskctl profile list`
- `deskctl profile set <name>`

Alle Kommandos verwenden intern die JSON‑API des Core Service.

---

## 8. Menüleisten‑App (UI‑Spec)

**Statusanzeige:**

- Icon (z.B. Desk‑Symbol).
- Farbe/Badge für:
  - Verbunden.
  - Getrennt.
  - Fehlerstatus.

**Menüinhalt:**

- Aktuelle Höhe (z.B. „110.5 cm“) nur bei Buttons
- Buttons:
  - „▲“ – Hoch (modussensitiv: Auto/Manual).
  - „▼“ – Runter.
  - „1“, „2“, „3“, „4“ – Presets.
    - Anzeige als Höhe, aktiver button markiert.
    - während Fahrt Höhenanzeige
    - wenn Desk nicht in Preset Höhe steht (durch Änderung am Tisch etc) zurück auf Buttonsanzeige
- Settings‑Submenü:
  - Preset  / Manuell (hoch / runter)
  - Einheit: cm / inch.
  - Auto‑Run: up/down jeweils auto/manual.
  - Aktives Profil: Owner/Guest/weitere.
  - Verbundener Desk auswählen.

---

## 9. Widget (optional)

**Inhalt:**

- Anzeige:
  - „Desk: 110.5 cm“.
- Aktionen (soweit Widget‑API erlaubt):
  - Tap: fährt auf zuletzt verwendetes Preset oder toggelt einfachen Move‑Befehl.
  - Kleine Buttons: Preset 1 / Auto‑Up / Auto‑Down (mit Einschränkungen der Plattform).
    - so ähnlich wie Menuzeilen App

---

## 10. Externe Referenzen / Startpunkte

### 10.1 Offizielle LINAK‑Ressourcen

- LINAK Desk Control App – Produktseite  
  https://www.linak.com/products/controls/desk-control-app/  
  → Referenz für Feature‑Set und UX‑Ideen. [web:14]

- Desk Control App – Apple App Store (iPhone / iPad / Apple‑Silicon‑Mac)  
  https://apps.apple.com/de/app/desk-control/id1203254365  
  → Referenz für vorhandene mobile/macOS‑Funktionen. [web:2]

- Desk Control Basic Software – PC/Mac  
  https://www.linak-us.com/products/controls/desk-control-basic-software/  
  → Referenz für Funktionsumfang, Systemarchitektur (lokale PC/Mac‑Software). [web:6]

- Desk Control Basic – Broschüre  
  https://www.one-stop-office-shop.nl/resize/deskline-linak_12526263209325.pdf/linak-deskline-app-brochurepdf.pdf  
  → Feature‑Liste, Setup, unterstützte Szenarien. [web:26]

- Desk Control Basic – Montageanleitung / Installationsanleitung (DE)  
  https://www.kuechenkonsum.de/media/pdf/cd/fe/5c/deskline-desk-control-basic-montageanleitung-dt-1.pdf  
  → Hinweise zur Installation, Anforderungen, typische Nutzerführung. [web:25]

- DPG Desk Panels & Desk Control App – User Manual (DE)  
  https://cdn.linak.com/-/media/files/user-manual-source/de/deskline-dpg-desk-panels-und-desk-control-app-montageanleitung-dt.pdf  
  → Beschreibung DPG1C, grundlegende Funktionen, App‑Verknüpfung. [web:3]

- DPG Desk Panels & Desk Control App – User Manual (ENG)  
  https://cdn.linak.com/-/media/files/user-manual-source/en/deskline-dpg-desk-panels-and-desk-control-app-user-manual-eng.pdf  
  → Detaillierte Beschreibung, Bluetooth‑Adapter, Bedienlogik. [web:23]

- DPG Controller User Guide (BRC)  
  https://brc.group/wp-content/uploads/2020/08/DPG-Viva-Linak-Controller-User-Guide.pdf  
  → Ergänzende Beschreibung von Preset‑Funktionen und App‑Interaktion. [web:15]

### 10.2 Open‑Source & Reverse‑Engineering

- **LinakDeskApp** – Desktop‑App (Linux) mit DPG1C‑Support  
  https://github.com/anetczuk/LinakDeskApp  
  → Wichtigste Referenz für BLE‑Protokoll, Service‑UUIDs, Characteristiken. [web:11]

- **linak-controller** – Python‑Script zur Steuerung von Linak‑Desks  
  https://github.com/rhyst/linak-controller  
  → Protokoll‑Details, Config‑Beispiele, Hinweise zur DPG1C‑Unterstützung. [web:18][web:21]

- **hass-linak-dpg** – Home‑Assistant‑Integration für DPG  
  https://github.com/Laeborg/hass-linak-dpg  
  → Implementierung von Verbindung, Höhenlesung und teilweise Steuerung via BLE. [web:24]

- **linak_desk** – Home‑Assistant Custom Component  
  https://github.com/mdrwiega/linak_desk  
  → Weitere Referenz für BLE‑Handling, Zustandsmodell. [web:22]

- Diskussions‑/Issue‑Threads zur DPG1C‑Kompatibilität:
  - DPG1C Support in `linak-controller`:  
    https://github.com/rhyst/linak-controller/issues/32 [web:21]
  - DPG1C in Home Assistant (Fehler, „Wake Up“):  
    https://github.com/home-assistant/core/issues/104178 [web:20]
  - Weitere DPG1C‑Fehlerbilder:  
    https://github.com/home-assistant/core/issues/106966 [web:19]
    https://github.com/alex20465/deskbluez/issues/2 [web:27]

---

## 11. Nächste Schritte

- JSON‑API formal spezifizieren (Schemas, Fehlercodes, Statuswerte).
- Konkreten Projekt‑Skeleton in Swift (CoreBluetooth + Menu Bar App + CLI‑Target) entwerfen.
- BLE‑Protokoll anhand der genannten Open‑Source‑Repos für DPG1C konkretisieren und in Modul „DeskProtocol“ kapseln. [web:11][web:18][web:24]
