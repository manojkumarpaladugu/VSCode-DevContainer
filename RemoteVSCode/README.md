# Brief
* prepare_remote_setup.py is a python tool to prepare the remote setup for passwordless authentication and for git access.
* This tool creates a SSH configuration that let's remotehost to use the SSH configuration from the localhost.
* This way the remote host can be logged in passwordless and access git too.

# Usage
`python .\prepare_remote_setup.py --git_user username --remote_user username --remote_host hostname-or-ip`