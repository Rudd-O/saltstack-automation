include:
- .rpm
- .docker
- .frontend

extend:
  docker-distribution socket directory:
    file:
    - require:
      - pkg: nginx
  htpasswd authentication for docker-distribution:
    file:
    - require:
      - pkg: nginx
      - pkg: docker-distribution
  nginx:
    service:
    - require:
      - test: docker-distribution accounts managed

repo server deployed:
  test.nop:
  - require:
    - test: RPM repo server deployed
    - test: Docker repo server deployed
    - test: Frontend deployed
