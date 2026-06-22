# gluon-l2tp-batman packages

Two Gluon/OpenWrt packages:

- `gluon-l2tp-batman-server`: extra uhttpd instance on port 49152 bound to the Gluon `next_node` / local-node addresses. `/cgi-bin/connect` creates the server-side unmanaged L2TPv3 Ethernet pseudowire and adds it to `bat0`.
- `gluon-l2tp-batman-client`: `gluon-l2tp-batman-connect [URL]` calls the CGI endpoint, creates the client-side unmanaged L2TPv3 Ethernet pseudowire and adds it to `bat0`.

Default client URL: `http://nextnode:49152/cgi-bin/connect`.

The tunnel interface MTU is set to 1500 on both sides.
