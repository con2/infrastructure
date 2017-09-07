# Single node PostgreSQL setup within Docker

This is a simple single node PostgreSQL setup using the [official PostgreSQL image](https://hub.docker.com/r/_/postgres). This setup is intended to be a temporary solution
until the Entöprais Jareahco(TM) is load-bearing.

## Streaming backup using Barman

When the `tracon/postgres` image is used, this role enables the Dockerized PostgreSQL server to be backed up using Barman. See the `postgresql-barman` role for setting up one.
