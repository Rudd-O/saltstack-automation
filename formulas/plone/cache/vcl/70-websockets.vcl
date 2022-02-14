vcl 4.1;

sub vcl_recv {
    call support_websockets_vcl_recv;
}

sub vcl_pipe {
    call support_websockets_vcl_pipe;
}
