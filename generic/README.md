# Generic development workspace

Ubuntu 26.04 development environment for VS Code/Cursor Dev Containers and
Docker Compose. The host's `~/workspace` directory is mounted at
`/opt/workspace`.

## Prerequisites

Create the workspace and configure the Git identity used inside the container:

```bash
mkdir -p "${HOME}/workspace"
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
test -f "${HOME}/.gitconfig"
```

The host Git configuration is mounted read-only. Set `HOST_GIT_CONFIG` to an
alternative absolute path before creating the container when needed.

The container uses Ubuntu's existing `ubuntu` account at UID/GID `1000:1000`.
On native Linux, ensure `~/workspace` is writable by that identity. Docker
Desktop normally translates bind-mount permissions.

## Start the environment

Open this directory as a Dev Container, or run from this directory:

```bash
python ../docker_manage.py start
python ../docker_manage.py shell generic-ubuntu
python ../docker_manage.py remove
```

The same commands work in native Windows PowerShell or Command Prompt. Python
3.9 or newer is required.

Recreate the service after changing its Dockerfile, mounts, or environment:

```bash
python ../docker_manage.py rebuild generic-ubuntu
```

For a disposable shell, run `python ../docker_manage.py run generic-ubuntu bash`.
The CLI forwards an active Linux or macOS host SSH agent for standalone
sessions. Native Windows sessions continue without automatic agent forwarding.
Editor-attached sessions retain the editor's forwarding behavior, and neither
workflow mounts private keys. See the root README for setup and security details.

## Included tools

The image includes Python, pip, CMake, pre-commit, Vim, Git, SSH, curl/wget,
zip, and unzip. Python, pip, CMake, and pre-commit resolve from the shared
`/opt/.venv` environment.
