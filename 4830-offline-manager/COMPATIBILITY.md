# 4830-offline-manager: Gluon v2023.1 / v2025.1

Stand: 2. November 2026. Geprüft gegen die exakten Upstream-Tags v2023.1 und
v2025.1 und deren festgeschriebene OpenWrt-/Paketquellen. Keine pauschale Zusage
für Community-Forks oder sämtliche nachfolgenden Patch-Releases.

## Ergebnis

| Bestandteil | v2023.1 | v2025.1 |
| --- | --- | --- |
| PHY-Ermittlung | `gluon.wireless.find_phy(radio)` | `gluon.wireless.find_phy(radio)` |
| Lua / Bitoperationen | Lua 5.1, `bit` / `luabitop` bleiben | Lua 5.1 bleibt; `bit32` / `lua-bit32` |
| WAN-DNS | `gluon-wan` bleibt | Umbenannt zu `gluon-wan-dns` |
| IPv6-WAN-Routing | `libpacketmark`, Markierung 1 bleiben | `libpacketmark`, Markierung 1 bleiben |
| Hostapd-Reload | HUP bleibt; BSS-`config_id` folgt der SSID | `ubus call hostapd reload '{}'` statt HUP |
| netifd | Externes Gerät mit `add_device` / `link-ext` | Externes Gerät mit `add_device` / `link-ext` |
| Firewall | Gluon verwendet weiterhin `firewall`/iptables | Gluon verwendet weiterhin `firewall`/iptables |
| Netzwerkkonfiguration | Bestehendes `ifname` bleibt gültig | Bestehendes `ifname` bleibt gültig |

Die falsche Verwendung von `gluon.util.find_phy` war bereits ein Fehler im
zuvor gelieferten v2021.1-Paket. Beide Kompatibilitätspatches beheben ihn.
Die Tests verwenden jetzt ein eigenes `gluon.wireless`-Testmodul und stellen
`find_phy` nicht mehr fälschlich in `gluon.util` bereit.

OpenWrt 22.03 nutzt eine BSS-`config_id`, um bei Konfigurationsänderungen die
zugehörigen Stationszustände zu verwerfen. Der v2023.1-Patch setzt vorhandene
IDs für die verwalteten BSS passend zur Ziel-SSID. IDs privater BSS und die
Radio-ID bleiben unverändert. Eine unveränderte Zielkonfiguration ist idempotent.

OpenWrt 24.10 erzeugt Hostapds aktive Konfiguration aus ucode als Inline-Daten.
Ein HUP nach Bearbeitung der ursprünglichen Datei lädt diese Datei nicht neu.
Die zentrale ubus-Methode `hostapd.reload` liest dagegen `orig_file` neu ein
und führt den Konfigurationsabgleich durch. Erst nach allen Dateianpassungen
wird diese Methode aufgerufen. Bei Fehler bleibt die Wiederholungsmarkierung
bestehen; der nächste Tick versucht den Reload erneut. Es wird kein allgemeiner
`wifi reload` ausgelöst und keine SSID in UCI überschrieben.

`luabitop` existiert im 24.10-Feed noch. Die Umstellung auf `lua-bit32` richtet
das Paket nach Gluon-Core und luaposix aus und vermeidet eine zweite Bitbibliothek;
sie bedeutet nicht, dass Lua durch ucode ersetzt werden muss.

Unverändert bleiben:

- Zwei getrennte sichtbare Open-/OWE-SSIDs ohne Transition-Modus.
- TQ <= 15 offline; TQ >= 30 online; 16..29 unverändert. TQ ist BATMAN-IV-TQ,
  kein RSSI und keine BATMAN-V-Durchsatzmetrik. Die Site muss für diese
  Qualitätsbewertung BATMAN_IV verwenden; die Gateway-Präsenz bleibt davon getrennt.
- Auch ein gelistetes Gateway mit TQ 0 verhindert Recovery-Update und Watchdog-Reboot.
- Minute-Cron mit 18 Sekunden Verzögerung, Aktionsfreigabe ab 15 Minuten Uptime,
  Update nach mehr als 60 Minuten Gateway-Verlust, weitere Versuche alle 10 Minuten,
  Reboot nach mehr als 95 Minuten. Laufende Updates sind vor Reboot geschützt.
- WLAN-Erkennung über sysfs vor `iw`, WAN-Fallback für Geräte ohne PHYs,
  offline4/offline6 nur bei passender Default-Route auf br-wan.

## Anwenden

Die beiden Patches sind **Alternativen**, jeweils gegen das ursprünglich gelieferte
`4830-offline-manager`-Paket für v2021.1 (PKG_VERSION=1, PKG_RELEASE=1).
Nicht nacheinander anwenden und nicht direkt gegen die Gluon-Quellen anwenden.
Das Paket muss bereits im Wurzelverzeichnis des externen Paketfeeds liegen.

Für v2023.1, im Wurzelverzeichnis des Paketfeeds:

```sh
git apply --check /pfad/4830-offline-manager-v2023.1.patch
git apply /pfad/4830-offline-manager-v2023.1.patch
```

Für v2025.1 stattdessen:

```sh
git apply --check /pfad/4830-offline-manager-v2025.1.patch
git apply /pfad/4830-offline-manager-v2025.1.patch
```

Das Download-Archiv enthält außerdem vollständige, bereits angepasste
Paketverzeichnisse unter `gluon-v2023.1/` beziehungsweise `gluon-v2025.1/`.
Entweder den passenden Patch anwenden oder das passende komplette Paket übernehmen.
PKG_RELEASE wird für v2023.1 auf 2, für v2025.1 auf 3 gesetzt.

Die Site muss bereits auf die gewünschte Gluon-Version portiert sein und
4830-offline-manager statt der drei Vorgänger auswählen. offline4/offline6-Mirrors
und Signaturschlüssel müssen für diese Firmware gepflegt werden. Der frühere
v2021.1-Site-Patch ist keine vollständige Migration auf v2023.1 oder v2025.1.
Hier werden ausschließlich Paket-Anpassungen geliefert; weder gepusht noch deployed.

## Upgrade-Pfad für Offloader

- v2023.1 unterstützt Upgrades ab v2021.1. Allerdings hat genau v2023.1 einen
  bekannten Konfigurationsverlust bei Upgrades von v2021.1.x auf x86-64,
  x86-generic und x86-legacy. Für diese Migration mindestens v2023.1.1 verwenden
  und die konkrete Zielversion gesondert bauen/testen.
- v2025.1 unterstützt Upgrades erst ab v2022.1. Ein direkter Sprung von v2021.1
  ist damit kein unterstützter Upgrade-Pfad.
- EdgeRouter X benötigt beim Wechsel auf v2025.1 wegen des Flash-Layouts manuelle
  Schritte. Der Offline-Manager umgeht diese Einschränkung nicht.

## Prüfung und Grenzen

- v2023.1: 68 Lua-5.1-Tests, 1 Shell-Wrapper-Test bestanden.
- v2025.1: 67 Lua-5.1-Tests, 1 Shell-Wrapper-Test bestanden.
- Lua-/Shell-Syntax geprüft; beide Patches gegen die ursprüngliche Lieferung
  mit `git apply --check` geprüft, angewandt und mit den getesteten Dateien verglichen.
- Die Tests verwenden simulierte Router-APIs. Neue Fälle prüfen mehrere Radios,
  unabhängige Open-/OWE-Namen, unveränderte private BSS, Idempotenz sowie erneuten
  Hostapd-Reload nach Fehlern im TQ-Hysteresebereich.
- Quellprüfung der Gluon-APIs, Hostapd-Integration, netifd-ubus-Schnittstelle,
  WAN-Markierung, Lua-/luaposix-Abhängigkeiten und Autoupdater-Hook-Reihenfolge.
- Kein vollständiger Firmware-Build und kein Hardwaretest. Insbesondere echte
  Hostapd-/netifd-Wechsel, Scan/Verbindungsaufbau, WAN-DNS, Update und Reboot müssen
  vor Ausrollen auf repräsentativen Geräten geprüft werden.

## Festgeschriebene Quellen

Gluon:

- [v2023.1](https://github.com/freifunk-gluon/gluon/tree/v2023.1), Commit
  `5e9afa33abcb2e7b6f28019b7532055000e43521`.
- [v2025.1](https://github.com/freifunk-gluon/gluon/tree/v2025.1), Commit
  `88cc0b7b1526a291f06573f935b05db941a456f9`.
- API jeweils `package/gluon-core/luasrc/usr/lib/lua/gluon/wireless.lua`;
  Abhängigkeiten `package/gluon-core/Makefile`;
  WAN-Regel `package/gluon-core/luasrc/lib/gluon/upgrade/110-network`;
  DNS-Wrapper `package/gluon-mesh-vpn-core/luasrc/usr/bin/`;
  Firewall-Auswahl zusätzlich `targets/generic`;
  Autoupdater-Netzwerk-Hook `package/gluon-mesh-batman-adv/files/usr/lib/autoupdater/upgrade.d/10stop-network`.

Die OpenWrt-Stände stammen aus den jeweiligen Gluon-`modules`:

- [OpenWrt für v2023.1](https://github.com/openwrt/openwrt/tree/1ec274a204a65c7f8543cf750a0b027a685818cb),
  Hostapd-Dateien `package/network/services/hostapd/files/hostapd.sh` und
  `package/network/services/hostapd/patches/700-wifi-reload.patch`.
- [OpenWrt für v2025.1](https://github.com/openwrt/openwrt/tree/b023a06cfb88ef9688a7f1c39b371a7129a85694),
  `package/network/services/hostapd/files/hostapd.uc` (`iface_gen_config`,
  `iface_load_config`, `main_obj.reload`) und
  `package/network/services/hostapd/patches/701-reload_config_inline.patch`;
  WLAN-Skripte unter `package/network/config/wifi-scripts/files/lib/netifd/`.
- [Paketfeed 22.03](https://github.com/openwrt/packages/tree/336660337ea209413f610bf47cc8fc82131ba37a),
  luaposix 35.1.
- [Paketfeed 24.10](https://github.com/openwrt/packages/tree/5b345d75962190250806e361325b72ed4c2b4f78),
  luaposix 36.2.1, `lang/lua-bit32/Makefile` und `lang/luabitop/Makefile`.
- netifd `ubus.c`: Commits
  [76d2d41b7355e02f95fbfa79affbd232fb090595](https://github.com/openwrt/netifd/blob/76d2d41b7355e02f95fbfa79affbd232fb090595/ubus.c) und
  [7901e66c5f273bceee8981bc8a0c8b0e60945f60](https://github.com/openwrt/netifd/blob/7901e66c5f273bceee8981bc8a0c8b0e60945f60/ubus.c).

Release-Hinweise:

- [Gluon v2023.1: unterstützte Migration und x86-Fehler](https://gluon.readthedocs.io/en/v2023.1.x/releases/v2023.1.html)
- [Gluon v2025.1: Migration, EdgeRouter X, WAN-DNS-Umbenennung](https://gluon.readthedocs.io/en/latest/releases/v2025.1.html)
