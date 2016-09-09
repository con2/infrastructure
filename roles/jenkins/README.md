# Jenkins deployment using Docker

## Persistent data

Jenkins keeps all its data in XML and JAR files under `/var/docker_home`. No database required.
This file is made into a volume called `{{ jenkins_hostname }}-data`.

To migrate a Jenkins installation from one machine, I did the following:

    # on the old machine, while the jenkins container is running
    docker exec -i jenkins.tracon.fi tar -cjv /var/jenkins_home > jenkins.tar.bz2
    scp jenkins.tar.bz2 new_machine:

    # on the new machine, while the jenkins container is running
    docker exec -i jenkins.tracon.fi tar -xjvC / < jenkins.tar.bz2
    docker restart jenkins.tracon.fi

This felt a little hazardous as the Jenkins container might be mutating the files while they were
being tarred/untarred. But `jenkins exec` was the easiest way to get into the same container
configuration with all the volumes etc. and it worked without any glitches.
