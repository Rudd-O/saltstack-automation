include:
- .prepare
- .upgrade
- .cleanup

extend:
  Preupgrade:
    test:
    - require:
      - test: Preparation complete
  Postupgrade:
    test:
    - require_in:
      - test: Cleanup begun
