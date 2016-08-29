#!/bin/bash
umask 077

docker exec kompassi.eu-postgres pg_dumpall -U postgres > /var/backups/postgresql/kompassi.eu-pg_dumpall
