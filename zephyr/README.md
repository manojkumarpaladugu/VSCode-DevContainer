# Zephyr development workspace

This image builds from Canonical's official Ubuntu 26.04 image and provides a
persistent Zephyr RTOS development environment for both VS Code/Cursor Dev
Containers and command-line Docker Compose workflows. The host's `~/workspace`
directory is available at `/opt/workspace` in the container.

The runtime includes the Zephyr SDK 0.17.0 (ARM toolchain), west, CMake,
Ninja, QEMU (ARM), OpenOCD, picocom, gcc-arm-none-eabi, pre-commit, Python,
pip, pipx, Vim, Git, SSH, curl/wget, zip, and unzip. CMake, west, pre-commit,
and pyelftools are installed in separate pipx environments.

The container runs in privileged mode with the host's `/dev` mounted to allow
direct access to USB devices for flashing hardware targets.

## Prepare the host Git identity

The container reads the host's global Git configuration so commits use the
same author identity as the host. Configure both required values before
starting the service:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
test -f "${HOME}/.gitconfig"
```

By default, `${HOME}/.gitconfig` is mounted read-only at
`/home/ubuntu/.gitconfig-host` and exposed to Git as system-level
configuration. Container-global and repository-local settings remain writable
and take precedence over these host defaults. The separate mount path avoids
conflicting with an editor that also copies configuration to
`/home/ubuntu/.gitconfig`.

For a host config stored elsewhere, set an absolute source path before creating
the container:

```bash
export HOST_GIT_CONFIG=/absolute/path/to/gitconfig
```

The source file must exist. Compose will fail instead of silently creating a
directory when the path is missing.

## Use with VS Code or Cursor

Open the `zephyr` directory as a Dev Container. The editor builds and attaches
to the `zephyr-ubuntu` Compose service as Ubuntu's existing non-root `ubuntu`
user. Its identity remains fixed at UID/GID `1000:1000`.

Closing the editor does not stop the service. This is intentional: the same
container can remain available for terminal sessions. Stop it explicitly with
the `docker compose down` command below when it is no longer needed.

Dev Containers may also copy the editor's Git configuration. The read-only
Compose mount provides the author identity even when that editor integration is
unavailable. When an SSH agent is running on the host, the editor forwards it
into attached editor sessions. Private keys are never mounted into the
container.

After adding or changing the Git-config mount, run **Dev Containers: Rebuild
Container** from the editor command palette. Restarting the existing container
is insufficient because Docker applies mounts when the container is created.

## Use without an editor

Make sure the host workspace exists, then run these commands from this directory:

```bash
mkdir -p "${HOME}/workspace"
docker compose up -d --build
docker compose exec zephyr-ubuntu bash
docker compose down
```

To apply mount or environment changes to an existing service without relying
on Compose's change detection, recreate it explicitly:

```bash
docker compose up -d --build --force-recreate zephyr-ubuntu
```

The Compose service is persistent and restarts unless explicitly stopped. Its
generated container name is scoped to the Compose project rather than being a
global fixed name.

Compose derives its default project name from this directory, so two copies of
this `zephyr` directory would otherwise both use the project name `zephyr`.
Give each concurrently running copy a stable, unique project name:

```bash
export COMPOSE_PROJECT_NAME=zephyr-my-project
docker compose up -d --build
docker compose exec zephyr-ubuntu bash
docker compose down
```

The explicitly named `zephyr-ubuntu` image remains shared. Use `--build` after
switching between copies that contain different Dockerfiles.

For a disposable shell instead of the persistent service:

```bash
docker compose run --rm zephyr-ubuntu bash
```

Standalone Compose sessions receive the host Git configuration through the
read-only mount, but they do not receive the host SSH agent or private keys.
Authentication and commit identity are separate: use an editor-attached session
for automatic SSH-agent forwarding, or configure standalone authentication
explicitly when it is needed.

## Host file ownership on Linux

The Dockerfile does not create or modify the development account and always
uses Ubuntu's existing `ubuntu` user at UID/GID `1000:1000`. On native Linux,
`${HOME}/workspace` must therefore be writable by that identity. When the host
account uses different IDs, manage the directory ownership or ACLs on the host
before starting the service. Docker Desktop platforms normally translate
bind-mount permissions.
