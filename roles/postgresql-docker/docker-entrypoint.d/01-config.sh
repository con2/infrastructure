#!/bin/bash
set -xue
cat >> $PGDATA/postgresql.conf << ENDHATE
wal_level = replica
max_wal_senders = 2
max_replication_slots = 2
ENDHATE

cat >> $PGDATA/pg_hba.conf << POSITIVETHOUGHTS
host replication $POSTGRES_BARMAN_DB_STREAMING_USER $POSTGRES_BARMAN_IP/32 md5
POSITIVETHOUGHTS
