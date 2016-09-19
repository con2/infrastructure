#!/bin/bash
set -e
cd /srv/letsencrypt
find . -ipath './secrets/*/renew.sh' -exec bash \{} \;
