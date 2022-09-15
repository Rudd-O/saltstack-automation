vcl 4.1;


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

sub vcl_recv {
    call support_websockets_vcl_recv;
}

sub vcl_pipe {
    call support_websockets_vcl_pipe;
}
