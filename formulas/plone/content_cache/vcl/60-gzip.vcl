vcl 4.1;

sub vcl_backend_response {
    if (beresp.http.content-type ~ "text" || beresp.http.content-type ~ "javascript") {
        set beresp.do_gzip = true;
    }
}
