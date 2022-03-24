# Matrix formula for SaltStack

This formula helps you get a standalone, federated Matrix homeserver — the famous Matrix in a Box.

[There's an online guide on how to use this formula](https://rudd-o.com/linux-and-free-software/matrix-in-a-box).

## Pillar values

```
matrix:
  synapse:
    logging:
      Optional.  This contains a YAML python logging config file as described by
      https://docs.python.org/3.7/library/logging.config.html#configuration-dictionary-schema
      The defaults are the defaults that ship in Matrix.
```
