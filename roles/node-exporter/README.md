# Prometheus Node Exporter

Uses [prometheus/node_exporter](https://github.com/prometheus/node_exporter) to export generic node metrics such as CPU, memory, disk space etc.

`node_exporter` prefers not being put in a container, so we do a classic Ansible deployment instead.

Systemd is used to start the service and keep it running. Legacy machines use Upstart.

See also [the prometheus role](https://github.com/tracon/ansible-tracon/tree/master/roles/prometheus).
