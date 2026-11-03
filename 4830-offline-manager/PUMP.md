# PUMP integration for Gluon v2023.1

Patch-Basis: [ffgtso/ffgt_packages-v2023.x](https://github.com/ffgtso/ffgt_packages-v2023.x/tree/b622663eca1110cf9c7e034cc7dea2b7a8800697),
Branch `master`, Commit `b622663eca1110cf9c7e034cc7dea2b7a8800697`.
Enthaltenes `gluon-pump`: Version 0.1.22. Manager: Version 1, Release 2 → 3.

## Ablauf

Die bisherigen Kriterien bleiben erhalten: 18 Sekunden Verzögerung beim
minütlichen Aufruf, mindestens 15 Minuten Uptime, mehr als 60 Minuten ohne
Batman-Gateways vor Update-Versuchen, mindestens zehn Minuten zwischen ihren
Starts, Reboot nach mehr als 95 Minuten. Ein vorhandenes Gateway, auch TQ 0,
verhindert Update/Reboot. TQ <= 15 setzt ausschließlich die Client-/OWE-SSIDs
offline; TQ >= 30 setzt sie online; dazwischen bleibt ihr Zustand bestehen.

Nach Ablauf der Ausfallfrist:

1. Bei aktiviertem PUMP-WLAN-Uplink zuerst `pump_wan`/`pump_wan6` und deren
   tatsächliches Gerät prüfen. Nur aktive, zum Gerät passende netifd-Interfaces
   mit Kernel-Default-Route werden für einen Versuch herangezogen.
2. `offline4`/`offline6` versuchen, sofern vorhanden; beim PUMP-Uplink andernfalls
   den konfigurierten Standardbranch. `gluon-wan` wählt WAN-DNS, `libpacketmark`
   mit Markierung 1 das IPv6-WAN-Routing. Gluon-PUMP liefert die DNS-Daten über
   seine bestehenden interface.d-/Hotplug-Hooks. Bei mehreren WAN-Default-Routen
   gilt die vorhandene Routingpriorität; der Manager setzt keine eigene Route.
3. Wenn kein Upgrade gestartet wurde und weiterhin kein Gateway vorhanden ist:
   offene Freifunk-APs über die aktiven PHYs suchen. PUMP-AP/STA-Interfaces können
   dabei die einzigen aktiven WLAN-Interfaces sein.
4. Normale WLAN-Interfaces mit `wifi down` abschalten und eine separate Station
   `offlinewifi` erstellen. Kein `uci:delete_all`, kein `uci:revert`, kein Austausch
   von `/etc/config/` und keine Änderung an PUMP-Zugangsdaten.
5. Die Station bei netifd extern für `offline_wifi4` und `offline_wifi6` anmelden;
   DHCPv4 und DHCPv6 starten. IPv6-Adresse, Default-Route und DNS werden bevorzugt;
   alternativ genügt ein vollständiger IPv4-Zugang. Bei IPv4-only wird ein
   vorhandener `offline4`-Branch verwendet, sonst der Standardbranch.
6. Nach Rückkehr oder Fehler beide temporären Protokolle stoppen, Station löschen
   und `wifi up` ausführen. Die zuvor erzeugte PUMP-Konfiguration bleibt erhalten.
   DNS-/Tunneldigger-Hotplug läuft beim erneuten PUMP-Uplink-Aufbau wie gewohnt.
   Bei begonnenem sysupgrade wird weder restauriert noch konkurrierend rebootet.

Ein Branch-Name erzwingt keine Adressfamilie. Die Mirror-URLs müssen zum
verfügbaren Zugang passen; beispielsweise hilft ein ausschließlich per IPv6
erreichbarer Standardmirror auf einem IPv4-only-AP nicht. Ein Exitcode 0 ohne
Upgrade-Marker kann „keine neuere Firmware“ bedeuten; weitere Versuche bleiben
innerhalb des bestehenden Zeitbudgets möglich. Laufende Autoupdater werden
nicht durch ein äußeres Zeitlimit beendet.

## Übernahme des alten Pakets

- Migration: eine vorhandene Manager-Einstellung bleibt erhalten. Sonst wird
  zuerst `pump-autoupdater-wifi-fallback.settings.enabled`, dann der gewöhnliche
  Fallback-Schalter, schließlich der normale Autoupdater-Schalter übernommen.
- Der Cron-Eintrag `pump-autoupdater-wifi-fallback` wird entfernt. Paketkonflikte
  verhindern eine parallele Installation, ebenso die parallelen SSID-Changer.
- `software.autoupdater.wifi-fallback` bleibt im respondd-Nodeinfo verfügbar.
  Es meldet die effektive Freigabe durch Manager, Manager-Autoupdate und normalen
  Autoupdater. Der bestehende native respondd-Adapter wurde übernommen; die
  Ablaufsteuerung ist weiterhin Lua/Shell. Copyright-Hinweise bleiben erhalten.
- Die alten Zwei-Stunden-Fristen und der Force-Schalter werden durch die bereits
  vereinbarten Manager-Regeln ersetzt. Das alte Paket bleibt im Repository für
  andere Images vorhanden, gehört aber nicht mehr in Manager-Images.
- `gluon-pump` bleibt optional. Für PUMP stellt dessen eigenes Paket den passenden
  WPA3-Supplicant bereit; der Manager erzwingt keine andere Supplicant-Variante.

## Einbau

Im Paketfeed:

```sh
git apply --check /pfad/4830-offline-manager-pump.patch
git apply /pfad/4830-offline-manager-pump.patch
```

Das Archiv enthält außerdem das vollständige aktualisierte Paketverzeichnis.
Dieses ist eine Alternative zum Anwenden des Paketpatches.

In der Site `gluon-pump` und `4830-offline-manager` auswählen und
`pump-autoupdater-wifi-fallback` entfernen. Keine anderen SSID-/Fallback-Skripte
parallel auswählen. Der separate Patch `site-ffgt-v2023.1-offline-manager-pump.patch`
setzt das für die bekannte Site um, gegen Branch `stable`, Commit
`f57001692331a1f0cec73ea101c6dcf2ee224568`. Er entfernt zusätzlich den dort noch
aktivierten `ffgt-ssid-changer` und den FFAC-Fallback aus der Low-Memory-Auswahl.
`gluon-pump` bleibt in der Standard-Auswahl erhalten; die bestehenden
Hardware-Ausschlüsse bleiben bestehen.

Nach Übernahme der Paketänderung den neuen Paketfeed-Commit in `modules` festlegen.
Der bisherige Pin enthält diese Änderung nicht; deshalb wird keine erfundene
Commit-ID in einen Patch geschrieben. Ein neuer Firmware-Build und Upgrade führen
das Manager-Upgrade-Skript aus und richten DHCPv4 sowie die Firewall-Regeln ein.
Ein bloßer Austausch der Lua-Dateien auf einem laufenden Router genügt nicht.
Es wurden keine Änderungen gepusht oder auf Router ausgerollt.

## Prüfung

83 Lua-5.1-Tests bestanden. Darunter: PUMP-Uplink vor WLAN-Scan, Upgrade-/Gateway-
Rückkehr ohne weiteren Scan, IPv4-only, beide externen netifd-Anmeldungen,
getrennte Open-/OWE-SSIDs bei unveränderten PUMP-BSS, Cleanup nach Fehlern,
Schutz vor UCI-Schreibzugriffen im Fallback und Migration deaktivierter Vorgänger.

Zwei Python-Tests bestanden: Shell-Einstieg `sleep 18` vor Tick sowie ein
kompilierter Hosttest des tatsächlichen respondd-C-Codes mit UCI-/JSON-API-Doubles
(32 Schalter-/Bool-Kombinationen plus vier Fehlerfälle).
Lua-/Shell-Syntax und Anwendung beider Patches werden geprüft.

Kein vollständiger OpenWrt/Gluon-Build, kein ABI-/Integrationstest mit den echten
Routerbibliotheken und kein Hardwaretest. Vor Ausrollen sind insbesondere
PUMP-AP, PUMP-STA, PUMP-WLAN-Uplink, IPv4-only und Wiederherstellung nach einem
fehlgeschlagenen Download auf Zielhardware zu prüfen. Manuelle gleichzeitige
PUMP-/WLAN-Rekonfigurationen durch Administratoren werden nicht gesperrt.

Dieser Patch richtet sich an das v2023.1-Paket im genannten Feed. Er ist nicht
direkt für die v2025.1-Variante bestimmt; dort unterscheiden sich weiterhin
Bitbibliothek, WAN-Wrapper und Hostapd-Reload.
