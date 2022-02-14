vcl 4.1;

sub sanitize_plone_cookies {
    # Cookie sanitization for Plone caching.
    if (req.http.Cookie ~ "(^|; *)__ac" || req.http.Cookie ~ "(^|; *)__cp" || req.http.Authorization) {
        # If the user is logged in, we let Plone-specific authorized user cookies through.
        set req.http.Temp-Cookie = ";" + req.http.Cookie;
        set req.http.Temp-Cookie = regsuball(req.http.Cookie, "; +", ";");
        set req.http.Temp-Cookie = regsuball(req.http.Temp-Cookie, ";(statusmessages|__cp|__ac(_name|_password|_persistent|)|_ZopeId|ZopeId|_tree-s|_fc.*|DF_filter|DF_expert)=", "; \1=");
        set req.http.Temp-Cookie = regsuball(req.http.Temp-Cookie, ";[^ ][^;]*", "");
        set req.http.Temp-Cookie = regsuball(req.http.Temp-Cookie, "^[; ]+|[; ]+$", "");

        if (req.http.Temp-Cookie == "") {
            unset req.http.Cookie;
        } else {
            set req.http.Cookie = req.http.Temp-Cookie;
        }
        unset req.http.Temp-Cookie;
    } else {
        unset req.http.Cookie;
    }
}

sub support_websockets_vcl_recv {
    if (req.http.Upgrade ~ "(?i)websocket") {
        return (pipe);
    }
}

sub support_websockets_vcl_pipe {
    if (req.http.Upgrade) {
        set bereq.http.Upgrade = req.http.Upgrade;
        set bereq.http.Connection = req.http.Connection;
    }
}
