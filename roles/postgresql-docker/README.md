# Single node PostgreSQL setup within Docker

This is a simple single node PostgreSQL setup using the [official PostgreSQL image](https://hub.docker.com/r/_/postgres). This setup is intended to be a temporary solution
until the Entöprais Jareahco(TM) is load-bearing.

## Streaming backup using Barman

When the `tracon/postgres` image is used, this role enables the Dockerized PostgreSQL server to be backed up using Barman. See the `postgresql-barman` role for setting up one.

## Manual steps to have an existing `postgresql-docker` container use streaming backup

Assuming `nuoli` is the new server.

1. Set `postgresql_ssl_certificate` and `postgresql_ssl_certificate_key` in `tracon.yml`.
2. On your workstation, `ansible-playbook -t postgresql-docker -l yourhost tracon.yml`
3. On the Docker host, `sudo docker exec nuoli.tracon.fi-postgres /docker-entrypoint-initdb.d/01-config.sh`
4. On the Docker host, `sudo docker exec --user postgres nuoli.tracon.fi-postgres /docker-entrypoint-initdb.d/02-users.sh`
5. On your workstation, `ansible-playbook -t postgresql-docker -l yourhost tracon.yml` again to restart with the updated `postgresql.conf`.
6. On the Barman server, `cp /etc/barman.d/monokkeli.conf /etc/barman.d/nuoli.conf`
7. On the Barman server, `vim /etc/barman.d/nuoli.conf` and `:%s/monokkeli/nuoli/`
8. On the Barman server, `sudo -u barman barman receive-wal --create-slot nuoli`
9. On the Barman server, `sudo -u barman barman cron` to start `receive-wal` in background.
10. On the Barman server, `sudo -u barman barman switch-xlog nuoli` to create something to archive for `barman cron`
11. On the Barman server, `sudo -u barman barman cron` to make `WAL archive: FAILED ` go away in…
12. …on the Barman server, `sudo -u barman barman check nuoli`. It should now be `OK` across the board.
13. Finally, on the Barman server, `sudo -u barman barman backup nuoli` to perform a base backup.
