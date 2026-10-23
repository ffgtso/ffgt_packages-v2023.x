return function(form, uci)
    local pkg_i18n = i18n 'ffgt-config-mode-wizard'
    local pretty_hostname = require 'pretty_hostname'
    local web_util = require 'gluon.web.util'
    local util = require 'gluon.util'
    local default_hostname = util.default_hostname()
    local hostname = pretty_hostname.get(uci)

    if hostname == default_hostname then
        local cmdstr='touch /tmp/return2wizard.hack 2>/dev/null'
        util.exec(cmdstr)
        local text = '<script> window.location.href = "/cgi-bin/config/admin/hostname";</script>'
        text = text .. pkg_i18n.translate('HOSTNAME NOT SET. Please go to %s.')
        text = "<CENTER><STRONG>" .. string.format(text, '<a href="/cgi-bin/config/admin/hostname">Hostname</a>') .. "</STRONG></CENTER>"
        form:section(Section, nil, text)
    end

    if not hostname or hostname == '' then
        hostname = pkg_i18n.translate('Not set')
    end

    local link = '<a href="/cgi-bin/config/admin/hostname">'
        .. web_util.pcdata(pkg_i18n.translate('Advanced settings / Node name'))
        .. '</a>'
    local text = web_util.pcdata(pkg_i18n.translate('Node name'))
        .. ': <strong>' .. web_util.pcdata(hostname) .. '</strong><br>'
        .. string.format(pkg_i18n.translate('To change it, go to %s.'), link)

    form:section(Section, nil, text)
end
