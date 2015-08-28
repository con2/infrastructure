# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  config.vm.box = "ubuntu/trusty64"

  config.vm.provider :virtualbox do |virtualbox|
    virtualbox.cpus = 4
    virtualbox.memory = 1024
  end

  config.vm.provision :ansible do |ansible|
    ansible.playbook = "tracon.yml"
    ansible.groups = {
      "logstash-centrals" => ["default"]
    }
    ansible.host_key_checking = false
  end
end
