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
        ca-certificates \
        curl \
        git \
        gzip \
        libstdc++6 \
        openssh-client \
        pipx \
        python-is-python3 \
        python3 \
        python3-pip \
        python3-venv \
        sudo \
        tar \
        tzdata \
        unzip \
        vim \
        wget \
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
    && rm -rf /home/ubuntu/.cache

WORKDIR /opt/workspace

CMD ["bash"]
