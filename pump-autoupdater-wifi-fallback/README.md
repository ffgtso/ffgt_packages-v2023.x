# pump-autoupdater-wifi-fallback

`pump-autoupdater-wifi-fallback` is a PUMP-aware variant of
`ffac-autoupdater-wifi-fallback`.

Its purpose is to recover nodes that have lost contact to the Freifunk mesh
after a firmware or mesh-parameter change. If the node no longer sees a
batman-adv gateway, it temporarily replaces the current wireless configuration
with a single open WiFi STA interface, connects to a visible Freifunk client
network and runs the autoupdater from there.

The package intentionally stays close to the original FFAC implementation:

* it creates the persistent `network.fallback` / `network.fallback6` sections in
  its Gluon upgrade script,
* it temporarily deletes all `wireless` `wifi-iface` sections only in the
  uncommitted UCI state,
* it calls `uci:save('wireless')` to let `wifi` apply the temporary fallback
  configuration,
* it calls `uci:revert('wireless')` afterwards.

No `/etc/config/*` files are copied or restored.

## Differences to ffac-autoupdater-wifi-fallback

### Mesh connectivity check only

The connectivity check does not look for an IPv4 default route and does not ping
autoupdater mirror hosts. It only checks whether

```sh
batctl gwl
```

contains at least one real gateway table row. The script deliberately ignores
the `batctl gwl` header, because that header contains local MAC addresses even
when no gateway is available. A gateway is detected only from rows like:

```text
* 02:ca:ff:ee:01:47 (255) 02:ca:ff:ee:01:47 [ mesh-vpn]: ...
```

If a batman-adv gateway row is present, the node is considered connected to the
mesh and the WiFi fallback is not used. A local WAN uplink without a mesh
gateway is intentionally ignored.

### PUMP restore hook

If PUMP is installed, detected by `/etc/config/pump` or UCI package `pump`, the
fallback script runs

```sh
/lib/gluon/upgrade/335-gluon-pump
```

after `uci:revert('wireless')` and again before the final network restart. This
lets PUMP re-materialize its generated configuration, such as PUMP mesh AP/STA,
`pump_uplink`, `pump_wan`, firewall, DNS helper state and tunneldigger binding.

### Supplicant dependency

This package depends on `wpa-supplicant-wolfssl` instead of
`wpa-supplicant-mini`, so it can coexist with PUMP images that need WPA3/SAE
support.

### Conflict

This package conflicts with `ffac-autoupdater-wifi-fallback`. Include only one
of them in an image.

## Configuration

`/etc/config/pump-autoupdater-wifi-fallback`:

```uci
config pump-autoupdater-wifi-fallback 'settings'
        option enabled '1'
```

By default the upgrade script initializes `enabled` from
`autoupdater.settings.enabled`, matching the original package behaviour.

## Runtime behaviour

The cron job is scheduled ten minutes after the regular autoupdater job. When
fallback is triggered, the script scans all radios for SSIDs matching
`.*[Ff][Rr][Ee][Ii][Ff][Uu][Nn][Kk].*`, tries them as open STA networks, and
runs:

```sh
/usr/sbin/autoupdater -f -b <branch>
```

If no sysupgrade happens, the script restores the standard wireless state and
restarts the network.
