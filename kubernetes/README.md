# Installing the Qb cluster from scratch

**Qb** is the next-generation hosting platform for Tracon, Conikuvat etc. services. Technology choices include

* [K3s](https://k3s.io) as the Kubernetes distribution
* [Longhorn](https://longhorn.io/) for distributed storage
* [Minio](https://min.io/) for object storage
* [ingress-nginx](https://kubernetes.github.io/ingress-nginx/)

TODO:

* [ ] In-cluster PostgreSQL using either [CrunchyData](https://github.com/CrunchyData/postgres-operator) or [Zalando](https://github.com/zalando/postgres-operator) PostgreSQL operator
* [ ] Minio in distributed mode (requires `qb4`)

## Pre-requisites

* At least 3 VMs
  * Ubuntu 20.04
  * SSH access with sudo
* Ansible, `kubectl`, Helm installed locally
  * For Ansible, using `python3 -m venv` and `pip install ansible` is recommended. Distro package managers may give you a WW2 era version.

## SSH via bastion server

Qb servers only have HTTP/HTTPS open to the world in the network-level firewall.

Monokkeli can be used as a bastion server. `~/.ssh/config`:

    Host monokkeli
        Hostname monokkeli.tracon.fi

    Host qb1
        Hostname qb1.con2.fi
        ProxyJump monokkeli

    Host qb2
        Hostname qb2.con2.fi
        ProxyJump monokkeli

    Host qb3
        Hostname qb3.con2.fi
        ProxyJump monokkeli

## K3s cluster setup

Setup ssh keys, basic packages, partitions etc:

    ansible-playbook -u root -t k3s-base,k3s-storage qb.yml

Provision initial server (`qb1`):

    ansible-playbook -bKt k3s-initial-server -l qb1 qb.yml

SSH in, find token in `/var/lib/rancher/k3s/server/token`. `ansible-vault edit group_vars/k3s/vault`, put it in `k3s_token`.

Provision other servers:

    ansible-playbook -bKt k3s-server -l qb2,qb3 qb.yml

On each server `qb1` through `qb3` you should be able to use `kubectl` as root.

Note: The `kubectl` binary installed by K3s is hardcoded to use `/etc/rancher/k3s/k3s.yml` as kubeconfig instead of `~/.kube/config`. `KUBECONFIG` env is still respected.

## Accessing the cluster from your workstation

Copy `/etc/rancher/k3s/k3s.yml` over to your workstation. Point `KUBECONFIG` to it. Open an SSH tunnel to one of the servers:

    ssh -fNL 6443:localhost:6443 qb1

Now you should be able to `kubectl` locally for increased happiness and comfort.

## Cluster services

Install the following

* [`ingress-nginx`](https://kubernetes.github.io/ingress-nginx/deploy/#using-helm)
* [`cert-manager`](https://cert-manager.io/docs/installation/kubernetes/#installing-with-helm)
* [`longhorn`](https://longhorn.io/docs/0.8.0/install/install-with-helm/)
* [`minio`](https://github.com/minio/charts)
* [`harbor`](https://github.com/goharbor/harbor-helm)

using Helm. Links above are to Helm installation instructions of each app.

* **Values**: Use values files from this directory.
* **Release name**: The release name should be the same as the application name.
* **Namespace**: Each should go in a namespace of the same name, with the notable exception of `longhorn` that should go in `longhorn-system`.

Using Longhorn as an example:

    helm repo add longhorn https://charts.longhorn.io
    helm install -n longhorn-system -f longhorn.values.yml longhorn longhorn/longhorn

Yes, that's five `longhorn`s in the same command.

## Miscellaneous

### Longhorn ingress

Longhorn needs ingress only to expose the management UI outside the cluster.

No built-in authentication. Basic authentication in ingress required. See [documentation](https://longhorn.io/docs/0.8.1/deploy/accessing-the-ui/longhorn-ingress/).

It's a good idea to put the unhashed password in a secret, eg. `longhorn-basic-auth-unhashed`, so that your fellow admins can find it and access the UI.