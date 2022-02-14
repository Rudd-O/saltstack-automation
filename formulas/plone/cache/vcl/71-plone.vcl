vcl 4.1;

sub vcl_recv {
    call sanitize_plone_cookies;
}
