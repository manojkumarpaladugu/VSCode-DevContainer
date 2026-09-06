FROM ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# This image intentionally relies on Ubuntu's built-in, fixed 1000:1000 account.
RUN id ubuntu >/dev/null 2>&1 \
    || { echo "The ubuntu:26.04 image does not contain the expected 'ubuntu' account." >&2; exit 1; }; \
    [ "$(id -u ubuntu)" = "1000" ] && [ "$(id -g ubuntu)" = "1000" ] \
    || { echo "The 'ubuntu' account must use UID and GID 1000." >&2; exit 1; }

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        gcc-arm-none-eabi \
        gcc-riscv64-unknown-elf \
        gdb-multiarch \
        git \
        gzip \
        libstdc++6 \
        openocd \
        openssh-client \
        picocom \
        pipx \
        python-is-python3 \
        python3 \
        python3-pip \
        python3-venv \
        sudo \
        tar \
        tzdata \
        unzip \
        usbutils \
        vim \
        wget \
        zip \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && install -d -o ubuntu -g ubuntu /opt/.venv \
    && install -d -o ubuntu -g ubuntu /opt/workspace \
    && rm -rf /var/lib/apt/lists/*

USER ubuntu
ENV HOME="/home/ubuntu" \
    LANG="C.UTF-8" \
    PATH="/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/opt/.venv/bin:${PATH}"
WORKDIR /home/ubuntu

# Keep the Python interpreter, pip, and development commands in one environment.
RUN python3 -m venv /opt/.venv \
    && pip install \
        cmake \
        pre-commit \
    && rm -rf /home/ubuntu/.cache

# Install rustup without choosing a global default toolchain.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y --no-modify-path --default-toolchain none \
    && rm /tmp/rustup-init.sh \
    && pipx install tockloader \
    && rm -rf /home/ubuntu/.cache

# Install the complete toolchain declared by the selected Tock source ref. Keep
# the manifest in the image so the installed version and components are visible.
ADD --chown=ubuntu:ubuntu \
    https://raw.githubusercontent.com/tock/tock/master/rust-toolchain.toml \
    /usr/local/share/tock-toolchain/rust-toolchain.toml
WORKDIR /usr/local/share/tock-toolchain
RUN rustup install \
    && rm -rf /home/ubuntu/.cache

WORKDIR /opt/workspace

CMD ["bash"]
