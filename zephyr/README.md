# Zephyr development workspace

Ubuntu 26.04 environment for Zephyr RTOS development with VS Code/Cursor Dev
Containers and Docker Compose. The host's `~/workspace` directory is mounted
at `/opt/workspace`.

The service is privileged and mounts the host's `/dev` so flashing tools can
access USB devices.

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
python ../docker_manage.py shell zephyr-ubuntu
python ../docker_manage.py remove
```

The same commands work in native Windows PowerShell or Command Prompt. Python
3.9 or newer is required.

Recreate the service after changing its Dockerfile, mounts, or environment:

```bash
python ../docker_manage.py rebuild zephyr-ubuntu
```

After rebuilding the image, regenerate existing Zephyr build directories with
`west build -p always` to discard cached Python, CMake, or SDK paths.

For a disposable shell, run `python ../docker_manage.py run zephyr-ubuntu bash`.
The CLI forwards an active Linux or macOS host SSH agent for standalone
sessions. Native Windows sessions continue without automatic agent forwarding.
Editor-attached sessions retain the editor's forwarding behavior, and neither
workflow mounts private keys. See the root README for setup and security details.

## Included tools

The image includes Zephyr SDK 0.17.0, west, CMake, Ninja, QEMU for ARM,
OpenOCD, picocom, gcc-arm-none-eabi, pre-commit, Python, pip, Vim, Git, SSH,
curl/wget, zip, and unzip. CMake, west, pre-commit, and pyelftools share the
`/opt/.venv` environment.

Docker `arm64` targets use the AArch64 SDK bundle and `amd64` targets use the
x86-64 bundle. `ZEPHYR_SDK_INSTALL_DIR` points to
`/opt/zephyr-sdk-0.17.0`, and the Zephyr SDK toolchain is selected explicitly.
