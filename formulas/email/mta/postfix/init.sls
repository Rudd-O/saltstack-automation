include:
- .service
- .virtual
- .config
- .tls

extend:
  postfix certs ready:
    test:
    - require_in:
      - file: /etc/postfix/main.cf
