# gluon-pump

`gluon-pump` implementiert PUMP, **Premium Ultra Mesh Plus**, als
verschlüsselte Infrastruktur-WLAN-Verbindung für Gluon-Knoten. Statt das
Batman-Mesh ausschließlich über 802.11s auf dem gleichen Funkkanal wie die
Client-SSID zu transportieren, erzeugt das Paket eine zusätzliche SSID und
bindet diese als `gluon_mesh`-Interface an batman-adv an.

Die PUMP-SSID kann wahlweise als Access Point (`ap`) oder als Station
(`sta`) betrieben werden. Damit lassen sich Punkt-zu-Punkt- und
Punkt-zu-Mehrpunkt-Strecken mit Gluon-Firmware realisieren, zum Beispiel für
geplante 2,4-GHz- oder 5-GHz-Uplinks zwischen Standorten.

## Zielbild

Ein typisches Setup sieht so aus:

```text
Gluon Standort A                         Gluon Standort B
----------------                         ----------------
client0: Freifunk-AP                     client0: Freifunk-AP
mesh_radio0: optional 802.11s            mesh_radio0: optional 802.11s
pump0: PUMP AP  <==== WPA2/WPA3 ====>    pump0: PUMP STA
          \                               /
           \---- batman-adv / bat0 ------/
```

Die PUMP-WLAN-Verbindung ist dabei kein Clientnetz und kein WAN-Uplink. Sie
ist ein zusätzlicher batman-adv-Hardif. Layer-3, Gatewayauswahl, Clientbridge
und Mesh-VPN bleiben unverändert beim vorhandenen Gluon-Setup.

Zusätzlich enthält das Paket einen Konfigurationsabschnitt **WiFi-Uplink**.
Damit kann ein empfangenes WLAN als upstream WAN verwendet werden, wenn kein
Ethernet-WAN vorhanden ist oder der Knoten bewusst per WLAN ins Internet
gebracht werden soll. Dieser Modus ist kein Batman-Transport. Er erzeugt ein
dediziertes geroutetes Layer-3-Uplink-Interface `pump_wan`/`pump_wan6`; das
virtuelle WLAN-Netdev heißt `pumpwan`.

## Benennung und Konfiguration

Das Paket verwendet konsequent den Bezeichner `pump`:

* Package: `gluon-pump`
* Feature: `pump`
* UCI-Konfiguration: `/etc/config/pump`
* Netzwerk-Interfaces: `pump_radio0`, `pump_radio1`, ...
* WLAN-Interfaces: `pump0`, `pump1`, ...

Die SSID und die Passphrase werden nicht lokal editiert, sondern aus der
Site-/Domain-Konfiguration abgeleitet:

* SSID: `PUMP-` + Wert aus `gluon.core.domain`; falls nicht gesetzt: `PUMP-nix`
* Passphrase: Wert von `prefix6` aus der Site-Konfiguration
* Encryption: `sae-mixed` mit `ieee80211w=1`, also WPA2/WPA3-Mixed-Mode

Im Config-Mode werden SSID und Passphrase als nicht editierbare Werte
angezeigt. Editierbar sind:

* `enabled`: PUMP aktivieren/deaktivieren
* `mode`: `ap` oder `sta`
* `radio`: `all`, `radio0`, `radio1`, ...
* Kanal je ausgewähltem Radio, aber nur im AP-Modus
* HT-Modus je ausgewähltem Radio, im AP- und STA-Modus
* WiFi-Uplink: Auswahl eines empfangenen WLANs als WAN-Ersatz
* WiFi-Uplink: HT-Modus und Power-Save-Verhalten

Kanal und HT-Modus werden Gluon-/OpenWrt-konform am jeweiligen `wifi-device`
gespeichert:

```uci
config wifi-device 'radio1'
	option channel '44'
	option htmode 'VHT80'
```

Zusätzlich speichert PUMP die im Config-Mode gewählten Werte unter
`pump.settings.radioX_channel` und `pump.settings.radioX_htmode`, damit das
Upgrade-Script die Werte deterministisch erneut auf die `wireless`-Konfiguration
anwenden kann.

## AP- und STA-Verhalten

### AP-Modus

Im AP-Modus kann für jedes ausgewählte Radio ein Kanal und ein HT-Modus
festgelegt werden. Nicht ausgewählte Radios zeigen im Config-Mode keine
PUMP-Kanal-/HT-Felder und werden vom PUMP-Upgrade-Script nicht verändert.

Sobald PUMP Kanal oder HT-Modus verwaltet, setzt das Paket:

```sh
uci set gluon.wireless.preserve_channels='1'
```

Das ist notwendig, weil Gluons `200-wireless` die WLAN-Kanäle bei Upgrades sonst
wieder aus `site.conf` und die Kanalbreite auf Gluons Default zurücksetzt.

### STA-Modus

Im STA-Modus gibt es bewusst keine Kanalauswahl. Die STA-Seite soll jeden AP mit
der generierten PUMP-SSID finden können. Das Paket setzt das ausgewählte Radio
auf:

```uci
option channel 'auto'
```

Der HT-Modus bleibt auswählbar. Bei `automatic / best available` wählt das Paket
den höchsten vom Treiber gemeldeten Modus in dieser Reihenfolge:

```text
HE160, HE80, HE40, HE20, VHT160, VHT80, VHT40, VHT20, HT40, HT20
```

Die konkrete Kanalbreite der Verbindung wird dann mit dem AP ausgehandelt.

Wichtig: Bei OpenWrt/mac80211 kann ein Radio im STA-Modus nur dann frei scannen
und dem AP-Kanal folgen, wenn keine anderen AP- oder Mesh-VIFs auf demselben
PHY den Kanal festnageln. Deshalb deaktiviert PUMP im STA-Modus alle anderen
`wifi-iface`-Sections auf dem ausgewählten Radio temporär und merkt sich deren
vorherigen `disabled`-Status in internen `pump.settings.iface_*_disabled`-
Optionen. Beim Wechsel zurück in den AP-Modus, bei Auswahl eines anderen Radios
oder beim Deaktivieren von PUMP werden diese Zustände wiederhergestellt.


## WiFi-Uplink

Der Abschnitt **WiFi-Uplink** ist unabhängig von PUMP-AP/STA. Er scannt die
verfügbaren Radios und bietet unterstützte empfangene WLANs im Config-Mode zur
Auswahl an. Der ausgewählte Eintrag speichert:

```uci
option uplink_enabled '1'
option uplink_radio 'radio1'
option uplink_ssid 'UpstreamSSID'
option uplink_bssid 'aa:bb:cc:dd:ee:ff'
option uplink_bssid_lock '1'      # 1: nur diese BSSID, 0: beliebiger AP mit dieser SSID
option uplink_encryption 'psk2'   # oder none, psk, sae, sae-mixed
option uplink_key '...'
```

Das Upgrade-Script erzeugt daraus ein dediziertes Layer-3-STA-Interface.
Es wird bewusst nicht in Gluons `br-wan` gebridged:

```uci
config interface 'pump_wan'
	option proto 'dhcp'
	option auto '1'
	option peerdns '0'

config interface 'pump_wan6'
	option proto 'dhcpv6'
	option ifname '@pump_wan'
	option reqprefix 'no'
	option peerdns '0'

config wifi-iface 'pump_uplink'
	option device 'radio1'
	option network 'pump_wan'
	option mode 'sta'
	option ifname 'pumpwan'
	option ssid 'UpstreamSSID'
	# option bssid wird nur gesetzt, wenn uplink_bssid_lock=1 ist
	option bssid 'aa:bb:cc:dd:ee:ff'
	option encryption 'psk2'
	option key '...'
```


Die Auswahl des Upstream-Netzes setzt SSID, Radio, Verschlüsselung und eine
vorbelegte BSSID. Die BSSID ist absichtlich ein separates Feld: Die Serverlogik
schreibt die BSSID des ausgewählten APs beim Speichern in dieses Feld; danach
kann sie manuell geändert werden. Mit `uplink_bssid_lock`
wird gesteuert, ob `wireless.pump_uplink.bssid` gesetzt wird. Bei
`uplink_bssid_lock='0'` wird keine BSSID in der `wifi-iface`-Section gesetzt;
der Supplicant darf dann jeden AP mit passender SSID und Verschlüsselung
verwenden.

Der WiFi-Uplink verwendet das gewählte Radio exklusiv. Während er aktiv ist,
werden alle anderen `wifi-iface`-Sections auf diesem Radio deaktiviert, auch
Client-AP, 802.11s-Mesh oder ein PUMP-Interface. Die vorherigen `disabled`-
Zustände werden unter internen `pump.settings.iface_*_disabled`-Optionen
gesichert und beim Deaktivieren oder Radio-Wechsel wiederhergestellt.

Für den WiFi-Uplink wird kein Kanal festgelegt. Das Radio wird auf
`channel auto` gesetzt, damit der STA-Modus dem ausgewählten AP folgen kann.
Der HT-Modus kann im Config-Mode gesetzt werden. Bei `automatic / best available`
wird der beste vom Treiber gemeldete Modus verwendet; bei instabilen Upstream-APs
kann ein konservativer Modus wie `VHT80`, `HE80`, `HT40` oder `HT20` gewählt
werden. Sobald weder PUMP noch WiFi-Uplink aktiv sind und PUMP selbst
`gluon.wireless.preserve_channels` gesetzt hatte, entfernt das Paket diese
Option und ruft wieder `/lib/gluon/upgrade/200-wireless` auf; damit greifen
wieder die WLAN-Einstellungen aus der `site.conf`.

Unterstützt werden offene Netze sowie übliche WPA/WPA2/WPA3-Personal-Netze.
Enterprise-/802.1X-Netze werden im Scan nicht als auswählbare Uplinks
behandelt.

`pump_wan6` wird immer mit angelegt, damit ein IPv6-fähiger Upstream per
DHCPv6/Router Advertisements genutzt werden kann. Bei reinen IPv4-Uplinks kann
`ifstatus pump_wan6` dauerhaft `pending` anzeigen und `odhcp6c` kann Meldungen
wie `Failed to send RS` oder `Failed to send SOLICIT` ausgeben. Das ist
unkritisch, solange `pump_wan` up ist und eine IPv4-Adresse sowie Default-Route
erhalten hat.

### Stabilität des WiFi-Uplinks

Ein laufender WiFi-Uplink kann im Log gelegentlich Meldungen wie
`CTRL-EVENT-BEACON-LOSS` erzeugen. Entscheidend ist zunächst, ob das Interface
verbunden bleibt, DHCP funktioniert und die Default-Route erhalten bleibt.

PUMP deaktiviert Power Saving für das STA-Netdev `pumpwan` standardmäßig:

```uci
option uplink_powersave '0'
```

Zusätzlich setzt ein Hotplug-Script beim `ifup` von `pump_wan` nochmals:

```sh
iw dev pumpwan set power_save off
```

Das reduziert Beacon-Loss-Probleme auf Treiber/AP-Kombinationen, bei denen
Station-Power-Save den Uplink stört. Wer Power Saving ausdrücklich verwenden
möchte, kann es im Config-Mode aktivieren oder per UCI setzen:

```sh
uci set pump.settings.uplink_powersave='1'
```

Bei weiterhin häufigem Beacon-Loss sollte zusätzlich die BSSID fixiert und der
WiFi-Uplink-HT-Modus konservativer gesetzt werden, z. B. `VHT80` statt
automatisch maximaler Breite.

### Tunneldigger / Mesh-VPN über WiFi-Uplink

Tunneldigger kann per `bind_interface` an ein konkretes Linux-Netdev gebunden
werden. Viele Gluon-Sites setzen hier standardmäßig `br-wan`. Da PUMP den
WiFi-Uplink bewusst nicht in `br-wan` bridged und `br-wan` bei reinem
WiFi-Uplink fehlen kann, würde Tunneldigger sonst mit Meldungen wie
`Failed to bind to device!` starten.

Wenn der WiFi-Uplink aktiv ist, speichert PUMP deshalb den bisherigen Wert von
`tunneldigger.<broker>.bind_interface` und setzt ihn für aktive Broker-Sections
auf:

```uci
option bind_interface 'pumpwan'
```

Beim Deaktivieren des WiFi-Uplinks wird der vorherige Wert wiederhergestellt.
Der Config-Mode startet Tunneldigger nach einer WiFi-Uplink-Änderung neu, damit
der neue Bind sofort greift.

## Rückkehr zur site.conf

Wenn PUMP und WiFi-Uplink deaktiviert sind und das Paket selbst zuvor
`gluon.wireless.preserve_channels=1` gesetzt hatte, entfernt das Paket diese
Option wieder und ruft `/lib/gluon/upgrade/200-wireless` auf. Dadurch greifen
wieder die WLAN-Einstellungen der `site.conf`, also insbesondere Kanal und
Gluon-Default-HT-Modus.

Hat `gluon.wireless.preserve_channels` bereits vor PUMP auf `1` gestanden,
betrachtet PUMP diese Einstellung nicht als Eigentum des Pakets und löscht sie
beim Deaktivieren nicht.

## UCI

Standardkonfiguration:

```uci
config settings 'settings'
	option enabled '0'
	option mode 'ap'
	option radio 'all'
	option mesh_no_rebroadcast '0'
	option preserve_channels '0' # intern: Ownership für preserve_channels
	option uplink_enabled '0'
	option uplink_radio ''
	option uplink_ssid ''
	option uplink_bssid ''
	option uplink_bssid_lock '1'
	option uplink_encryption 'auto'
	option uplink_key ''
	option uplink_htmode 'auto'
	option uplink_powersave '0'
	option uplink_network_iface '0' # intern: Ownership für network.pump_wan/pump_wan6
	option tunneldigger_bind_interface '0' # intern: Ownership für Tunneldigger bind_interface
```

Beispiel AP-Seite:

```sh
uci set pump.settings.enabled='1'
uci set pump.settings.mode='ap'
uci set pump.settings.radio='radio1'
uci set pump.settings.radio1_channel='44'
uci set pump.settings.radio1_htmode='VHT80'
uci commit pump
/lib/gluon/upgrade/335-gluon-pump
uci commit gluon
uci commit network
uci commit wireless
wifi reload
```

Das Upgrade-Script setzt daraus zusätzlich:

```uci
config wifi-device 'radio1'
	option channel '44'
	option htmode 'VHT80'
```

Beispiel STA-Seite mit automatischem/bestem HT-Modus:

```sh
uci set pump.settings.enabled='1'
uci set pump.settings.mode='sta'
uci set pump.settings.radio='radio1'
uci set pump.settings.radio1_htmode='auto'
uci commit pump
/lib/gluon/upgrade/335-gluon-pump
uci commit gluon
uci commit network
uci commit wireless
wifi reload
```

Das Upgrade-Script setzt daraus:

```uci
config wifi-device 'radio1'
	option channel 'auto'
	option htmode '<bester unterstützter Modus>'
```

Außerdem werden auf `radio1` andere VIFs wie `client_radio1`, `owe_radio1`,
`mesh_radio1` oder lokal ergänzte AP-VIFs deaktiviert, solange PUMP auf diesem
Radio im STA-Modus läuft.

Das Upgrade-Script erzeugt pro ausgewähltem Radio außerdem:

```uci
config interface 'pump_radio1'
	option proto 'gluon_mesh'
	option transitive '1'
	option fixed_mtu '1'

config wifi-iface 'pump_radio1'
	option device 'radio1'
	option network 'pump_radio1'
	option mode 'ap'      # oder 'sta'
	option ifname 'pump1'
	option ssid 'PUMP-...'
	option key '...prefix6...'
	option encryption 'sae-mixed'
	option ieee80211w '1'
```


Beispiel WiFi-Uplink:

```sh
uci set pump.settings.uplink_enabled='1'
uci set pump.settings.uplink_radio='radio1'
uci set pump.settings.uplink_ssid='UpstreamSSID'
uci set pump.settings.uplink_bssid='aa:bb:cc:dd:ee:ff'
uci set pump.settings.uplink_bssid_lock='1'   # oder '0' für beliebige BSSID
uci set pump.settings.uplink_encryption='psk2'
uci set pump.settings.uplink_key='upstream-passphrase'
uci commit pump
/lib/gluon/upgrade/335-gluon-pump
uci commit pump
uci commit gluon
uci commit network
uci commit wireless
/etc/init.d/network reload
wifi reload
```

Das Upgrade-Script bindet den WiFi-Uplink nicht direkt an `network.wan`, weil
`network.wan` in Gluon als Bridge (`br-wan`) erzeugt wird. Ein normales
802.11-STA-Interface kann ohne WDS/4addr nicht in diese Bridge; netifd meldet
sonst `BRIDGE_NOT_ALLOWED`. PUMP nutzt deshalb `network.pump_wan`/`pump_wan6`
als dedizierte DHCP-Uplink-Interfaces. Der Config-Mode führt den notwendigen
Upgrade- und Reload-Schritt automatisch aus.

## Einbindung in eine Site

Als externen Feed einbinden, zum Beispiel in `modules`:

```make
GLUON_SITE_FEEDS='pump'
PACKAGES_PUMP_REPO=https://example.org/freifunk/gluon-pump.git
PACKAGES_PUMP_COMMIT=<commit>
PACKAGES_PUMP_BRANCH=main
```

Dann in `image-customization.lua`:

```lua
features {
  'mesh-batman-adv-15',
  'web-advanced',
  'wireless-encryption-wpa3',
  'pump',
}
```

Alternativ kann das Paket direkt in `GLUON_SITE_PACKAGES` aufgenommen werden:

```make
GLUON_SITE_PACKAGES += gluon-pump
```

## Voraussetzungen und Grenzen

* Erfordert Gluon ab `v2023.1.x`.
* Erfordert batman-adv, also typischerweise `mesh-batman-adv-15`.
* Erfordert WPA3-AP-Support über `gluon-wireless-encryption-wpa3`.
* Erfordert für PUMP-STA und WiFi-Uplink zusätzlich `wpa-supplicant-wolfssl`, da `hostapd-wolfssl` nur den Authenticator/AP-Teil bereitstellt.
* Erfordert `libiwinfo-lua` für Kanal- und HT-Modus-Listen im Config-Mode.
* `gluon.core.domain` darf inklusive Präfix `PUMP-` maximal 32 Zeichen ergeben.
  Ist die SSID länger, wird PUMP nicht aktiviert und im Config-Mode wird eine
  Warnung angezeigt.
* `prefix6` muss ein gültiger WPA-Key sein: 8 bis 63 druckbare ASCII-Zeichen.
* AP/STA-Infrastruktur ersetzt kein 802.11s-Mesh auf beliebigen Nachbarkanälen.
  Die PUMP-Strecke muss wie ein geplanter Link behandelt werden: Kanal,
  Bandbreite, Sendeleistung, Antennen, DFS/Outdoor-Regeln und Airtime sollten
  bewusst geplant werden.
* `mesh_no_rebroadcast` ist vorhanden, aber standardmäßig deaktiviert. Für
  echte Punkt-zu-Punkt-Strecken kann es sinnvoll sein; bei Punkt-zu-Mehrpunkt
  sollte es nur nach Test aktiviert werden.

## Betriebshinweise

Für Standortstrecken empfiehlt sich je Seite ein dediziertes Radio. Die
Freifunk-Client-APs können dann auf anderen Kanälen laufen als der PUMP-Link.
Das reduziert die Konkurrenz zwischen Clientverkehr und Meshtransport und
vermeidet die typische 802.11s-Situation, bei der Client-AP und Mesh auf dem
gleichen Kanal Airtime teilen.

PUMP ist bewusst keine automatische Nachbarschafts-Mesh-Funktion. Es ist als
Werkzeug für geplante Funkstrecken gedacht, bei denen AP- und STA-Seite
administrativ zusammengehören und dieselbe Site-/Domain-Konfiguration nutzen.


## Notes for 0.1.10 / 0.1.11 / 0.1.12

* WiFi uplink stores the selected AP BSSID server-side after saving; the live form no longer relies on JavaScript prefill.
* WPA2/WPA3 mixed mode uses OpenWrt/Gluon UCI encryption `sae-mixed`; existing `psk3-mixed` settings are normalized on write.
* The WiFi uplink STA no longer forces a generated `macaddr`; mac80211 chooses the STA address, which avoids VIF creation failures on targets that reject the generated address.
* 0.1.11 moves the WiFi uplink off Gluon's `br-wan` bridge and onto dedicated `pump_wan`/`pump_wan6` DHCP interfaces, fixing `BRIDGE_NOT_ALLOWED` on STA interfaces.
* 0.1.12 documents that `pump_wan6` may remain pending on IPv4-only uplinks; this is harmless when `pump_wan` is up.
* 0.1.13 binds active Tunneldigger broker sections to `pumpwan` while WiFi-Uplink is active and restores their previous `bind_interface` values when WiFi-Uplink is disabled.
* 0.1.14 adds WiFi-Uplink HT-mode selection and keeps STA power saving disabled by default, including a hotplug safeguard for `pumpwan`.
* 0.1.15 fixes Config Mode persistence of `tunneldigger.<broker>.bind_interface`: after running the PUMP upgrade script, Config Mode commits the refreshed UCI state instead of overwriting it with the pre-upgrade Lua cursor.


### WiFi-Uplink network model

The WiFi uplink is configured as a normal station interface, but it is **not**
added to Gluon's generated `wan` bridge. A non-WDS 802.11 station cannot be
enslaved into a Linux bridge; OpenWrt/mac80211 rejects such a setup with
`BRIDGE_NOT_ALLOWED`. Therefore PUMP creates a dedicated routed network
interface instead:

```uci
config interface 'pump_wan'
	option proto 'dhcp'
	option auto '1'
	option peerdns '0'

config interface 'pump_wan6'
	option proto 'dhcpv6'
	option ifname '@pump_wan'
	option reqprefix 'no'
	option peerdns '0'

config wifi-iface 'pump_uplink'
	option network 'pump_wan'
	option mode 'sta'
	option ifname 'pumpwan'
```

This gives the node a real Layer-3 uplink/default route without trying to bridge
the STA interface into `br-wan`. Legacy package state that added `pumpwan` to
`network.wan.ifname` or created `gluon.iface_pumpwan` is removed on the next
PUMP upgrade run.
