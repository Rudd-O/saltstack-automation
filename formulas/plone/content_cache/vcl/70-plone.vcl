vcl 4.1;

sub plone_vcl_recv {
    call sanitize_plone_cookies;
}

sub vcl_recv {
    if (req.http.Plone-Backend) {
        call plone_vcl_recv;
    }
}
