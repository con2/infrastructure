FROM postgres:9.6

COPY docker-entrypoint.d/01-config.sh /docker-entrypoint-initdb.d/01-config.sh
COPY docker-entrypoint.d/02-users.sh /docker-entrypoint-initdb.d/02-users.sh
RUN chmod 755 /docker-entrypoint-initdb.d/01-config.sh /docker-entrypoint-initdb.d/02-users.sh
