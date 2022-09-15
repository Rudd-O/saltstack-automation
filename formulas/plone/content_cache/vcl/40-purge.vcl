vcl 4.1;

sub vcl_recv {
    if (req.method == "PURGE") {
{% if purgekey %}
        if (req.url ~ "^/purgekey={{ purgekey }}($|/|[?])") {
            set req.url = regsub(req.url, "^/purgekey={{ purgekey }}", "");
            /* Now normalize the URL. */
            if (req.url ~ "^/+") {
                set req.url = regsub(req.url, "^/+", "/");
            } else {
                set req.url = regsub(req.url, "^", "/");
            }
        } else {
            return (synth(401, "Not authorized to purge"));
        }
{% else %}
        return (synth(405, "Method not enabled"));
{% endif %}
    }
}
