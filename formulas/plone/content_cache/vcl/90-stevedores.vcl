vcl 4.1;
import std; 

sub vcl_backend_response {

{% for name, data in stevedores.items() %}

{%   set from_size = data.get("for_sizes", "-").split("-")[0] %}
{%   set to_size = data.get("for_sizes", "-").split("-")[1] %}
{%   set stream = data.get("stream") %}
{%   if from_size %}
    if (std.integer(beresp.http.Content-Length, 0) >= {{ from_size }}) {
{%   endif %}
{%   if to_size %}
        if (std.integer(beresp.http.Content-Length, 0) <= {{ to_size }}) {
{%   endif %}
            set beresp.storage = storage.{{ name }};
            set beresp.http.x-storage = "storage.{{ name }}";
{%   if stream %}
            set beresp.do_stream = true;
            set beresp.http.x-stream = "yes";
{%   endif %}
{%   if to_size %}
        }
{%   endif %}
{%   if from_size %}
    }
{%   endif %}

{% endfor %}

}
