#!/bin/bash
set -xue
cat >> $PGDATA/postgresql.conf << ENDHATE
wal_level = hot_standby
max_wal_senders = 3
max_replication_slots = 3
ssl = on
ssl_cert_file = '/server.crt'
ssl_key_file = '/server.key'
ENDHATE

cat >> $PGDATA/pg_hba.conf << POSITIVETHOUGHTS
host replication $POSTGRES_BARMAN_DB_STREAMING_USER $POSTGRES_BARMAN_IP/32 md5
POSITIVETHOUGHTS
