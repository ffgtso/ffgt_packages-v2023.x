/*
  Copyright (c) 2016, Matthias Schiffer <mschiffer@universe-factory.net>
  Copyright (c) 2016, Karsten Böddeker <freifunk@kb-light.de>
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


#include <respondd.h>
#include <json-c/json.h>
#include <uci.h>
#include <stdbool.h>
#include <string.h>

static bool enabled_option(struct uci_context *ctx, struct uci_section *s, const char *key) {
	const char *v = uci_lookup_option_string(ctx, s, key);
	return v && (!strcmp(v, "1") || !strcmp(v, "true") || !strcmp(v, "yes") || !strcmp(v, "on"));
}

static bool fallback_enabled(void) {
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *manager, *updater;
	struct uci_section *m, *u;
	bool enabled = false;
	if (!ctx) return false;
	ctx->flags &= ~UCI_FLAG_STRICT;
	if (uci_load(ctx, "4830-offline-manager", &manager) || uci_load(ctx, "autoupdater", &updater)) goto out;
	m = uci_lookup_section(ctx, manager, "settings");
	u = uci_lookup_section(ctx, updater, "settings");
	if (m && u) enabled = enabled_option(ctx, m, "enabled")
		&& enabled_option(ctx, m, "autoupdate_enabled") && enabled_option(ctx, u, "enabled");
out:
	uci_free_context(ctx);
	return enabled;
}

static struct json_object *respondd_provider_nodeinfo(void) {
	struct json_object *ret = json_object_new_object();
	struct json_object *software = json_object_new_object();
	struct json_object *autoupdater = json_object_new_object();
	json_object_object_add(autoupdater, "wifi-fallback", json_object_new_boolean(fallback_enabled()));
	json_object_object_add(software, "autoupdater", autoupdater);
	json_object_object_add(ret, "software", software);
	return ret;
}

const struct respondd_provider_info respondd_providers[] = {
	{"nodeinfo", respondd_provider_nodeinfo},
	{}
};
