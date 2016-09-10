#!/bin/bash
umask 077

docker exec jenkins.tracon.fi-postgres pg_dumpall -U postgres > /var/backups/postgresql/jenkins.tracon.fi-pg_dumpall
docker exec jenkins.tracon.fi tar -c /var/jenkins_home > /var/backups/jenkins/jenkins_home.tar
