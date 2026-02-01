#!/bin/sh

echo -n "$(/usr/bin/jsonfilter </lib/gluon/domains/$(uci get gluon.core.domain).json -e '@.mesh_vpn.tunneldigger.brokers[*]' | sed -e 's/^.*://g' | uniq)"
