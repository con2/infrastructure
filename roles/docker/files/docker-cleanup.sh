#!/bin/bash
set -e

# NO! WE DO NOT DO THIS! Consider, for example
# - the postgresql container is exited, for some reason
# - okay, so remove it
# - and finally, remove its dangling volume
#docker ps -qaf status=exited | xargs -r docker rm

docker images -qf dangling=true | xargs -r docker rmi

# actually, let's not touch volumes after all
#docker volume ls -qf dangling=true | xargs -r docker volume rm
