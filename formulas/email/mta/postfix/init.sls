include:
- .service
- .aliases
- .virtual
- .config
- .tls

extend:
  certs ready:
    test:
    - require_in:
      - file: /etc/postfix/main.cf
