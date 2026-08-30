FROM ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
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
    && install -d -o ubuntu -g ubuntu /opt/.venv \
    && install -d -o ubuntu -g ubuntu /opt/workspace \
    && rm -rf /var/lib/apt/lists/*

USER ubuntu
ENV HOME="/home/ubuntu" \
    LANG="C.UTF-8" \
    PATH="/opt/.venv/bin:${PATH}"
WORKDIR /home/ubuntu

# Keep Zephyr's Python commands and importable packages in one environment.
RUN python3 -m venv /opt/.venv \
    && pip install \
        cmake \
        pre-commit \
        pyelftools \
        west \
    && rm -rf /home/ubuntu/.cache

# Install the Zephyr SDK matching the Docker target architecture.
ARG ZEPHYR_SDK="zephyr-sdk-${ZEPHYR_SDK_VERSION}"
ARG ZEPHYR_SDK_INSTALL_DIR="/opt/${ZEPHYR_SDK}"
ARG ZEPHYR_SDK_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}"
USER root
WORKDIR /tmp
RUN case "${TARGETARCH}" in \
        arm64) sdk_arch="aarch64" ;; \
        amd64) sdk_arch="x86_64" ;; \
        *) echo "Unsupported Docker target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && sdk_package="${ZEPHYR_SDK}_linux-${sdk_arch}.tar.xz" \
    && wget "${ZEPHYR_SDK_URL}/${sdk_package}" \
    && wget -O - "${ZEPHYR_SDK_URL}/sha256.sum" | sha256sum --check --ignore-missing \
    && tar xf "${sdk_package}" -C /opt \
    && rm "${sdk_package}" \
    && chown -R ubuntu:ubuntu "${ZEPHYR_SDK_INSTALL_DIR}"

USER ubuntu
RUN ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -t arm-zephyr-eabi \
    && ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -c \
    && rm -rf /home/ubuntu/.cache

ENV ZEPHYR_SDK_INSTALL_DIR="${ZEPHYR_SDK_INSTALL_DIR}" \
    ZEPHYR_TOOLCHAIN_VARIANT="zephyr"

WORKDIR /opt/workspace

CMD ["bash"]
