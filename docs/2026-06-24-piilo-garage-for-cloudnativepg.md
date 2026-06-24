# Self-Hosted S3 Outside Kubernetes
**CloudNativePG · Barman Cloud · Backup Storage**

NOTE: This is the original Claude-written document for evaluating Garage and SeaweedFS for a single-node S3-compatible backup target, retained for historical purposes. For an up-to-date admin documentation for our Garage setup, see [Con2 Outline](https://outline.con2.fi/doc/object-storage-garage-fubuhlj2S1).

---

## Recommendation: Garage

One binary. One systemd unit. Native S3 API — no filer, no gateway, no extra processes to supervise.

---

## At a glance

| Attribute | Garage | SeaweedFS |
|---|---|---|
| Processes (single-node S3) | **1 binary** | 3 minimum — master, volume, filer |
| S3 API | **Native, built-in** | Via filer component |
| Single-node | **First-class use case** | Supported; designed for distributed |
| Memory at idle | **~50 MB** | Higher — multiplied by process count |
| Language | Rust | Go |
| Barman Cloud compatible | Yes | Yes |

---

## Why SeaweedFS doesn't fit

SeaweedFS is capable software, built for multi-node distributed deployments where fine-grained volume management matters. To expose an S3 API on a single node you need at least three processes running concurrently: a master server, a volume server, and a filer server. That is three things to supervise, three logs to monitor, and three independent failure modes on a machine whose only job is holding database backups.

A backup target that fails at 3am during a restore matters more than one that fails during a routine write. Fewer moving parts is a legitimate requirement, not laziness.

---

## Connectivity: TLS via nginx reverse proxy

The simplest path for cluster-to-backup-server connectivity over the public internet is TLS termination at nginx, using your existing acme_tiny.py/cron certificate setup. Garage speaks plain HTTP internally; nginx handles TLS and forwards traffic to it on localhost.

**Garage config change**: bind the S3 API to localhost only so it is not exposed directly:

```toml
[s3_api]
api_bind_addr = "127.0.0.1:3900"   # was 0.0.0.0 — localhost only behind nginx
```

**nginx config** (`/etc/nginx/sites-available/garage`):

```nginx
server {
    listen 80;
    server_name backup.example.com;

    # ACME HTTP-01 challenge for certificate renewal
    location /.well-known/acme-challenge/ {
        root /var/www/acme;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name backup.example.com;

    ssl_certificate     /etc/ssl/garage/fullchain.pem;
    ssl_certificate_key /etc/ssl/garage/privkey.pem;

    # Base backups can be many gigabytes — remove the body size cap
    client_max_body_size 0;

    # Long transfers need long timeouts; default 60s will cut off large restores
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;

    # Stream uploads directly to Garage — do not buffer in nginx first.
    # Without this, nginx spools the entire upload body to disk before
    # forwarding, which stalls multi-GB base backups and can exhaust disk.
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:3900;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

The ACME challenge block integrates with the existing acme_tiny.py setup without changes — certificate renewal continues to work as before, and nginx reloads pick up new certificates automatically if you have that in the cron job already.

---

## Setting up Garage

A minimal `/etc/garage/garage.toml` for single-node use:

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir     = "/var/lib/garage/data"

replication_factor = 1   # single node

rpc_bind_addr   = "127.0.0.1:3901"
rpc_public_addr = "127.0.0.1:3901"

[s3_api]
s3_region     = "garage"
api_bind_addr = "127.0.0.1:3900"   # localhost only — nginx proxies from 443

[admin]
api_bind_addr = "127.0.0.1:3903"
```

Initialize, assign the layout, and create the backup bucket:

```sh
# Enable and start
systemctl enable --now garage

# Retrieve the local node ID, then assign a zone and capacity weight
NODE=$(garage node id -q | cut -d@ -f1)
garage layout assign -z dc1 -c 1G "$NODE"
garage layout apply

# Bucket and access key
garage bucket create cnpg-backups
garage key create barman-cloud-key
garage bucket allow cnpg-backups \
  --read --write --owner \
  --key barman-cloud-key
```

---

## Barman Cloud compatibility

Garage covers every S3 operation Barman Cloud uses — PutObject, GetObject, ListObjectsV2, DeleteObject, and multipart upload. Set `s3PathStyle: true` (or equivalent) in the CloudNativePG object store Secret. Some S3 clients default to virtual-hosted-style URLs (`bucket.host/key`) rather than path-style (`host/bucket/key`); Garage expects path-style without extra DNS configuration.

---

## When to revisit this

SeaweedFS becomes the right choice if storage later needs to span multiple nodes, requires volume tiering, or must replicate across machines. For a single-node backup target holding PostgreSQL WAL and base backups, Garage is the right amount of software — no more.
