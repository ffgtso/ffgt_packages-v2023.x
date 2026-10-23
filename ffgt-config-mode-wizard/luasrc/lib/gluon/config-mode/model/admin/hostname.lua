local uci = require('simple-uci').cursor()
local pretty_hostname = require 'pretty_hostname'
local util = require 'gluon.util'

local site_i18n = i18n 'gluon-site'
local help = site_i18n._translate("gluon-config-mode:hostname-help")
    or translate(
        'The node name is used solely for identification of your node, e.g. on a '
        .. 'node map. It does not affect the name (SSID) of the broadcasted WLAN.'
    )

local MAX_SUFFIX = 31 -- 37 Zeichen minus "12345-"

local function sanitize(value, limit)
    local name = tostring(value or '')

    -- Umlaute vor der Beschränkung auf ASCII umschreiben.
    local replacements = {
        {'ä', 'ae'}, {'ö', 'oe'}, {'ü', 'ue'},
        {'Ä', 'Ae'}, {'Ö', 'Oe'}, {'Ü', 'Ue'},
        {'ß', 'sz'},
    }

    for _, replacement in ipairs(replacements) do
        name = name:gsub(replacement[1], replacement[2])
    end

    name = name:gsub('[^A-Za-z0-9%-]+', '-')
    name = name:gsub('%-+', '-')
    name = name:gsub('^%-+', ''):gsub('%-+$', '')

    if limit then
        name = name:sub(1, limit):gsub('%-+$', '')
    end

    return name
end

local legacy_prefixes = {
    'ffgt', 'ffrw', 'fflip', 'freifunk',
    'gut', 'tst', 'rhwd', 'muer',
}

local function normalize_suffix(value)
    local name = sanitize(value)

    -- Bereits vorhandene PLZ und alte Community-Präfixe entfernen.
    -- Wiederholen, damit auch Kombinationen erkannt werden.
    while true do
        local previous = name
        name = name:gsub('^%d%d%d%d%d%-', '')

        for _, prefix in ipairs(legacy_prefixes) do
            if name:sub(1, #prefix + 1):lower() == prefix .. '-' then
                name = name:sub(#prefix + 2)
                break
            end
        end

        if name == previous then
            break
        end
    end

    return sanitize(name, MAX_SUFFIX)
end

local location = uci:get_first('gluon-node-info', 'location')
local zip = location
    and uci:get('gluon-node-info', location, 'zip')
local addr = location
    and uci:get('gluon-node-info', location, 'addr')

zip = tostring(zip or ''):match('^%s*(.-)%s*$')

local f = Form(translate("Node name"), help)

-- Ohne gültige PLZ keinen Hostnamen speichern.
if not zip:match('^%d%d%d%d%d$') or zip == '00000' then
    f:section(Section, nil,
        'Bitte zuerst die Geolokalisierung mit einer gültigen '
        .. 'fünfstelligen PLZ speichern: '
        .. '<a href="/cgi-bin/config/admin/geolocate">'
        .. 'Geolokalisierung öffnen</a>.'
    )
    return f
end

local default_hostname = util.default_hostname()
local current_hostname = pretty_hostname.get(uci)
local address = sanitize(addr, 26)
local mac_suffix = util.node_id():sub(-4):lower()

local suggested_suffix
if address ~= '' then
    suggested_suffix = address .. '-' .. mac_suffix
end

local initial_suffix
if not current_hostname or current_hostname == default_hostname then
    initial_suffix = suggested_suffix or ''
else
    initial_suffix = normalize_suffix(current_hostname)
end

local s = f:section(Section)
local o = s:option(
    Value,
    'hostname',
    translate("Node name") .. ': ' .. zip .. '-'
)

o.optional = false
o.datatype = 'minlength(1)'
o.default = initial_suffix
o.description =
    'Nur den Namensteil hinter der PLZ eingeben. '
    .. 'Umlaute werden umgeschrieben, Sonderzeichen durch Bindestriche '
    .. 'ersetzt und mehrfache Bindestriche zusammengefasst. '
    .. 'Der Namensteil wird auf 31 Zeichen gekürzt.'

if suggested_suffix then
    o.placeholder = suggested_suffix
else
    o.description = o.description
        .. ' Für einen Adressvorschlag fehlt die Adresse '
        .. 'in der Geolokalisierung.'
end

-- Gluon ruft validate() ohne Argument auf;
-- der übermittelte Wert steht in self.data.
function o:validate()
    if type(self.data) ~= 'string' then
        return false
    end

    self.data = normalize_suffix(self.data)
    return self.data ~= ''
end

function o:write(data)
    local suffix = normalize_suffix(data)

    -- Zusätzliche Absicherung vor dem Schreiben.
    if suffix == '' then
        return
    end

    pretty_hostname.set(uci, zip .. '-' .. suffix)
    uci:commit('system')
end

return f