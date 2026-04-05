# labctl Command Reference

`labctl` is a thin dispatcher.  Each subcommand maps to a function or a
script under `scripts/`.  It owns compose-file stacking, environment wiring,
and flag parsing — business logic lives in the scripts.

## Lifecycle

| Command | Description |
| --------- | ------------- |
| `labctl up [--gpu] [--hostnet] [--builder]` | Start containers.  Flags stack compose overlays and profiles. |
| `labctl down` | Stop and remove containers. |
| `labctl build [--no-cache]` | Build images from Dockerfiles. |
| `labctl rebuild` | Build images without cache. |
| `labctl clean` | Interactive: remove containers, volumes, prune dangling images.  `/opt/lab` is never touched. |

## Interaction

| Command | Description |
| --------- | ------------- |
| `labctl shell [container]` | Exec bash into a container (default: `kali-main`). |
| `labctl logs [container]` | Follow container logs. |

## Tooling

| Command | Description |
| --------- | ------------- |
| `labctl sync [-n NAME] [--dry-run]` | Sync pinned external binaries from `manifests/binaries.tsv`. |
| `labctl tmux <profile>` | Launch a named tmux session.  Profiles: `default`, `htb`, `build`, `research`. |

## Workflow

| Command | Description |
| --------- | ------------- |
| `labctl launch <profile> [target]` | Full launch: workspace creation (Empusa or fallback) → compose up → kali-main tmux session.  Profiles: `default`, `htb`, `build`, `research`.  The `build` profile also starts the builder sidecar. |
| `labctl workspace <name> [--profile P]` | Create workspace via Empusa (profiles: `htb`, `build`, `research`, `internal`).  Falls back to minimal scaffold (`notes/`, `scans/`, `loot/`, `logs/`) without Empusa. |

## Ops

| Command | Description |
| --------- | ------------- |
| `labctl status` | Lab health: containers, VPN, GPU, disk usage, workspace count. |
| `labctl verify` | Read-only pre-flight host checks.  Returns non-zero on critical failures. |
| `labctl update [flags]` | Safe platform update.  See flags below. |
| `labctl bootstrap` | One-time host provisioning (requires `sudo`). |

### `labctl update` flags

| Flag | Effect |
| ------ | -------- |
| `--pull` | `git pull --ff-only` the hecate-bootstrap repo before rebuild. |
| `--empusa` | Update Empusa via `install-empusa.sh update`. |
| `--binaries` | Refresh external binaries via `sync-binaries.sh`. |
| `--no-build` | Skip image rebuild. |
| `--no-restart` | Skip compose restart after rebuild. |
| `--builder` | Include builder profile in restart. |
| `--gpu` | Set `LAB_GPU=1` for compose operations. |
| `--hostnet` | Set `LAB_HOSTNET=1` for compose operations. |
| `--force` | Bypass confirmation prompts. |

The update script always runs `verify-host.sh` first and aborts on failure.
On build failure, running containers are left intact.  `/opt/lab` is never modified.

## Environment

| Variable | Type | Default | Used by | Effect |
| --- | --- | --- | --- | --- |
| `LAB_ROOT` | path | `/opt/lab` | all scripts | Persistent data root |
| `LAB_GPU` | `0\|1` | `0` | `labctl`, `launch-lab.sh`, `update-lab.sh` | Stack GPU compose overlay |
| `LAB_HOSTNET` | `0\|1` | `0` | `labctl`, `launch-lab.sh`, `update-lab.sh` | Stack host-network compose overlay |
| `COMPOSE_PROJECT_NAME` | string | `lab` | `labctl`, `launch-lab.sh`, `update-lab.sh` | Docker Compose project name |
| `GITHUB_TOKEN` | string | *(unset)* | `sync-binaries.sh` | GitHub PAT — raises API rate limit from 60 → 5,000 req/hr |
| `EMPUSA_REPO` | URL | *(see default)* | `install-empusa.sh` | Empusa clone URL (default: `https://github.com/Icarus4122/empusa.git`) |

## Compose Stacking

```bash
labctl up --gpu --hostnet --builder
  →  docker compose \
       -f compose/docker-compose.yml \
       -f compose/docker-compose.gpu.yml \
       -f compose/docker-compose.hostnet.yml \
       --profile build \
       up -d
```

All three scripts (`labctl`, `launch-lab.sh`, `update-lab.sh`) source
the shared helper `scripts/lib/compose.sh` for compose-file stacking.
