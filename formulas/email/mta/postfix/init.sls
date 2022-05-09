include:
- .service
- .virtual
- .config
- .tls

extend:
  certs ready:
    test:
    - require_in:
      - file: /etc/postfix/main.cf
