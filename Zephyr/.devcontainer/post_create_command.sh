#!/bin/bash

# This script is executed after the container is created for the first time.

set -euo pipefail

# Setup Git
export GIT_USERNAME_FULL="Manoj Kumar Paladugu"
export GIT_USERNAME_SHORT="manojkumarpaladugu"
export GIT_EMAIL="paladugumanojkumar@gmail.com"

git config --global user.name "${GIT_USERNAME_FULL}"
git config --global user.email "${GIT_EMAIL}"
git config --global core.editor "code --wait"

mkdir -p ~/.ssh
cat <<EOT >> ~/.ssh/config
Host github.com
  User ${GIT_USERNAME_SHORT}
EOT