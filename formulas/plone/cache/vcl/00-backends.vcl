vcl 4.1;

# Default backend definition. Set this to point to your content server.
# This will be overwritten by invocations to varnish-set-backend.
backend default {
   .host = "127.0.0.1";
   .port = "8080";
}
