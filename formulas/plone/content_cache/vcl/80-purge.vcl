vcl 4.1;

sub vcl_recv {
    if (req.method == "PURGE") {
        return(purge);
    }
}
