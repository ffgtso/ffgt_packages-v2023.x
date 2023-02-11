--[[
Copyright 2008 Steven Barth <steven@midlink.org>
Copyright 2008 Jo-Philipp Wich <xm@leipzig.freifunk.net>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0
]]--

package 'ffgt-geolocate'

local util = require 'gluon.util'
local site = require 'gluon.site'
local uci = require("simple-uci").cursor()


local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function action_geoloc(http, renderer)
	-- Determine state
	local step = tonumber(http:getenv("REQUEST_METHOD") == "POST" and http:formvalue("step")) or 1
    local location = uci:get_first("gluon-node-info", "location")
    local lat = uci:get("gluon-node-info", location, "latitude")
    local lon = uci:get("gluon-node-info", location, "longitude")

	-- Step 1: Select/enter coordinates; if some are there alredy, try reverse geolocation with them
	if step == 1 then
        if not lat then lat = 0 else lat=tonumber(lat) end
        if not lon then lon = 0 else lon=tonumber(lon) end
        -- lat / lon were no numbers ...
        if not lat then lat = 0 end
        if not lon then lon = 0 end
        if not (lat == 0 and lon == 0) then
            os.execute("/lib/gluon/ffgt-geolocate/rgeo.sh")
        end
		renderer.render_layout('admin/geolocate', { null_coords = (lat == 0 and lon == 0), }, 'ffgt-geolocate')
	-- Step 2: Try geolocate with the data entered, unless "autolocate" was selected, in which
	--         case we ignore the coordinates entered.
	elseif step == 2 then
		local autolocate = (http:formvalue("autolocate") == "1")
		if autolocate then
            os.execute("/lib/gluon/ffgt-geolocate/geolocate.sh force")
            renderer.render_layout('admin/geolocate', { autolocated = 1, }, 'ffgt-geolocate')
        else
            local newlat = tonumber(trim(http:formvalue("lat")))
            local newlon = tonumber(trim(http:formvalue("lon")))

            if not newlat or not newlon then
                renderer.render_layout('admin/geolocate', { null_coords = 1, }, 'ffgt-geolocate')
            else
                local cmdstr = string.format("/lib/gluon/ffgt-geolocate/rgeo.sh %f %f 2>/dev/null", newlat, newlon)
                os.execute(cmdstr)

                location = uci:get_first("gluon-node-info", "location")
                lat = uci:get("gluon-node-info", location, "latitude")
                lon = uci:get("gluon-node-info", location, "longitude")
                local unlocode = uci:get("gluon-node-info", location, "locode")

                if not lat then lat = 0 else lat=tonumber(lat) end
                if not lon then lon = 0 else lon=tonumber(lon) end
                -- lat / lon were no numbers ...
                if not lat then lat = 0 end
                if not lon then lon = 0 end
                if (lat == 51.892825) and (lon == 8.383708) then
                    lat=51.0
                    lon=9.0
                end

                if ((lat == 0 and lon == 0) or (lat == 51.0 and lon == 9.0)) then
                    renderer.render_layout('admin/geolocate', { rgeo_error = 1, }, 'ffgt-geolocate')
                else
                    uci:set('gluon', 'core', 'domain', unlocode)
                    uci:commit('gluon')
                    os.execute('gluon-reconfigure')
                    local cmdstr='touch /tmp/return2wizard.hack 2>/dev/null'
                    os.execute(cmdstr)
                    renderer.render_layout('admin/geolocate_done', nil, 'ffgt-geolocate')
                end
            end
        end
	elseif step == 3 then
        renderer.render_layout('admin/geolocate_eeeee', nil, 'ffgt-geolocate', { hidenav = true, })
	end
end


local geoloc = entry({"admin", "geolocate"}, call(action_geoloc), _("Geolocation"), 2)
