# Barman backup server for PostgreSQL

This role configures the [Barman](http://www.pgbarman.org) backup server for PostgreSQL.

Some configuration at the PostgreSQL side is also required: see the `postgresql` role (not `postgresql-docker`).

## TODO

* [ ] Recovery drills: newest or to a point in time
* [ ] SSL. Barman should always connect to PostgreSQL using TLS encryption.
* [ ] Backup status monitoring via Prometheus.
* [ ] Barman server logs to a central location, preferably EFK.
* [ ] Retention policy.
