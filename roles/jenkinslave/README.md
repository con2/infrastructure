# Jenkins slave

## Manual steps

If you are deploying code using Jenkins, you need to get the public key of the target machines
into the `known_hosts` file of the Jenkins slave. The easiest way to accomplish this is to become
the Jenkins slave user and `ssh` into the target machine (eg. `ssh root@neula.kompassi.eu`) manually.
