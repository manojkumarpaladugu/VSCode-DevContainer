#!/bin/bash

# This script is executed after the container is created for the first time.

set -euo pipefail

export GIT_USERNAME="Manoj Kumar Paladugu"
export GIT_USERNAME_SHORT="manojkumarpaladugu"
export GIT_EMAIL="paladugumanojkumar@gmail.com"

# Configure SSH
cat <<EOT >> ~/.ssh/config
Host github.com
    CheckHostIP no
    HostKeyAlgorithms +ssh-rsa
    User ${GIT_USERNAME_SHORT}
EOT

# Setup Git
git config --global user.name "${GIT_USERNAME}"
git config --global user.email "${GIT_EMAIL}"
git config --global core.editor "code --wait"
