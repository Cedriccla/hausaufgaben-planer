# Hausaufgaben-Planer

Selbst programmierter Hausaufgaben-Planer fürs iPad: Aufgaben eintragen, Wochenübersicht, Fokus-Timer (Pomodoro), Erinnerungen.

- `ios/` – iPad-App in Swift/SwiftUI. Öffnet sich in **Swift Playgrounds** (`Hausaufgaben.swiftpm`) oder wird über GitHub Actions zu einer `.ipa` gebaut (für Sideloadly).
- **Untis:** Im Tab „Untis“ Schule suchen und mit den Untis-Zugangsdaten anmelden. Die Hausaufgaben aus Untis kommen dann automatisch in die Liste (beim Öffnen der App oder durch Herunterziehen der Liste).
- `docs/` – Web-Version (PWA) mit Untis-Stundenplan-Import, über GitHub Pages nutzbar.

## .ipa bauen
Unter **Actions → „iPad-App bauen (.ipa)“ → Run workflow**. Die fertige Datei liegt danach beim Lauf unter „Artifacts“.

## Mit Sideloadly installieren
1. Sideloadly (sideloadly.io) und iTunes (Windows) installieren.
2. iPad per Kabel anschließen, `Hausaufgaben.ipa` in Sideloadly ziehen.
3. Apple-ID eingeben → **Start**.
4. Auf dem iPad: Einstellungen → Allgemein → VPN & Geräteverwaltung → deiner Apple-ID vertrauen.
5. Ab iPadOS 16: Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus** einschalten, iPad neu starten.

Mit einer kostenlosen Apple-ID läuft die App 7 Tage. Danach in Sideloadly erneut installieren (Daten bleiben erhalten) oder die automatische Erneuerung im WLAN aktivieren.
