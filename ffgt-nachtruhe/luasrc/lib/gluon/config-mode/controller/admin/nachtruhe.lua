local wireless = require 'gluon.wireless'
package 'ffgt-nachtruhe'

if wireless.device_uses_wlan(uci) then
    entry({"admin", "nachtruhe"}, model("admin/nachtruhe"), _("Nachtruhe"), 31)
end
