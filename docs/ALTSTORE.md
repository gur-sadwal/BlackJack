# BlackJack per AltStore aufs iPhone

AltStore installiert Apps, die nicht aus dem App Store kommen, mit deiner **eigenen Apple-ID**.
Das ist **kein Jailbreak**: Garantie, iOS-Updates und deine Daten bleiben unberührt.

> **Kurzfassung:** AltServer auf dem Mac → AltStore aufs iPhone → `BlackJack.ipa` in AltStore öffnen.
> Alle 7 Tage frischt AltStore die App automatisch auf, solange der Mac im selben WLAN läuft.

---

## Was du brauchst

| | |
|---|---|
| **Mac** | mit aktuellem macOS (AltServer läuft in der Menüleiste) |
| **iPhone** | iOS 26 oder neuer (getestet für iOS 27.2) |
| **Apple-ID** | eine normale, kostenlose Apple-ID reicht. Tipp: eine Zweit-ID nur dafür anlegen |
| **Kabel** | nur für die Ersteinrichtung |

---

## 1 · AltServer auf dem Mac installieren

1. Lade **AltServer für macOS** von der offiziellen Seite **[altstore.io](https://altstore.io)** herunter.
   (Nur von dort – keine Spiegel-Downloads.)
2. Ziehe **AltServer.app** in den Ordner **Programme** und starte es.
   Es erscheint als ◇-Symbol in der **Menüleiste**.
3. Falls AltServer nach weiteren Komponenten fragt, folge den Hinweisen im Fenster.

## 2 · iPhone vorbereiten

1. iPhone **per Kabel** an den Mac anschließen und auf dem iPhone **„Vertrauen“** tippen.
2. Im **Finder** das iPhone auswählen und **„Dieses iPhone im WLAN anzeigen“** aktivieren
   → so klappt die automatische Aktualisierung später ohne Kabel.

## 3 · AltStore aufs iPhone

1. Menüleiste → **AltServer** → **Install AltStore** → dein iPhone wählen.
2. Apple-ID und Passwort eingeben. Die Daten gehen nur an Apple, um die App zu signieren.
3. Auf dem iPhone: **Einstellungen → Allgemein → VPN & Geräteverwaltung** →
   deine Apple-ID antippen → **Vertrauen**.
4. **Entwicklermodus** einschalten (einmalig):
   **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** → an → iPhone neu starten → bestätigen.
   *(Der Punkt erscheint erst, nachdem die erste Sideload-App installiert wurde.)*

## 4 · BlackJack installieren

1. Auf dem iPhone in **Safari** die Release-Seite des Repos öffnen
   (**GitHub → Releases → neueste Version**) und **`BlackJack.ipa`** laden.
   Die Datei landet in **Dateien → Downloads**.
   *Alternativ:* IPA per **AirDrop** vom Mac schicken.
2. **AltStore** öffnen → Tab **My Apps** → oben links **„+“** → `BlackJack.ipa` auswählen.
3. Kurz warten – fertig. BlackJack liegt jetzt auf dem Home-Bildschirm. 🃏

## 5 · Aktuell halten (7-Tage-Regel)

Mit einer kostenlosen Apple-ID signiert Apple Apps nur für **7 Tage**.

- **Automatisch:** Läuft der Mac mit AltServer im **selben WLAN**, aktualisiert AltStore im Hintergrund.
- **Manuell:** AltStore → **My Apps** → **Refresh All**.
- Läuft die Frist doch ab, öffnet sich die App nicht mehr. **Keine Daten gehen verloren**:
  einfach auffrischen, dann geht's weiter.

> Mit einer kostenlosen Apple-ID sind gleichzeitig höchstens **3 Sideload-Apps** aktiv (AltStore zählt mit).

## 6 · Updates einspielen

Neue Version bauen (im Projektordner):

```bash
./scripts/build-ipa.sh
```

Dann `build/BlackJack.ipa` wie in Schritt 4 in AltStore öffnen. Die App wird **überschrieben**,
Guthaben, Level und Erfolge **bleiben erhalten**.

---

## Spielstand – wo liegt der?

- Der Spielstand (Guthaben, Level, Statistik, Erfolge, Deck-Wahl) liegt **lokal auf dem iPhone**
  (wenige hundert Byte in den App-Einstellungen).
- Er übersteht Neustarts, iOS-Updates, AltStore-Refreshes und App-Updates.
- Er ist Teil deines normalen **iPhone-Backups** (iCloud oder Mac).
- **Weg ist er nur**, wenn du die App **löschst**.
- Game Center und iCloud-Sync würden einen kostenpflichtigen Apple-Entwickler-Account
  voraussetzen und funktionieren mit einer kostenlosen AltStore-Signatur nicht.

---

## Probleme?

| Problem | Lösung |
|---|---|
| „Untrusted Developer“ | Schritt 3.3 – Profil unter *VPN & Geräteverwaltung* vertrauen |
| App startet nicht mehr | 7 Tage abgelaufen → AltStore → *Refresh All* |
| AltStore findet den Mac nicht | Mac und iPhone im selben WLAN, AltServer läuft, Finder-WLAN-Option aktiv |
| „Maximum number of apps“ | Andere Sideload-App in AltStore deaktivieren (max. 3 mit Gratis-Apple-ID) |
| Entwicklermodus fehlt | Erst eine Sideload-App installieren (AltStore), dann erscheint der Schalter |

**Alternative ohne AltStore:** Projekt in Xcode öffnen, iPhone anschließen, unter *Signing & Capabilities*
dein Team (Apple-ID) wählen und ▶︎ drücken. Auch hier gilt die 7-Tage-Regel.
