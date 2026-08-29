# Dev Containers Setup

This repository contains scripts to easily connect to local and remote development containers using VS Code or Cursor.

## Prepare Host Machine

### Setup Docker Engine

1. [Install Docker Engine](https://docs.docker.com/engine/install/)
2. [Linux Post-install](https://docs.docker.com/engine/install/linux-postinstall/)
3. [Install Remote Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

### Generate SSH key and add it to the GitHub account

1. [Generate SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)
2. [Add to GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)
3. [Test connection](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection)

### Remote Setup

Use the `RemoteVSCode/prepare_remote_setup.py` script to set up passwordless SSH and git access on remote hosts.

```bash
python RemoteVSCode/prepare_remote_setup.py --git_user username --remote_user username --remote_host hostname-or-ip
```

## Docker management CLI

`docker_manage.sh` is a generic wrapper for common container, image, and
Docker Compose workflows. It does not contain project-specific image names,
ports, mounts, environment variables, or build arguments.

```text
./docker_manage.sh [GLOBAL_OPTIONS] container ACTION [ARGS...]
./docker_manage.sh [GLOBAL_OPTIONS] image ACTION [ARGS...]
./docker_manage.sh [GLOBAL_OPTIONS] compose [COMPOSE_OPTIONS] ACTION [ARGS...]
```

Run `./docker_manage.sh --help` or the help for an individual resource, such
as `./docker_manage.sh container --help`, for the complete action list.

### Containers

Docker arguments are forwarded unchanged, so normal Docker flags can be used:

```bash
# List all containers and start two existing containers.
./docker_manage.sh container list --all
./docker_manage.sh container start api worker

# Create a container from any image and follow its logs.
./docker_manage.sh container run --name web -d -p 8080:80 nginx:alpine
./docker_manage.sh container logs --follow --tail 100 web

# Open bash when available, otherwise fall back to sh.
./docker_manage.sh container shell web

# Run a specific interactive command instead of resolving a shell.
./docker_manage.sh container shell web python3
```

`container shell` requires the container to already be running. It never
starts a stopped container implicitly.

### Images

```bash
./docker_manage.sh image build -t my-app:dev -f Dockerfile .
./docker_manage.sh image pull alpine:latest
./docker_manage.sh image tag my-app:dev registry.example.com/my-app:dev
./docker_manage.sh image inspect my-app:dev
```

No UID/GID build arguments or other build settings are injected. Supply every
project-specific option explicitly as a normal Docker argument.

### Docker Compose

Compose mode is always explicit. Compose options that select files, profiles,
or project identity belong between `compose` and the action:

```bash
./docker_manage.sh compose -f generic/docker-compose.yml -p generic-dev up -d
./docker_manage.sh compose -f generic/docker-compose.yml -p generic-dev ps
./docker_manage.sh compose -f generic/docker-compose.yml -p generic-dev shell generic-ubuntu
./docker_manage.sh compose -f generic/docker-compose.yml -p generic-dev down
```

When `--file` is omitted, Docker Compose performs its normal file discovery.
`compose down` preserves volumes and images unless Docker's `--volumes` or
`--rmi` option is explicitly supplied.

### Safety and automation

Container/image removal and pruning require one confirmation. In scripts, CI,
or other non-interactive sessions, place the global `--force` option before the
resource to skip that confirmation:

```bash
./docker_manage.sh --force container remove old-api old-worker
./docker_manage.sh --force image prune --all
```

The global flag only skips this wrapper's prompt; it does not add Docker's
force-removal flag to `container remove` or `image remove`. Put a native Docker
flag after the action when its behavior is intended.

Use `--dry-run` to inspect the exact command without contacting the Docker
daemon. Diagnostic output goes to stderr, leaving Docker output pipe-friendly.
Colors are disabled automatically when stderr is not a terminal and can also
be disabled with `--no-color` or the `NO_COLOR` environment variable.

```bash
./docker_manage.sh --dry-run container run --name test alpine:latest echo hello
./docker_manage.sh --verbose image list --format '{{.Repository}}:{{.Tag}}'
```
