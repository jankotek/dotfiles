# jan-pod-setup

Create a maximally restricted user and rootless podman pod as a systemd user service.

Tested on Ubuntu 24.04 (podman 4.9, AppArmor) and openSUSE Tumbleweed (podman 5.8, SELinux).

## Usage

```bash
sudo jan-pod-setup <name>
```

The `<name>` becomes the username, home directory name, pod name, and service name.

## What it creates

```
/var/pod/<name>/
├── app.container       -> Quadlet container definition
├── pod.conf            -> Quadlet pod definition (podman 5.x only)
├── containers.conf     -> Podman engine defaults
├── storage.conf        -> Storage driver config
├── registries.conf     -> Image registry config
├── environment.conf    -> Env vars for user systemd session
├── data/               -> Persistent data volume
├── bin/
│   ├── upgrade         -> Pull images + restart
│   ├── recreate        -> Reload Quadlet + restart
│   └── status          -> Show status
├── apparmor.conf       -> /etc/apparmor.d/podman-<name>  (Ubuntu only)
├── sysctl.conf         -> /etc/sysctl.d/90-podman-<name>.conf
└── tmpfiles.conf       -> /etc/tmpfiles.d/podman-<name>.conf

jan-pod-manage          # Admin wrapper (shared by all pods)
```

## Admin commands

```bash
jan-pod-manage <name> shell       # bash shell as the pod user
jan-pod-manage <name> status      # pod + container + service status
jan-pod-manage <name> upgrade     # pull latest images + restart
jan-pod-manage <name> recreate    # reload Quadlet files + restart
jan-pod-manage <name> logs        # follow container + service logs (journald)
jan-pod-manage <name> exec <ctr> sh  # exec into a running container
jan-pod-manage <name> prune       # stop, remove containers/images, free disk (keeps data/)
jan-pod-manage                    # list all pods
```

## Logging

Container stdout/stderr is sent to journald via `LogDriver=journald`. Logs are tagged with the systemd service unit, so they appear alongside service lifecycle events (start/stop/restart) in one timeline.

View logs:
```bash
jan-pod-manage <name> logs                          # follow logs (as root)
journalctl _SYSTEMD_USER_UNIT=<name>-app.service     # filter by service
```

## Security hardening

| Layer | What |
|---|---|
| User | nologin shell, locked password, no user group (nogroup) |
| Sudo | `/etc/sudoers.d/deny-<name>` blocks all sudo |
| Cron/at | Added to `/etc/cron.deny` and `/etc/at.deny` |
| Filesystem ACLs | Deny access to /home, /root, /tmp, /var/tmp, /var/log, /var/spool, /var/mail, /etc/ssh |
| Home directory | 0700, parent /var/pod is 0711 (traverse only, no listing) |
| /proc | `hidepid=2` — users can only see their own processes |
| Ports | `net.ipv4.ip_unprivileged_port_start=1024` — no low port binding |
| dmesg | `kernel.dmesg_restrict=1` — kernel log restricted to root |
| Containers | `DropCapability=ALL` by default, `NoNewPrivileges=true`, private namespaces |
| /home inside container | Masked with empty read-only mount |
| AppArmor (Ubuntu) | Profile with deny rules for privilege escalation tools, sensitive paths |
| SELinux (Tumbleweed) | Container paths labeled `container_var_lib_t` / `container_file_t` |
| Cgroup delegation | Enabled for rootless podman on cgroup v2 |
| Private TMPDIR | `~/.tmp/` — no access to system /tmp or /var/tmp |
| Subuid/subgid | Auto-allocated non-overlapping ranges |

## Port binding

Containers cannot bind to ports below 1024 on the host (enforced by sysctl). Use port remapping to expose services on standard ports:

**Podman 5.x** — port mapping goes in `pod.conf` under `[Pod]`:
```ini
[Pod]
PublishPort=8080:2080
```

**Podman 4.x** — port mapping goes in `app.container` under `[Container]`:
```ini
[Container]
PublishPort=8080:2080
```

To avoid needing `NET_BIND_SERVICE` inside the container, configure the app to listen on a high port (e.g. `LISTEN=2080`) and remap in `PublishPort`.

If you must listen on port 80 inside the container (e.g. Apache default), add `AddCapability=NET_BIND_SERVICE` to the container. This only affects the container's internal namespace — the host sysctl still blocks the pod user from binding low ports directly.

## Example: FreshRSS

After running the setup script:

```bash
sudo ./setup-pod-service.sh freshrss
```

Edit `/var/pod/freshrss/app.container`:

```ini
[Unit]
Description=FreshRSS feed reader

[Container]
Image=docker.io/freshrss/freshrss:latest
ContainerName=freshrss-app
Pod=freshrss.pod

DropCapability=ALL
AddCapability=CHOWN DAC_OVERRIDE SETGID SETUID
ReadOnly=false
SecurityLabelDisable=true
LogDriver=journald

Environment=LISTEN=2080
Environment=TZ=UTC
Environment=CRON_MIN=2,32

Volume=/var/pod/freshrss/data:/var/www/FreshRSS/data:Z
Volume=/var/pod/freshrss/.empty:/home:ro
Volume=/var/pod/freshrss/.empty:/root:ro
Tmpfs=/tmp:rw,noexec,nosuid,size=64m

[Service]
MemoryMax=512M

[Install]
WantedBy=default.target
```

Edit `/var/pod/freshrss/pod.conf` (podman 5.x) to add port mapping:

```ini
[Pod]
PodName=freshrss
PublishPort=8080:2080
```

On podman 4.x, add `PublishPort=8080:80` and `AddCapability=NET_BIND_SERVICE` directly in `app.container` instead (no `Pod=` line, no `LISTEN` env var needed since port 80 is mapped directly).

Pull image and start:

```bash
jan-pod-manage freshrss recreate
```

Create admin user:

```bash
jan-pod-manage freshrss exec freshrss-app ./cli/create-user.php \
  --user admin --password <pass> --language en
```

### FreshRSS notes

| Setting | Why |
|---|---|
| `ReadOnly=false` | Apache modifies /etc/timezone, /etc/php at startup |
| `AddCapability=CHOWN DAC_OVERRIDE SETGID SETUID` | Apache needs to chown files and switch to www-data |
| `SecurityLabelDisable=true` | Required on Tumbleweed — Apache can't write to /dev/stderr without it |
| `LogDriver=journald` | Container stdout/stderr goes to journald, viewable via `manage logs` |
| `LISTEN=2080` | Makes Apache listen on a high port, avoiding NET_BIND_SERVICE |
| `PublishPort=8080:2080` | Maps host port 8080 to container port 2080 |
| Remove `Exec=` line | Use the image's own entrypoint |

## Quadlet reference

### Container directives (`app.container`)

```ini
[Container]
Image=docker.io/org/image:tag
Exec=command args
ContainerName=name
Pod=name.pod                           # podman 5.x only

DropCapability=ALL
AddCapability=CHOWN DAC_OVERRIDE
NoNewPrivileges=true
ReadOnly=true
SecurityLabelDisable=true
LogDriver=journald

Environment=KEY=value
EnvironmentFile=/var/pod/<name>/data/env

Volume=/host/path:/container/path:Z
Tmpfs=/tmp:rw,noexec,nosuid,size=64m

PublishPort=8080:8080                  # or in .pod file on 5.x

HealthCmd=curl -f http://localhost:8080/health || exit 1
HealthInterval=30s
HealthTimeout=5s
HealthRetries=3

AutoUpdate=registry
Memory=512M

# PodmanArgs=--pids-limit=128
# PodmanArgs=--cpus=0.5

[Service]
CPUQuota=100%                          # 100% = 1 core
MemoryMax=512M
TasksMax=64
```

### Pod directives (`pod.conf`, podman 5.x only)

```ini
[Pod]
PodName=name
PublishPort=8080:8080
DNS=1.1.1.1
AddHost=dbhost:10.0.0.5
```

## Distro-specific notes

### Ubuntu 24.04

- Podman 4.9 — no `.pod` file support, uses `.container` only
- `PublishPort=` goes in `[Container]` section directly
- AppArmor enabled — script installs a per-user profile
- `NET_BIND_SERVICE` needed if container listens on port < 1024 inside container

### openSUSE Tumbleweed

- Podman 5.8 — full `.pod` file support, `PublishPort=` goes in `[Pod]` section
- `crun` must be installed (`zypper install crun`) — `runc` fails with cgroup v2
- `SecurityLabelDisable=true` needed for images that write to /dev/stderr
- Cgroup delegation required (script adds `user@UID.service.d/delegate.conf`)

## Adding a second container to the pod

Create a new file at the real path:

```bash
vi /var/pod/<name>/.config/containers/systemd/<name>-db.container
```

```ini
[Unit]
Description=database

[Container]
Image=docker.io/library/postgres:16-alpine
Pod=<name>.pod
ContainerName=<name>-db

DropCapability=ALL
AddCapability=CHOWN DAC_OVERRIDE SETGID SETUID
LogDriver=journald

Environment=POSTGRES_USER=app
EnvironmentFile=/var/pod/<name>/data/db-env
Volume=/var/pod/<name>/data/pgdata:/var/lib/postgresql/data:Z

[Install]
WantedBy=default.target
```

Then reload:

```bash
jan-pod-manage <name> recreate
```

Containers in the same pod share `localhost` — the app connects to `localhost:5432`.

## Prune (free disk space)

```bash
jan-pod-manage <name> prune
```

Stops services, removes all containers/pods/images for this user. The `data/` directory is not touched. To restart after prune:

```bash
jan-pod-manage <name> recreate
```
