#!/bin/sh

docker exec -it atlassian_db_1 su -l postgres -c pg_dumpall | nice pbzip2 -9 > /opt/atlassian/db-backup.sql.gz
