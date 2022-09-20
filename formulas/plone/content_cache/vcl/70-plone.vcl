vcl 4.1;

sub plone_vcl_recv {
    call sanitize_plone_cookies;
}

sub vcl_recv {
    if (req.http.Plone-Backend) {
        call plone_vcl_recv;
    }
}

sub vcl_backend_fetch {
    if (bereq.http.Plone-Backend) {
        /* Disable connection reuse. */
        set bereq.http.Connection = "close";
    }
}
