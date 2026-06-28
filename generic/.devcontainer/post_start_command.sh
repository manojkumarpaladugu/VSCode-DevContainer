#!/bin/bash

# This script is executed everytime the container is started.

set -euo pipefail

# Copy host mounted SSH configuration to the container's home directory
cp -r /opt/.host/.ssh $HOME/
cp /opt/.host/.gitconfig $HOME/

exec "$@"
