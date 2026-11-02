# 4830-offline-manager

Gemeinsames Lua-Paket für Gluon v2023.1/OpenWrt 22.03: Offline-SSIDs,
WLAN-/WAN-Recovery-Updates und Offline-Reboot. Ersetzt `tecff-ssid-changer`,
`tecff-autoupdater-wifi-fallback` und `4830-node-watchdog`. Kein IPK oder
fertiges Firmware-Image; ausschließlich Quellpaket.

## Zwei getrennte Kriterien

| Beobachtung | SSIDs | Ausfalltimer für Update/Reboot |
| --- | --- | --- |
| Ausgewähltes Gateway TQ <= 15 | Offline-Namen | Wird zurückgesetzt, solange irgendein Gateway gelistet ist |
| TQ 16 bis 29 | Unverändert (Hysterese) | Wird bei vorhandenen Gateways zurückgesetzt |
| TQ >= 30 | Jeweilige konfigurierte Online-Namen | Zurückgesetzt |
| Keine Gateways | Offline-Namen | Läuft |
| Gateway-Abfrage fehlgeschlagen/unbekanntes Format | Unverändert | Ungültig; keine Update-/Reboot-Entscheidung |

Die Grenzen 15 und 30 sind einschließlich. Sie beziehen sich auf den rohen
BATMAN-IV-TQ-Wert, nicht auf RSSI oder Prozent. Ein gelistetes Gateway mit TQ 0
verhindert ausdrücklich Recovery-Update und Watchdog-Reboot. Gateway-Präsenz
umfasst auch nicht ausgewählte Einträge; die SSID-Qualität kommt vom ausgewählten
Eintrag (`=>` oder `*`). Ohne ausgewählten Eintrag wird TQ 0 verwendet. Bei
ungültiger/mehrdeutiger TQ bleibt die SSID unverändert, vorhandene Gateways zählen
weiterhin als vorhanden. Es gibt keine Gateway-/Mirror-Pings als Offline-Kriterium.

Open- und OWE-WLAN bleiben getrennte BSS mit ihren eigenen UCI-SSIDs pro Radio.
Offline-Präfixe: `FF_OFFLINE_` und `FF_OFF_OWE_`, jeweils mit gekürztem Hostnamen
(maximal 32 Bytes). Private BSS, Verschlüsselung und Sichtbarkeit werden nicht
verändert. Kein OWE-Transition-Modus und keine Transition-SSID-Verarbeitung.
Nur erzeugte Hostapd-Konfigurationen werden atomar und unter Beibehaltung der
Dateirechte angepasst; UCI-WLAN-Einstellungen werden nicht überschrieben. Hex-
Kodierung in `ssid2` schützt Sonderzeichen. Hostapd erhält nach den Änderungen
an allen Radios ein HUP; ein fehlgeschlagenes HUP wird später erneut versucht.

## Zeitablauf

Eine einzige minütliche micron-Aufgabe ruft `/usr/sbin/4830-offline-manager` auf.
Der Shell-Einstieg wartet **18 Sekunden**, bevor er den Lua-Tick startet. Die
18 Sekunden sind eine Phasenverschiebung, keine Sperre für fremde Cronjobs.

1. Gateway-Präsenz/TQ erfassen und den Zustand im RAM aktualisieren.
2. Vor 900 Sekunden Uptime keine SSID-/WLAN-/WAN-/Reboot-Aktionen.
3. Danach minütlich die SSID-Funktion ausführen (außer während eines Updates).
4. Nach **mehr als 3600 Sekunden** ohne Gateways einen Update-Versuch starten,
   danach frühestens alle **600 Sekunden**, gerechnet vom letzten Versuchsbeginn.
5. Nach **mehr als 5700 Sekunden** ohne Gateways hat Reboot Vorrang vor einem
   weiteren Update-Versuch. Direkt vor Update/Reboot wird die Gateway-Liste erneut
   geprüft.

Beispiel: erste Offline-Beobachtung bei Uptime 18 s, danach regelmäßige Ticks:
Versuche bei 3678, 4278, 4878 und 5478 s; Reboot bei 5778 s. Die 15-Minuten-
Bootfrist und die einstündige Ausfallfrist sind gleichzeitige Voraussetzungen,
nicht zwei aufeinander addierte Wartezeiten. Ein Gateway setzt das Intervall
sofort bei der nächsten Beobachtung zurück.

Zustand: `/tmp/4830-offline-manager.state` (JSON mit Boot-ID, Uptime, Beginn des
Ausfalls und letztem Versuch). Keine Flash-Schreibvorgänge für Zähler. NTP-Sprünge
ändern keine Frist. Neustart, unbekannte Gateway-Abfrage, ungültiger Zeitstempel
oder Beobachtungslücke > 150 s setzen die Kontinuität zurück. Die Beobachtung hat
Minutengranularität; sehr kurze Änderungen zwischen Ticks werden nicht erfasst.

## Update-Worker und Reboot-Schutz

Der Tick startet einen separaten Worker. Dadurch laufen die minütlichen
Beobachtungen weiter. Tick und Worker besitzen separate Prozesssperren; eine
zusätzliche Aktionssperre verhindert SSID-Änderungen/Reboot während des Workers.
Die temporären Befehlsausgaben sind pro Prozess getrennt.

Der Worker begrenzt Verbindungsvorbereitung und AP-Suche auf neun Minuten,
spätestens bis zur 95-Minuten-Schwelle. Nach Rückkehr werden die temporäre Station
entfernt und die normalen WLAN-Interfaces wieder aktiviert. Einzelne bereits
laufende Befehle und das Aufräumen können über diese Grenze hinauslaufen.
**Autoupdater/sysupgrade selbst werden niemals nach Ablauf einer äußeren Frist
getötet.** Ein laufendes Update verschiebt deshalb gegebenenfalls den Reboot.
Das gilt auch für einen extern gestarteten Autoupdater. Ein Upgrade-Hook setzt
vor Gluons Netzwerk-Abbau eine Markierung; nach sysupgrade-Handoff findet kein
Netzwerk-Wiederaufbau und kein konkurrierender Watchdog-Reboot mehr statt. Ein
Autoupdater-Abbruch entfernt die Markierung. Bei ungewöhnlichem Prozessabbruch
kann sie bis zum Neustart bestehen bleiben; sie darf erst nach Prüfung eines
möglicherweise laufenden Flash-Vorgangs manuell entfernt werden.

## WLAN- und WAN-Pfad

Registrierte PHYs werden über sysfs geprüft. Ohne PHYs wird kein `iw` aufgerufen,
sodass fehlendes nl80211 auf Offloadern den WAN-Pfad nicht blockiert. Vorhandene,
aber ausgeschaltete WLAN-Interfaces werden nicht für einen Scan aktiviert.

WLAN: aktive PHYs scannen; offene Infrastruktur-APs mit `freifunk` im SSID-Namen
nach Signal sortieren; normale WLAN-Interfaces abschalten; Station `offlinewifi`
per `iw` anlegen und als externes Gerät bei netifd anmelden. Das logische Interface
`offline_wifi6` bezieht IPv6-Adresse, Default-Route und DNS via netifd/odhcp6c.
Danach wird `autoupdater -f -b <konfigurierter Branch>` aufgerufen. Exitcode 0 ohne
begonnenes sysupgrade kann lediglich „keine neue Firmware“ bedeuten: weitere
Kandidaten werden bis zum Vorbereitungszeitlimit geprüft. Es gibt keinen separaten
wpa_supplicant-Ersatz und keine permanente UCI-WLAN-Umschaltung.

Ohne WLAN: nur bei existierendem `br-wan` und passender Kernel-Default-Route den
Branch `offline4`, danach gegebenenfalls `offline6` versuchen. WAN-Aufrufe verwenden
`gluon-wan` für WAN-DNS und `libpacketmark` (Markierung 1) für IPv6-WAN-Routing.
Die Branches müssen passende Mirrors/Schlüssel enthalten; die Branch-Namen
selbst erzwingen keine Adressfamilie. In der zuvor gelieferten Site-Änderung für v2021.1 verwenden
sie die bisherigen Deadend-Mirrors (IPv4/IPv6-Hostname) und unverändert deren
Signaturschwelle und Schlüssel. Das normale WLAN-Update verwendet weiterhin den
konfigurierten Standardbranch.

## Einbau und Migration

1. `4830-offline-manager/` in den Paketfeed übernehmen oder den Paketpatch anwenden.
2. In der bereits für Gluon v2023.1 portierten Site die drei alten Pakete durch
   dieses Paket ersetzen und passende offline4/offline6-Branches bereitstellen.
   Der alte v2021.1-Site-Patch ist keine vollständige Site-Migration.
3. Paketfeed-Commit nach Übernahme der Änderung im Build festlegen. Ein lokaler
   Patch steht einem entfernten Build mit `PACKAGES_FFGT_COMMIT=LATEST` nicht
   automatisch zur Verfügung. Die gelieferten Änderungen wurden nicht gepusht.
4. Regulären Gluon-Build und Firmware-Upgrade ausführen. Das Gluon-Upgrade-Skript
   migriert die Aktivierung des alten Fallbacks und entfernt dessen Konfiguration
   sowie die alten erzeugten Cron-Einträge. Paketkonflikte verhindern parallele
   Installation der ersetzten Implementierungen.

Konfiguration `/etc/config/4830-offline-manager`, Section `settings`:
`enabled`, `ssid_enabled`, `autoupdate_enabled`, `reboot_enabled` (Bool).
`autoupdate_enabled` übernimmt beim ersten Upgrade den alten Fallback-Schalter,
sonst den Autoupdater-Schalter. Updates setzen zusätzlich einen aktivierten
normalen Autoupdater voraus. SSID-Funktion und Watchdog sind standardmäßig aktiv.
Es gibt keinen Force-Schalter, der die Fristen oder Gateway-Präsenz umgeht.

Die neue WLAN-Firewall-Zone `offlinefb` erlaubt den nötigen ICMPv6-/DHCPv6-Verkehr,
aber kein Forwarding und keine zusätzliche SSH-Freigabe. Keine Änderung an
Signatur-/Geräte-/Versionsprüfungen des Autoupdaters.

## Prüfung

```sh
lua5.1 tests/test.lua
python3 tests/test_wrapper.py
find luasrc -type f -exec luac5.1 -p '{}' \;
```

68 Lua-5.1-Tests mit simulierten Router-APIs, ein ausführbarer Wrapper-Test für
Reihenfolge `sleep 18` vor Tick, Lua-/Shell-Syntaxprüfungen. Abgedeckt sind u. a.
TQ 0/15/16/29/30, getrennte Open-/OWE-SSIDs, Gateway-Verlust/Erholung, stündliche
Schwelle, Zehn-Minuten-Takt, 95-Minuten-Reboot, Sperren, Upgrade-Handoff, WAN,
netifd-Anmeldung und Migration. Die Tests ersetzen keinen Firmware-Build und
keinen Test von Hostapd, netifd, WLAN-Treiber, WAN-DNS, Flash und Reboot auf
Zielhardware. Ein kompletter Firmware-Build und Hardwaretests wurden nicht
ausgeführt. Ergebnisse stehen in `tests/RESULTS.txt`.

Ursprüngliche Quellbasis: Paketfeed `002233c40efff1cc0f6dc321efefae8e60ddb82c`, Site
`0b44742ea9c257da2cce7571a8a50dfee6d5e7c0`, Upstream-Gluon-Tag `v2021.1`.
Die Site nennt `v2021.1.2-ffgt`; deren gesamte Fork-Abweichungen wurden nicht gebaut.
Runtime-Basis ist die zuvor geprüfte ffgt-WLAN-Fallback-Implementierung mit
luaposix, erweitert und unter den beiliegenden Lizenzbedingungen zusammengeführt.

## Versionsanpassung

Dieser Stand enthält den eigenständigen Kompatibilitätspatch für Gluon v2023.1
gegen das ursprünglich gelieferte v2021.1-Paket. Details und festgeschriebene
Quellen stehen in [COMPATIBILITY.md](COMPATIBILITY.md).
Die PHY-Ermittlung wurde auf `gluon.wireless.find_phy` korrigiert. Das behebt
auch einen Fehler des ursprünglichen Pakets, nicht nur eine Versionsänderung.
