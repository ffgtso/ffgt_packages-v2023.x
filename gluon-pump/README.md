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

## Benennung und Konfiguration

Das Paket verwendet konsequent den Bezeichner `pump`:

* Package: `gluon-pump`
* Feature: `pump`
* UCI-Konfiguration: `/etc/config/pump`
* Netzwerk-Interfaces: `pump_radio0`, `pump_radio1`, ...
* WLAN-Interfaces: `pump0`, `pump1`, ...

Die SSID und die Passphrase werden nicht lokal editiert, sondern aus der
Site-/Domain-Konfiguration abgeleitet:

* SSID: `PUMP-` + erster Wert aus `domain_names`
* Passphrase: Wert von `prefix6`
* Encryption: `psk3-mixed` mit `ieee80211w=1`, also WPA2/WPA3-Mixed-Mode

Im Config-Mode werden SSID und Passphrase als nicht editierbare Werte
angezeigt. Editierbar sind nur:

* `enabled`: PUMP aktivieren/deaktivieren
* `mode`: `ap` oder `sta`
* `radio`: `all`, `radio0`, `radio1`, ...

## UCI

Standardkonfiguration:

```uci
config settings 'settings'
	option enabled '0'
	option mode 'ap'
	option radio 'all'
	option mesh_no_rebroadcast '0'
```

Beispiel AP-Seite:

```sh
uci set pump.settings.enabled='1'
uci set pump.settings.mode='ap'
uci set pump.settings.radio='radio1'
uci commit pump
/lib/gluon/upgrade/335-gluon-pump
uci commit network
uci commit wireless
wifi reload
```

Beispiel STA-Seite:

```sh
uci set pump.settings.enabled='1'
uci set pump.settings.mode='sta'
uci set pump.settings.radio='radio1'
uci commit pump
/lib/gluon/upgrade/335-gluon-pump
uci commit network
uci commit wireless
wifi reload
```

Das Upgrade-Script erzeugt pro ausgewähltem Radio:

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
	option encryption 'psk3-mixed'
	option ieee80211w '1'
```

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
* Erfordert WPA3-Support über `gluon-wireless-encryption-wpa3`.
* `domain_names` darf inklusive Präfix `PUMP-` maximal 32 Zeichen ergeben.
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
