FROM ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ZEPHYR_SDK_VERSION="0.17.0"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# This image intentionally relies on Ubuntu's built-in, fixed 1000:1000 account.
RUN id ubuntu >/dev/null 2>&1 \
    || { echo "The ubuntu:26.04 image does not contain the expected 'ubuntu' account." >&2; exit 1; }; \
    [ "$(id -u ubuntu)" = "1000" ] && [ "$(id -g ubuntu)" = "1000" ] \
    || { echo "The 'ubuntu' account must use UID and GID 1000." >&2; exit 1; }

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gcc-arm-none-eabi \
        git \
        gzip \
        libstdc++6 \
        ninja-build \
        openocd \
        openssh-client \
        picocom \
        pipx \
        python-is-python3 \
        python3 \
        python3-pip \
        python3-venv \
        qemu-system-arm \
        sudo \
        tar \
        tzdata \
        unzip \
        usbutils \
        vim \
        wget \
        xz-utils \
        zip \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && install -d -o ubuntu -g ubuntu /opt/workspace \
    && rm -rf /var/lib/apt/lists/*

USER ubuntu
ENV HOME="/home/ubuntu" \
    LANG="C.UTF-8" \
    PATH="/home/ubuntu/.local/bin:${PATH}"
WORKDIR /home/ubuntu

# pipx gives each command an isolated environment while exposing its executable
# through ~/.local/bin.
RUN pipx install cmake \
    && pipx install pre-commit \
    && pipx install west \
    && pipx install pyelftools \
    && rm -rf /home/ubuntu/.cache

# Install the Zephyr SDK under the user's home directory.
ARG ZEPHYR_SDK="zephyr-sdk-${ZEPHYR_SDK_VERSION}"
ARG ZEPHYR_SDK_INSTALL_DIR="/home/ubuntu/${ZEPHYR_SDK}"
ARG ZEPHYR_SDK_PACKAGE="${ZEPHYR_SDK}_linux-x86_64.tar.xz"
ARG ZEPHYR_SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}"
RUN wget "${ZEPHYR_SDK_URL}/${ZEPHYR_SDK_PACKAGE}" \
    && wget -O - "${ZEPHYR_SDK_URL}/sha256.sum" | shasum --check --ignore-missing \
    && tar xf ${ZEPHYR_SDK_PACKAGE} -C /home/ubuntu \
    && rm ${ZEPHYR_SDK_PACKAGE} \
    && ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -t arm-zephyr-eabi \
    && ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -c \
    && rm -rf /home/ubuntu/.cache

ENV ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_INSTALL_DIR}"

WORKDIR /opt/workspace

CMD ["bash"]
