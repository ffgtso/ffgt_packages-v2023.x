# pump-autoupdater-wifi-fallback

`pump-autoupdater-wifi-fallback` is a PUMP-aware recovery package for Gluon
nodes that have become detached from the Freifunk mesh after a firmware or mesh
parameter change.

It is based on the idea of `ffac-autoupdater-wifi-fallback`: if a node has no
working mesh connectivity for a configurable time, it temporarily connects as a
WiFi station to a visible open Freifunk client network and runs the Gluon
autoupdater from there.

The package differs from `ffac-autoupdater-wifi-fallback` in two important ways:

1. The connectivity check is mesh-focused. It only checks whether `batctl gwl`
   returns at least one B.A.T.M.A.N. gateway. IPv4 WAN state is deliberately not
   used as the decision criterion.
2. Before fallback mode is entered, the package takes file-based snapshots of
   the relevant UCI configuration files. After the autoupdater attempt, it
   restores those snapshots and, if PUMP is installed, runs
   `/lib/gluon/upgrade/335-gluon-pump` again. This recreates PUMP Mesh AP/STA,
   PUMP WiFi uplink, `pump_wan`, firewall membership, DNS helper state and
   Tunneldigger binding according to `/etc/config/pump`.

## Intended use case

This package is meant for nodes that were disconnected from the mesh by an
upgrade ordering problem. A typical case is a mesh chain where downstream nodes
are not upgraded before the node that provides their mesh path, or where mesh
parameters changed so that the node no longer sees a B.A.T.M.A.N. gateway.

In that situation, the node can still see a nearby open Freifunk client SSID.
The package temporarily replaces the active WiFi interfaces with a single STA
interface named `fallback`, obtains DHCP on `network.fallback`, runs
`autoupdater -f`, and then restores the original configuration if no sysupgrade
has taken over.

## Compatibility with PUMP

When PUMP is installed, the fallback run is intentionally temporary and
restorative:

- `wireless.pump_radioX` sections are restored.
- `wireless.pump_uplink` is restored.
- exclusive-radio disable states kept in `/etc/config/pump` are preserved.
- `/lib/gluon/upgrade/335-gluon-pump` is executed after restoring the UCI
  snapshots.
- the PUMP WiFi uplink's `pump_wan`/`pump_wan6` state is materialized again.
- Tunneldigger `bind_interface` is re-applied by PUMP, for example to `pumpwan`.

The package is a replacement for `ffac-autoupdater-wifi-fallback`, not a package
to install alongside it. The Makefile declares a conflict with
`ffac-autoupdater-wifi-fallback`.

## Connectivity check

The recovery mode is entered only if the configured delay has elapsed and this
check fails:

```sh
batctl gwl
```

The check is considered successful as soon as the output contains at least one
MAC address, i.e. at least one B.A.T.M.A.N. gateway is known. DNS, IPv4 default
routes and reachability of update mirrors are intentionally ignored for deciding
whether the node is still connected to the mesh.

## Configuration

The package uses `/etc/config/pump-autoupdater-wifi-fallback`:

```uci
config pump-autoupdater-wifi-fallback 'settings'
	option enabled '1'
	option outage_delay '7200'
	option min_uptime '3600'
	option ssid_pattern '.*[Ff][Rr][Ee][Ii][Ff][Uu][Nn][Kk].*'
```

### `enabled`

`1` enables the fallback mechanism, `0` disables it. On first install, the value
is derived from `autoupdater.settings.enabled`.

### `outage_delay`

Number of seconds the node must be without a B.A.T.M.A.N. gateway before
fallback mode is attempted. Default: `7200` seconds.

### `min_uptime`

Minimum uptime before checks can trigger fallback mode. Default: `3600` seconds.
This avoids false positives during early boot.

### `ssid_pattern`

Lua pattern for open client SSIDs that may be used as fallback networks. The
default matches SSIDs containing `Freifunk`, case-insensitively.

Only open networks are configured by this package:

```uci
config wifi-iface 'fallback'
	option mode 'sta'
	option network 'fallback'
	option encryption 'none'
```

## Runtime flow

1. Hourly cron/micron execution.
2. Check `enabled`, autoupdater state and minimum uptime.
3. Run `batctl gwl` and look for a gateway MAC address.
4. If no gateway is present for `outage_delay` seconds, scan all enabled radios
   for SSIDs matching `ssid_pattern`.
5. Take snapshots of:
   - `/etc/config/wireless`
   - `/etc/config/network`
   - `/etc/config/firewall`
   - `/etc/config/tunneldigger`
   - `/etc/config/pump` if present
6. Temporarily remove all `wifi-iface` sections and create only the fallback STA.
7. Run `/usr/sbin/autoupdater -f -b <branch>`.
8. If no sysupgrade takes over, restore the snapshots.
9. If PUMP is installed, run `/lib/gluon/upgrade/335-gluon-pump`.
10. Commit restored UCI state and restart the network.

## Files

```text
/etc/config/pump-autoupdater-wifi-fallback
/usr/sbin/pump-autoupdater-wifi-fallback
/usr/lib/lua/pump-autoupdater-wifi-fallback/util.lua
/lib/gluon/upgrade/512-pump-autoupdater-wifi-fallback
/usr/lib/micron.d/pump-autoupdater-wifi-fallback
```

## Notes

The fallback operation is intentionally disruptive while it is active: all normal
WiFi interfaces are temporarily removed so the selected radio can associate with
the open client network. This is acceptable because the package only enters this
mode after the node has already lost its B.A.T.M.A.N. gateway for the configured
delay.
