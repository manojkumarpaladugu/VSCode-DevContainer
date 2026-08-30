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

## Development containers

- [Generic Ubuntu environment](generic/README.md)
- [Zephyr development environment](zephyr/README.md)

Each project README documents its Docker Compose and Dev Container workflow.
Command-line Compose operations are exposed through the cross-platform
`docker_manage.py` CLI. Python 3.9 or newer and Docker Compose v2 are required.

## Docker management CLI

`docker_manage.py` provides a small action-first interface for Compose projects:

```text
python docker_manage.py [GLOBAL_OPTIONS] [COMPOSE_OPTIONS] ACTION [ARGS...]
```

Invoke the Python script directly on Linux, macOS, or native Windows.

Run commands from a project directory so the Compose file is discovered
automatically:

```bash
cd generic
python ../docker_manage.py start
python ../docker_manage.py shell generic-ubuntu
python ../docker_manage.py status
python ../docker_manage.py remove
```

Alternatively, select a Compose file explicitly from the repository root:

```bash
python docker_manage.py -f zephyr/docker-compose.yml start
python docker_manage.py -f zephyr/docker-compose.yml shell zephyr-ubuntu
```

From native Windows PowerShell or Command Prompt, use the same Python CLI:

```powershell
cd generic
python ..\docker_manage.py start
python ..\docker_manage.py shell generic-ubuntu
python ..\docker_manage.py status
python ..\docker_manage.py remove
```

If the Windows installation provides the Python launcher instead of the
`python` command, use `py -3` in its place.

`start` creates and starts services without forcing an image build. `rebuild`
builds images and force-recreates their containers, while `run` starts a
disposable service container and removes it when the command exits. `remove`
stops containers before removing them and preserves images and volumes. Run
`python docker_manage.py --help` for the complete action list.

### SSH agent forwarding

On Linux and macOS, standalone containers started through the management CLI
automatically forward an available host SSH agent. This allows Git to
authenticate with SSH without copying or mounting private keys into the
container.

Load the required key on the host and verify that the agent can see it:

```bash
ssh-add ~/.ssh/id_ed25519
ssh-add -l
```

On Linux, the CLI mounts the Unix socket from `SSH_AUTH_SOCK`. On macOS it
uses Docker Desktop's
[`/run/host-services/ssh-auth.sock`](https://docs.docker.com/desktop/features/networking/networking-how-tos/#ssh-agent-forwarding)
bridge. For another Unix-socket layout, set an explicit source before starting
or recreating the service. The CLI derives the socket's numeric group ID
when it can inspect the source locally; provide both overrides for a socket path
that is resolved only by the Docker daemon:

```bash
DOCKER_SSH_AUTH_SOCK=/absolute/path/to/agent.sock python ../docker_manage.py start
DOCKER_SSH_AUTH_SOCK=/daemon/path/agent.sock DOCKER_SSH_AUTH_GID=1234 python ../docker_manage.py start
```

Docker does not provide a documented automatic host-agent socket bridge for
native Windows. The CLI therefore warns and continues without agent forwarding
for `start`, `rebuild`, `shell`, and `run`; all other management functionality
works normally. If a separately configured bridge exposes a socket path that is
visible to the Docker daemon, set both `DOCKER_SSH_AUTH_SOCK` and the numeric
`DOCKER_SSH_AUTH_GID` before running `python docker_manage.py`. Invalid explicit
overrides fail before Docker is contacted.

On any platform, if no usable agent is detected automatically,
container-creating actions warn and continue without forwarding. After starting
a project, verify the forwarded agent and clone from the container shell:

```bash
ssh-add -l
git clone git@github.com:OWNER/REPOSITORY.git
```

The container can ask the forwarded agent to sign authentication requests, so
forward it only into trusted images and containers. The private keys themselves
remain on the host. Editor-launched Dev Containers continue to use the editor's
own automatic agent forwarding and do not load the standalone overlay.

Removal and global cleanup require confirmation. In non-interactive
environments, place global `--force` before any Compose options and the action.
Use `--dry-run` to inspect the commands without contacting Docker.

```bash
python docker_manage.py --dry-run -f generic/docker-compose.yml rebuild generic-ubuntu
python docker_manage.py --force cleanup
```

`cleanup` permanently removes stopped containers plus every image, network,
named or anonymous volume, and build-cache entry unused by running containers.
It is the only engine-level action; all project actions use Docker Compose
internally.
