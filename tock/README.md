# Tock RTOS development workspace

Ubuntu 26.04 environment for ARM and RISC-V development, following the
[Tock Linux quickstart](https://book.tockos.org/setup/quickstart-linux).
Use Docker Compose or VS Code/Cursor Dev Containers. The host's `~/workspace`
is mounted at `/opt/workspace`; source checkouts are managed manually.

## Prerequisites

Install Docker Engine and Compose v2, and Python 3.9 or newer for the management
CLI. Prepare the host workspace and Git identity:

```bash
mkdir -p "${HOME}/workspace"
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
test -f "${HOME}/.gitconfig"
```

The host Git configuration is mounted read-only. Set `HOST_GIT_CONFIG` to an
alternative absolute path if needed. The container uses `ubuntu` with fixed
UID/GID `1000:1000`; on Linux the workspace must be writable by that identity.

## Start the environment

Open this directory as a Dev Container, or run from this directory:

```bash
python ../docker_manage.py start
python ../docker_manage.py shell tock-ubuntu
```

Rebuild after changing the image or configuration:

```bash
python ../docker_manage.py rebuild tock-ubuntu
```

Use `python ../docker_manage.py run tock-ubuntu bash` for a disposable shell,
and `python ../docker_manage.py remove` to stop and remove the container.
Standalone sessions use the management CLI's SSH-agent forwarding; editor
sessions use editor-managed forwarding. See the [root README](../README.md)
for host setup and platform details.

## Tools and source setup

The image includes the Rust toolchain declared by Tock's `rust-toolchain.toml`,
ARM and RISC-V GCC cross-compilers, native build tools and Make, GDB
(`gdb-multiarch`), OpenOCD, picocom, USB utilities, Git, SSH, Python, pip, pipx,
CMake, pre-commit, Vim, and archive/download utilities.
`tockloader` is installed with pipx as `ubuntu` and is on `PATH` in both editor
and standalone sessions. General Python development uses `/opt/.venv`.

The image build downloads the toolchain manifest from Tock's `master` branch
and installs its compiler, components, and targets as `ubuntu`. Inside the
container, clone Tock and build immediately:

```bash
cd /opt/workspace
git clone https://github.com/tock/tock.git
cd tock
```

The image has no global default Rust toolchain; run Rust commands inside a Tock
checkout so rustup selects its pinned nightly. Rust installations and pipx tools
live in the container user's home, while source persists in the host workspace.
Rebuilding the image refreshes the toolchain when Tock updates its manifest.

The image keeps the manifest used during construction at
`/usr/local/share/tock-toolchain/rust-toolchain.toml` for inspection. Building
the image and installing a toolchain require network access. A checkout from a
different Tock branch or release may declare another toolchain; run
`rustup install` in that checkout when necessary.

Build an ARM kernel for the Nordic nRF52840 development kit:

```bash
make -C boards/nordic/nrf52840dk
```

Build a RISC-V kernel for HiFive1:

```bash
make -C boards/hifive1
```

These compile kernels without requiring connected hardware. Consult the
[board documentation](https://github.com/tock/tock/tree/master/boards)
for board revisions, flashing commands, and application setup.

For Rust Analyzer, open the cloned Tock directory as your editor workspace
inside the container. Its matching toolchain is already installed. The initial
`/opt/workspace` folder is a parent of the checkout and has no Rust project or
toolchain configuration of its own.

### C userspace applications

[libtock-c](https://github.com/tock/libtock-c) also needs `elf2tab` to package
applications. Install it with an explicitly selected stable Rust toolchain;
libtock-c's automatic installation otherwise fails in the fresh image, which
has no default compiler:

```bash
cd /opt/workspace
git clone https://github.com/tock/libtock-c.git
cd libtock-c
rustup toolchain install stable --profile minimal
cargo +stable install elf2tab --locked
make -C examples/blink TOCK_TARGETS=cortex-m4
```

For a HiFive1 application build:

```bash
make -C examples/blink 'TOCK_TARGETS=rv32imac|rv32imac.0x20040080.0x80002800|0x20040080|0x80002800'
```

Use the target and memory layout specified by your board's documentation.
The first build downloads libtock-c's matching C libraries, so network access
is required. The kernel checkout continues to select its own pinned nightly.
Repeat the stable toolchain and `elf2tab` installation after recreating the
container.

## Flashing and debugging

This service follows the repository's Zephyr setup: it is privileged and mounts
host `/dev` for Linux USB access. Use it with trusted code. Device permissions
still apply to the non-root `ubuntu` user.

On the Linux **host**, install the udev rule appropriate to your board. The
following examples adapt the quickstart device IDs to group-based permissions
(install only those matching your device):

```bash
# FTDI serial interface
sudo tee /etc/udev/rules.d/99-ftdi.rules <<'RULE'
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0660", GROUP="dialout"
RULE
# Arduino serial interface
sudo tee /etc/udev/rules.d/98-arduino.rules <<'RULE'
SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="005a", MODE="0660", GROUP="dialout"
RULE
sudo udevadm control --reload-rules
```

Unplug and reconnect the board. For group-based serial access, inspect the
numeric device group on the host with `stat -c '%g' /dev/ttyACM0` (substitute
your device), then add that numeric GID through a local Compose override:

```yaml
# docker-compose.override.yml, next to docker-compose.yml
services:
  tock-ubuntu:
    group_add:
      - "20" # Replace with the host device's numeric group ID.
```

Standalone Compose discovery loads this override when run from this directory.
For editor sessions, replace the `dockerComposeFile` string in
`.devcontainer/devcontainer.json` with this array:

```json
"dockerComposeFile": ["../docker-compose.yml", "../docker-compose.override.yml"]
```

Recreate the container after changing groups. USB debug probes may require additional
vendor-provided host udev rules; serial rules alone do not cover every probe.

OpenOCD and `gdb-multiarch` are included, and Cortex-Debug is configured to use
`/usr/bin/gdb-multiarch`. Supply a board-specific debug launch configuration
with the kernel ELF and probe settings. When the board requires `JLinkExe`, download the Linux
package matching the container architecture from
[SEGGER J-Link Software and Documentation Pack](https://www.segger.com/downloads/jlink/),
accept its terms, and install it inside the container, for example with
`sudo apt install /opt/workspace/JLink_Linux_<version>_<architecture>.deb`.
Install the vendor's USB permission rules on the host as appropriate. Manual
J-Link installations must be repeated after container recreation.

Docker Desktop runs containers in a VM; mounting `/dev` does not automatically
expose the physical host's USB devices. Use separately configured USB forwarding
or flash on the host. Physical flashing requires validation with your actual
board and probe.
