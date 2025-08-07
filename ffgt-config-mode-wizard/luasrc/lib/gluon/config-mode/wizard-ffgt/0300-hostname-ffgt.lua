return function(form, uci)
	local pkg_i18n = i18n 'ffgt-config-mode-wizard'
	local site_i18n = i18n 'gluon-site'

	local pretty_hostname = require 'pretty_hostname'
	local site = require 'gluon.site'
	local util = require 'gluon.util'
    local uci = require("simple-uci").cursor()

    local location = uci:get_first("gluon-node-info", 'location')
    local addr = uci:get("gluon-node-info", location, "addr") or "FEHLER_ADDR"
    local city = uci:get("gluon-node-info", location, "city") or "FEHLER_ORT"
    local zip = uci:get("gluon-node-info", location, "zip") or "00000"
    local mac = string.sub(util.node_id(), 9)

    if not zip or not city or not addr then
        local cmdstr='touch /tmp/return2wizard.hack 2>/dev/null'
        util.exec(cmdstr)
        local text = "<script> window.location.href = "/cgi-bin/config/admin/geolocate";</script>"
        text = text .. pkg_i18n.translate('LOCATION NOT SET. Please go to %s.')
        text = "<CENTER><STRONG>" .. string.format(text, '<a href="/cgi-bin/config/admin/geolocate">Geolocate</a>') .. "</STRONG></CENTER>"
        form:section(Section, nil, text)
    end

    local current_systemhostname = uci:get_first("system", "system", "hostname")
	local current_hostname = pretty_hostname.get(uci)
	local default_hostname = util.default_hostname()
	local configured = uci:get_first('gluon-setup-mode', 'setup_mode', 'configured', false) or (current_hostname ~= default_hostname)

	if (not current_hostname) then hostname=default_hostname else hostname=current_hostname end
	hostname = hostname:gsub(" ","-")
    hostname = hostname:gsub("%p","-")
    hostname = hostname:gsub("_","-")
    hostname = hostname:gsub("%-%-","-")
    hostname = hostname:gsub("^ffgt%-", "")
    hostname = hostname:gsub("^ffrw%-", "")
    hostname = hostname:gsub("^fflip%-", "")
    hostname = hostname:gsub("^FFLIP%-", "")
    hostname = hostname:gsub("^freifunk%-", "")
    hostname = hostname:gsub("^gut%-", "")
    hostname = hostname:gsub("^tst%-", "")
    hostname = hostname:gsub("^rhwd%-", "")
    hostname = hostname:gsub("^muer%-", "")
    -- hostname = hostname:gsub("^" .. zip .. "%-", "")
    hostname = hostname:gsub("^%d%d%d%d%d%-", "")
    hostname = hostname:sub(1, 31)

    -- Limit to (37-strlen("00000-")), i. e. 31 chars
    local mystrA = string.sub(string.format("%.26s-%s", addr, mac), 1, 31)
    local mystrB = string.sub(string.format("%.26s-%s", city, mac), 1, 31)
    local mystrC = string.sub(string.format("freifunk-%s", util.node_id()), 1, 31)

	local help = site_i18n._translate("gluon-config-mode:hostname-help") or pkg_i18n.translate(
		'The node name is used solely for identification of your node, e.g. on a '
		.. 'node map. It does not affect the name (SSID) of the broadcasted WLAN.'
	)
	help = help .. "<div><br></br></div>" .. pkg_i18n.translate("Suggested names:")
	help = help .. " " .. string.format("<em>%s</em> | <em>%s</em> | <em>%s</em>", mystrA, mystrB, mystrC);
	form:section(Section, nil, help)

    if (not current_systemhostname) then hostname=mystrA end

    -- local s = form:section(Section)
    -- local suggested_hostname = s:option(ListValue, "suggested_hostname", site_i18n.translate("Suggested hostnames")
    -- suggested_hostname:value("own", translate("(Own input below)"))
    -- suggested_hostname:value("optA", mystrA)
    -- suggested_hostname:value("optB", mystrB)
    -- suggested_hostname:value("optC", mystrC)
    -- suggested_hostname.default = "own"

    local optstr=string.format("%s: %s-", pkg_i18n.translate("Node name"), zip)
	local s = form:section(Section)

	local o = s:option(Value, "hostname", optstr)
	o.datatype = 'minlength(1)'
	if site.config_mode.hostname.optional(true) then
		o.optional = true
		o.placeholder = default_hostname
	end
    -- if configured then
		o.default = hostname
	-- end

	function o:write(data)
	    local newname = data
        newname = newname:gsub(" ","-")
        newname = newname:gsub("%p","-")
        newname = newname:gsub("_","-")
        newname = newname:gsub("%-%-","-")
        newname = newname:gsub("^ffgt%-", "")
        newname = newname:gsub("^ffrw%-", "")
        newname = newname:gsub("^fflip%-", "")
        newname = newname:gsub("^FFLIP%-", "")
        newname = newname:gsub("^freifunk%-", "")
        newname = newname:gsub("^gut%-", "")
        newname = newname:gsub("^tst%-", "")
        newname = newname:gsub("^rhwd%-", "")
        newname = newname:gsub("^muer%-", "")
        newname = newname:gsub("^%d%d%d%d%d%-", "")
        newname = zip .. "-" .. newname
        newname = newname:sub(1, 37)

		pretty_hostname.set(uci, newname)
		uci:commit('system')

	end

	return {'system'}
end
