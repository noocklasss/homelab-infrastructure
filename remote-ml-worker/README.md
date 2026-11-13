# Remote Machine Learning Worker (Rootless `bwrap` + SSH Reverse Tunnel)

## Problem Statement

The 24/7 home server runs on legacy hardware (**Intel Core 2 Duo T6570**, **2.8 GiB RAM**), which supports up to SSE4.1 and lacks **`x86_64-v2` (SSE4.2)** instructions.

Starting with Immich `v3`, the `immich-machine-learning` container bundles **NumPy 2.x** compiled with `-march=x86-64-v2` baseline optimizations, causing the container to crash-loop on boot:

```text
RuntimeError: NumPy was built with baseline optimizations:
(X86_V2) but your machine doesn't support:
(X86_V2).
```

Additionally, running CLIP and facial recognition models inside 2.8 GiB of RAM starves PostgreSQL and the core Immich server.

## Solution Architecture

Instead of downgrading Immich or keeping an expensive desktop online 24/7:

1. **Decouple inference from storage**: Removed `immich-machine-learning` from the server's Docker Compose stack while keeping `immich_server`, `immich_postgres` (with `VectorChord`), and `immich_redis` (`Valkey 9`) running 24/7.
2. **Rootless `bubblewrap` (`bwrap`) sandbox on the workstation**: Exported the official `immich-machine-learning:v3` OCI rootfs to `~/.local/share/immich-ml/rootfs` and execute `/opt/venv/bin/python -m immich_ml` inside an unprivileged user namespace on `127.0.0.1:3003` without requiring a local Docker daemon or root privileges.
3. **Zero idle resource overhead**: Configured `MACHINE_LEARNING_MODEL_TTL=60`, so ONNX models automatically unload from workstation RAM 60 seconds after a search or upload completes.
4. **Zero-trust SSH reverse tunnel (`immich-ml-tunnel`)**:
   - The workstation initiates an outbound SSH reverse tunnel (`-R 127.0.0.1:13003:127.0.0.1:3003`) to the home server and runs a lightweight `asyncio` TCP bridge on the Docker bridge address (`172.17.0.1:3003`, set with `IMMICH_BRIDGE_ADDRESS`), reachable from containers but not from the rest of the network.
   - `immich_server` resolves `http://immich-machine-learning:3003` via Docker's `extra_hosts: ["immich-machine-learning:host-gateway"]`.
   - No inbound ports need to be opened in the workstation's `ufw` firewall, and `sshd` on the server does not require `GatewayPorts yes`.

## Deployment

1. Copy `bin/immich-ml` and `bin/immich-ml-tunnel` to `~/.local/bin/` and make them executable.
2. Export the container rootfs from the server:
   ```bash
   mkdir -p ~/.local/share/immich-ml/rootfs ~/.local/share/immich-ml/cache
   ssh homeserver "docker export immich_machine_learning" | tar -x -C ~/.local/share/immich-ml/rootfs
   ```
3. Install and start the `systemd --user` units:
   ```bash
   cp systemd/*.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now immich-ml.service immich-ml-tunnel.service
   ```
4. Verify end-to-end connectivity from inside `immich_server`:
   ```bash
   ssh homeserver "docker exec immich_server curl -fsS http://immich-machine-learning:3003/ping"
   # Expected output: pong
   ```
