local wireless = require 'gluon.wireless'
local uci = require("simple-uci").cursor()

if wireless.device_uses_wlan(uci) then
    entry({"admin", "ssid-changer"}, model("admin/ssid-changer"), _("Offline-SSID"), 35)
end
