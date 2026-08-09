# 4830-meshstate

Gluon package for Gluon >= 2021.1.2.

Once per hour it requests

    http://setup.ipv6.4830.org/meshstate.php?node=<primary_mac>

where `<primary_mac>` is read from `/lib/gluon/core/sysconfig/primary_mac`.

The response format is manifest-like:

    <payload line 1>
    <payload line 2>
    ---
    <128-hex-character ECDSA signature>
    [more signatures ...]

The package reads the currently selected autoupdater branch from UCI and uses
all `pubkey` entries of that branch. One matching signature/key pair is
sufficient; the firmware branch's `good_signatures` value is deliberately not
used.

Signature verification does not require the `ecdsautils` command-line package.
The main program remains Lua; because `libecdsautil` exposes a C API rather than
a Lua binding, it calls a small private verifier installed as

    /usr/lib/4830-meshstate/4830-meshstate-verify

which links directly against the already used `libecdsautil`. The library's
pkg-config metadata pulls in its `libuecc` dependency as required by the public
API.

For compatibility with Gluon 2021.1.2, the private verifier additionally rejects
ECDSA signatures with `r == 0` or `s == 0` before passing them to
`libecdsautil`. This compensates for CVE-2022-24884 in the older library version
shipped by that Gluon release.

Only after successful verification is the payload (everything before `---`)
atomically renamed to:

    /tmp/meshstate/current.cfg

A download or verification failure leaves an existing `current.cfg` untouched.
The downloaded response is limited to 1 MiB and must use LF line endings.

## Installation in a Gluon tree

Place this directory below `package/`, for example:

    gluon/package/4830-meshstate/

and add the package to the site's package selection, e.g. in `site.mk`:

    GLUON_SITE_PACKAGES += 4830-meshstate

Then build Gluon normally.

The package contains a micron entry. During a normal Gluon upgrade/first boot,
`510-meshstate` chooses a random minute within the hour so that nodes do not all
contact the endpoint simultaneously. The shipped minute-0 entry is a fallback
for direct runtime installation.

## Manual test on a node

    /usr/sbin/4830-meshstate
    logread -e 4830-meshstate
    cat /tmp/meshstate/current.cfg

The output lives in `/tmp` as requested and therefore does not survive a reboot;
it will be recreated by the next successful hourly run.
