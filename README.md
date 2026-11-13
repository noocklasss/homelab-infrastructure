# Homelab Infrastructure (IaC & Hybrid Distributed ML)

[![Infrastructure CI](https://github.com/noocklasss/homelab-infrastructure/actions/workflows/ci.yml/badge.svg)](https://github.com/noocklasss/homelab-infrastructure/actions/workflows/ci.yml)

Production-oriented Infrastructure as Code (IaC), reverse proxy configurations, `systemd` service definitions, and operational automation for a hybrid two-node self-hosted homelab.

---

## Overview & Motivation

This repository manages a self-hosted Linux environment designed to maximize reliability and hardware reuse across two distinct nodes:

- **Storage & Always-On Node (`oikoserver`)**: An older low-power Ubuntu server (**Intel Core 2 Duo T6570**, **2.8 GiB RAM**) running 24/7 for photo management (**Immich**), **PostgreSQL + VectorChord**, **Valkey**, **Nginx TLS 1.3** reverse proxying, **Samba** file sharing, and local microservices.
- **On-Demand AI Inference Node (`noock`)**: A modern workstation (**12th Gen Intel i5-12400**, **RTX 2060**) running a rootless, sandboxed **Immich Machine Learning** worker over an encrypted **SSH reverse tunnel** so heavy neural network inference never impacts the 24/7 node.

---

## System Architecture

```mermaid
flowchart LR
    Client["LAN / HTTPS Clients"] --> Nginx["Nginx Reverse Proxy<br>(TLS 1.3 + HTTP/2)"]

    subgraph Server["24/7 Storage & App Node (Ubuntu)"]
        Nginx -->|"127.0.0.1:2283"| ImmichWeb
        Nginx -->|"Port 5000 / 5173 / 6969"| SystemdApps["Host systemd Services<br>(FastAPI, FFmpeg UI, Static Docs)"]
        ImmichWeb["immich_server (:2283)"] --> Valkey["immich_redis (Valkey 9)"]
        ImmichWeb --> Postgres["immich_postgres<br>(PostgreSQL 14 + VectorChord)"]
        Watchtower["watchtower<br>(opt-in label updates)"]
        Bridge["SSH Reverse Tunnel Bridge<br>(172.17.0.1:3003 -> 127.0.0.1:13003)"]
        ImmichWeb -->|"extra_hosts: host-gateway:3003"| Bridge
    end

    subgraph Workstation["On-Demand Inference Node"]
        MLWorker["Rootless bwrap Sandbox<br>(immich_ml :3003, TTL=60s)"]
    end

    MLWorker <-->|"Encrypted SSH Reverse Tunnel<br>(No inbound firewall ports)"| Bridge
```

---

## Engineering Case Study: Overcoming Legacy CPU ISA Limits (`x86_64-v2`)

### The Problem
The 24/7 storage server runs on a 2009 **Intel Core 2 Duo T6570** (up to SSE4.1) with **2.8 GiB RAM**. Starting with Immich `v3`, the official `immich-machine-learning` container ships **NumPy 2.x** compiled with `-march=x86-64-v2` (SSE4.2) baseline optimizations, causing an immediate crash loop on startup:

```text
RuntimeError: NumPy was built with baseline optimizations:
(X86_V2) but your machine doesn't support:
(X86_V2).
```

### The Solution
Rather than pinning legacy software or leaving a desktop running 24/7:
1. **Decoupled Stateful & Stateless Services**: Removed `immich-machine-learning` from the server's Docker Compose stack while keeping `immich_server`, `immich_postgres` (VectorChord), and `immich_redis` (Valkey 9) online 24/7.
2. **Rootless Sandboxed Worker (`bubblewrap`)**: Exported the official `v3.4.1` OCI container rootfs to the workstation and executed `/opt/venv/bin/python -m immich_ml` inside an unprivileged `bwrap` namespace (`remote-ml-worker/bin/immich-ml`) managed by `systemd --user`.
3. **Zero Idle Footprint**: Configured `MACHINE_LEARNING_MODEL_TTL=60` so CLIP and facial recognition models unload completely from RAM 60 seconds after a search or photo upload finishes.
4. **Firewall-Friendly SSH Reverse Tunnel**: `remote-ml-worker/bin/immich-ml-tunnel` maintains an auto-reconnecting outbound SSH tunnel to the server (`ServerAliveInterval=15`), bridging it to `immich_server` via Docker's `extra_hosts` (`host-gateway`). The bridge listens only on the Docker bridge address (`172.17.0.1`), so containers can reach the worker but the rest of the network cannot, and no inbound port is opened on the workstation's `ufw` firewall nor `GatewayPorts` enabled in `sshd`.

See [remote-ml-worker/README.md](remote-ml-worker/README.md) for full setup details.

---

## Repository Structure

```text
.
├── .github/workflows/
│   └── ci.yml                       # ShellCheck, Compose + systemd checks, Gitleaks history scan (SHA-pinned actions)
├── remote-ml-worker/
│   ├── bin/
│   │   ├── immich-ml                # Rootless bubblewrap launcher for Immich ML v3
│   │   └── immich-ml-tunnel         # Persistent SSH reverse tunnel + asyncio port bridge
│   ├── systemd/
│   │   ├── immich-ml.service        # systemd --user unit for the ML sandbox
│   │   └── immich-ml-tunnel.service # systemd --user unit for the SSH tunnel
│   └── README.md                    # Technical deep-dive on CPU ISA & ML offloading
├── reverse-proxy/nginx/
│   ├── conf.d/websocket-upgrade.conf # Shared WebSocket upgrade map (defined once per nginx)
│   ├── immich.conf                  # TLS 1.3 front for Immich (localhost-only :2283), 50 GB uploads
│   ├── media-api.conf               # TLS 1.3 + HTTP/2 reverse proxy for FastAPI service
│   ├── media-transcoder.conf        # TLS 1.3 + WebSocket upgrade proxy (1G upload limit)
│   └── static-docs.conf             # LAN-only HTTP proxy for local documentation mirror
├── scripts/
│   ├── backup-postgres.sh           # Verified, compressed pg_dumpall backup with 7-day retention
│   ├── duckdns-update.sh            # Environment-driven dynamic DNS updater
│   └── healthcheck.sh               # End-to-end verification of Immich API & ML tunnel
├── stacks/
│   ├── immich/
│   │   ├── .env.example             # Sanitized environment variable template
│   │   └── docker-compose.yml       # Immich v3 server, VectorChord PostgreSQL, & Valkey 9
│   └── maintenance/
│       └── docker-compose.yml       # Watchtower (digest-pinned), updates only opted-in containers
├── systemd/
│   ├── ffmpeg-ui.service            # FFmpeg Web UI host service
│   ├── media-api.service            # Uvicorn FastAPI media service
│   └── static-docs.service          # Node.js static documentation service
├── .gitignore
└── LICENSE
```

---

## Security & Secret Management

- **No committed credentials**: real `.env` files, TLS certificates (`*.pem`, `*.key`, `*.crt`), database dumps and runtime volumes are excluded via `.gitignore`. CI fails on any tracked env/key/certificate file and runs Gitleaks over the full history.
- **TLS 1.3 only, HTTPS only**: public virtual hosts serve `TLSv1.3` with HTTP/2 and HSTS; port 80 only redirects to HTTPS. The documentation mirror is plain HTTP and refuses anything outside private address ranges.
- **Nothing listens wider than it must**: Immich is published on `127.0.0.1:2283` behind Nginx (`IMMICH_BIND_ADDRESS`), and the ML tunnel bridge listens on the Docker bridge address only.
- **Least privilege**:
  - Host `systemd` services run as a dedicated non-root user with `NoNewPrivileges`, `ProtectSystem=full`, `PrivateTmp` and kernel / cgroup protection.
  - The remote ML worker executes inside an unprivileged `bwrap` filesystem sandbox.
  - Inter-node ML traffic travels inside an authenticated Ed25519 SSH tunnel.
- **Supply chain**: Postgres, Valkey and Watchtower images are pinned by digest, Immich to a release, CI actions to commit SHAs. Watchtower only updates containers that opt in by label; Immich upgrades are deliberate.

---

## Operations, Backups & Verification

### 1. Deploy the Immich Stack (Server)
```bash
cd stacks/immich
cp .env.example .env
# Edit .env with strong database credentials and host paths
docker compose up -d
sudo cp ../../reverse-proxy/nginx/conf.d/websocket-upgrade.conf /etc/nginx/conf.d/
sudo cp ../../reverse-proxy/nginx/immich.conf /etc/nginx/sites-available/ && sudo ln -s ../sites-available/immich.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```
Point the Immich mobile app at `https://<your photos host>` instead of `http://<server>:2283`; with the default
`IMMICH_BIND_ADDRESS=127.0.0.1` the direct port is no longer reachable from the network.

### 2. Automated PostgreSQL Backups
`scripts/backup-postgres.sh` writes a compressed logical dump (`pg_dumpall | gzip -9`), checks that the archive is readable and really is a cluster dump before keeping it, and prunes archives older than `RETENTION_DAYS` (default: `7`):
```bash
./scripts/backup-postgres.sh
```

### Restoring a backup
A backup only counts once it has been restored. To restore into the running stack (this replaces the current database):
```bash
cd stacks/immich
docker compose stop immich-server                       # nothing writes while we restore
gunzip -c ~/backups/immich-db/immich_pgdump_YYYYMMDD_HHMMSS.sql.gz \
  | docker exec -i immich_postgres psql --username=postgres --dbname=postgres
docker compose start immich-server
```
Then run `scripts/healthcheck.sh` from the workstation.
The dump is made with `--clean --if-exists`, so it drops and recreates each database itself. Backups live on the server's
own disk; copy them off the machine as well (for example with `rsync` to the workstation), or a disk failure takes both.

### 3. End-to-End Health Check
Verify the local `bwrap` worker, SSH reverse tunnel, Immich server API version, and container-to-worker routing in one command:
```bash
./scripts/healthcheck.sh
```
