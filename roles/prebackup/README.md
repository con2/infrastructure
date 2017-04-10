# Pre-backup scripts for external backup system

In our infrastructure there is an external backup system (managed by Kyuu) that connects to machines each night over SSH, issues the `/usr/local/sbin/pre-backup` command and then collects the contents of (at least) the following directories:

* `/etc`
* `/srv`
* `/var/backup`

The pre-backup script is expected to eg. dump databases and do any other steps necessary to ensure a consistent backup.

This role sets up the said script to run any executable scripts from under `/etc/pre-backup.d` so that multiple roles may define their pre-backup actions. This facility is used at least by the following roles:

* `jenkins`
* `postgresql-docker`
* `tracontent`

