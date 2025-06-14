FROM ubuntu:24.04

# Build time arguments
ARG DEBIAN_FRONTEND=noninteractive
ARG IMAGE_USER="dev"
ARG ZEPHYR_SDK_VERSION="0.17.0"
ARG USER_INSTALL_DIR="/opt"
ARG GID=1000
ARG UID=1000

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# Install system dependencies
# -----------------------------------------------------------------------------
# Update the system
RUN apt-get update     && \
    apt-get upgrade -y

# This RUN command installs all required packages for Zephyr development.
RUN apt-get install -y \
    sudo               \
    vim                \
    git                \
    wget               \
    python3            \
    python3-venv       \
    python3-pip        \
    ninja-build        \
    qemu-system-arm && \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Create user and group
# -----------------------------------------------------------------------------
# Delete default username (ubuntu) with UID 1000 and create new user
RUN userdel -r ubuntu                                                                  && \
    # Create new user with UID and GID that matches to the real host (1000:1000)
    # This avoids permission issues when mounting the workspaces directory
    groupadd -g ${GID} ${IMAGE_USER}                                                   && \
    useradd -m -u ${UID} -g ${GID} -d "/home/${IMAGE_USER}" -s /bin/bash ${IMAGE_USER} && \
    echo "${IMAGE_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN ln -s /usr/bin/python3 /usr/bin/python                                  && \
    # Ensure user install directory is writable by the non-root user
    mkdir -p ${USER_INSTALL_DIR} && chown ${UID}:${GID} ${USER_INSTALL_DIR}

# Set the default user
USER ${IMAGE_USER}

# -----------------------------------------------------------------------------
# Setup python environment
# -----------------------------------------------------------------------------
# Install python virtual environment
ARG VENV_DIR="${USER_INSTALL_DIR}/venv"
RUN python -m venv ${VENV_DIR}
ENV PATH="${VENV_DIR}/bin:$PATH"

# Install python packages
RUN pip install \
    cmake       \
    west        \
    pre-commit  \
    pyelftools

# -----------------------------------------------------------------------------
# Download and install the Zephyr SDK
# -----------------------------------------------------------------------------
WORKDIR ${USER_INSTALL_DIR}
ARG ZEPHYR_SDK="zephyr-sdk-${ZEPHYR_SDK_VERSION}"
ARG ZEPHYR_SDK_INSTALL_DIR="${USER_INSTALL_DIR}/${ZEPHYR_SDK}"
ARG ZEPHYR_SDK_PACKAGE="${ZEPHYR_SDK}_linux-x86_64.tar.xz"
RUN wget "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/${ZEPHYR_SDK_PACKAGE}"                             && \
    wget -O - "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_SDK_VERSION}/sha256.sum" | shasum --check --ignore-missing && \
    tar xvf ${ZEPHYR_SDK_PACKAGE}                                                                                                                  && \
    rm ${ZEPHYR_SDK_PACKAGE}                                                                                                                       && \
    ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -t arm-zephyr-eabi                                                                                          && \
    ${ZEPHYR_SDK_INSTALL_DIR}/setup.sh -c

# -----------------------------------------------------------------------------
# Set up working directory and default command
# -----------------------------------------------------------------------------
# WORKDIR: Sets the default working directory for subsequent instructions and when the container starts.
WORKDIR /workspaces

# CMD: Specifies the default command to execute when the container starts.
#      'bash' will drop you into a shell prompt, ready for development.
CMD ["bash"]    
