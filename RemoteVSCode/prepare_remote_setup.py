import argparse
import logging

from ssh_setup import *

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format='%(levelname)s - %(message)s')

    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Remote Setup for VS Code")
    parser.add_argument("--git_user", required=True, help="Specify the git user name")
    parser.add_argument("--remote_user", required=True, help="Specify the remote host user name")
    parser.add_argument("--remote_host", required=True, help="Specify the remote host name or IP")
    args = parser.parse_args()
    remote_user = args.remote_user
    remote_host = args.remote_host

    key_path = authorize_localhost_to_access_remotehost("ed25519", args.git_user, args.remote_user, args.remote_host)
