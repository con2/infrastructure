# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "bento/ubuntu-16.04"

  config.vm.provider :virtualbox do |virtualbox|
    virtualbox.cpus = 4
    virtualbox.memory = 2048
  end


  config.vm.define "siilo" do |siilo|
    siilo.vm.network "private_network", ip: "192.168.50.4"
    siilo.vm.provision :ansible do |ansible|
      ansible.playbook = "tracon.yml"
      ansible.vault_password_file = ".vault_pass.txt"
      ansible.extra_vars = {
          "letsencrypt_enabled" => "0",
          "base_resolv_conf_enabled" => "0",
          "postgresql_barman_hostname" => "192.168.50.5",
          "postgresql_barman_ip" => "192.168.50.5",

          # FIXME nowadays a list, postgresql_access_networks. we prolly can't set complex vars herein?
          "postgresql_access_network" => "192.168.50.0/24",
          "postgresql_listen" => "192.168.50.4",
          "pgadmin4_ssl" => false,
      }
      ansible.groups = {
          "docker-servers" => ["siilo"],
          "postgresql-servers" => ["siilo"],
      }
      ansible.host_key_checking = false
    end
  end

  config.vm.define "piilo" do |piilo|
    piilo.vm.network "private_network", ip: "192.168.50.5"
    piilo.vm.provision :ansible do |ansible|
      ansible.playbook = "tracon.yml"
      ansible.vault_password_file = ".vault_pass.txt"
      ansible.extra_vars = {
          "letsencrypt_enabled" => "0",
          "base_resolv_conf_enabled" => "0",
          "postgresql_hostname" => "192.168.50.4",
      }
      ansible.groups = {
          "barman-servers" => ["piilo"]
      }
      ansible.host_key_checking = false
    end
  end


  # config.vm.define "nuoli" do |nuoli|
  #   nuoli.vm.provision :ansible do |ansible|
  #     ansible.playbook = "tracon.yml"
  #     ansible.vault_password_file = ".vault_pass.txt"
  #     ansible.extra_vars = {
  #         "slackirc_enabled" => "0",
  #         "infokala_allowed_hosts" => "infokala.tracon.fi infokala.localdomain",
  #         "infokala_email_host" => "",
  #         "letsencrypt_enabled" => "0",
  #     }
  #     ansible.groups = {
  #         "tracon-servers" => ["nuoli"]
  #     }
  #     ansible.host_key_checking = false
  #   end
  # end

  # config.vm.define "neula" do |neula|
  #   neula.vm.provision :ansible do |ansible|
  #     ansible.playbook = "tracon.yml"
  #     ansible.vault_password_file = ".vault_pass.txt"
  #     ansible.extra_vars = {
  #         "kompassi_allowed_hosts" => "kompassi.eu local.kompassi.eu",
  #         "kompassi_email_host" => "",
  #         "kompassi_crowd_application_password" => "",
  #         "kompassi_desuprofile_oauth2_client_id" => "",
  #         "letsencrypt_enabled" => "0",
  #     }
  #     ansible.groups = {
  #         "kompassi-servers" => ["neula"]
  #     }
  #     ansible.host_key_checking = false
  #   end
  # end

  # config.vm.define "monokkeli" do |monokkeli|
  #   monokkeli.vm.provision :ansible do |ansible|
  #     ansible.playbook = "tracon.yml"
  #     ansible.vault_password_file = ".vault_pass.txt"
  #     ansible.extra_vars = {
  #         "jenkins_hostname" => "jenkins.local",
  #         "jenkins_allowed_hosts" => "jenkins.local",
  #         "letsencrypt_enabled" => "0",
  #     }
  #     ansible.groups = {
  #         "management-servers" => ["monokkeli"]
  #     }
  #     ansible.host_key_checking = false
  #   end
  # end
end
