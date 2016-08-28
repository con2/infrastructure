# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "ubuntu/xenial64"
  config.vm.network "private_network", type: "dhcp"

  config.vm.provider :virtualbox do |virtualbox|
    virtualbox.cpus = 4
    virtualbox.memory = 1024
  end

  config.vm.provision :shell do |shell|
    shell.inline = "apt-get update && apt-get -y dist-upgrade && apt-get -y install python"
  end

  config.vm.provision :ansible do |ansible|
    ansible.playbook = "tracon.yml"
    # ansible.extra_vars = {
    #   "ansible_python_interpreter" => "/usr/bin/python2.7"
    # }
    ansible.groups = {
      "kompassi-servers" => ["default"]
    }
    ansible.host_key_checking = false
  end
end
