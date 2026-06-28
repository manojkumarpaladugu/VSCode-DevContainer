FROM ubuntu:26.04

# Build time arguments
ARG DEBIAN_FRONTEND=noninteractive
ARG IMAGE_USER
ARG HOME_DIR="/home/${IMAGE_USER}"
ARG TIMEZONE
ARG WORKSPACE_DIR="/opt/workspace"
ARG GID=1000
ARG UID=1000
ARG VENV_DIR="${HOME_DIR}/.venv"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Switch to temporary directory
WORKDIR "/tmp"

# Update system and install required packages
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    sudo \
    tzdata \
    python3 \
    python3-venv \
    python3-pip \
    wget \
    vim \
    git \
    zip \
    unzip \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Set timezone
RUN if [ -n "${TIMEZONE}" ]; then \
        ln -snf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
        echo ${TIMEZONE} > /etc/timezone && \
        dpkg-reconfigure -f noninteractive tzdata; \
    fi
ENV TZ=${TIMEZONE}

# Safely remove default ubuntu user (UID 1000) if it exists, and create our dev user
RUN if id -u ubuntu &>/dev/null; then userdel -r ubuntu; fi && \
    groupadd -g ${GID} ${IMAGE_USER} && \
    useradd -m -u ${UID} -g ${GID} -d ${HOME_DIR} -s /bin/bash ${IMAGE_USER} && \
    echo "${IMAGE_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup python virtual environment and set ownership
RUN ln -s /usr/bin/python3 /usr/bin/python && \
    python -m venv ${VENV_DIR} && \
    chown -R ${IMAGE_USER}:${IMAGE_USER} ${VENV_DIR}

# Add virtual environment to PATH
ENV PATH="${VENV_DIR}/bin:$PATH"

# Switch to the non-root user for pip installation and subsequent shell usage
USER ${IMAGE_USER}
WORKDIR ${WORKSPACE_DIR}

# Install python packages inside the venv as the non-root user to preserve file ownership
RUN pip install --no-cache-dir \
    cmake \
    pre-commit

# 'bash' will drop you into a shell prompt, ready for development.
CMD ["bash"]
