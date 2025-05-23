import os
import subprocess
import shutil
import logging
import platform

def get_ssh_directory():
    """
    Get the SSH directory path for the current user.

    :return: Path to the SSH directory.
    """
    ssh_dir = os.path.expanduser("~/.ssh")
    return ssh_dir

def generate_ssh_key_pair(key_type, key_path, comment):
    """
    Generate an SSH key pair.

    :param key_type: The type of SSH key to generate (e.g., 'rsa', 'ed25519').
    :param key_path: The path of the key file to generate.
    :param comment: A comment to include in the key.
    """
    # Validate key type
    supported_key_types = ['rsa', 'ed25519']
    if key_type not in supported_key_types:
        raise Exception(f"Unsupported key type '{key_type}'. Supported types are: {supported_key_types}")

    # Check if ssh-keygen is available
    if not shutil.which("ssh-keygen"):
        raise Exception("ssh-keygen command not found. Please ensure OpenSSH is installed and in your PATH.")

    # Generate the SSH key pair
    try:
        subprocess.run(
            ["ssh-keygen", "-o", "-a", "100", "-t", key_type, "-f", key_path, "-C", comment, "-q", "-N", ""],
            check=True
        )
        logging.info(f"SSH key pair generated successfully: {key_path}")
    except subprocess.CalledProcessError as e:
        raise Exception(f"Error generating SSH key pair: {e}")

def add_public_key_to_remote(pubkey_path, remote_user, remote_host):
    """
    Add a public key to the remote host's authorized_keys file.

    :param pubkey_path: Path to the public key file.
    :param remote_user: Username for the remote host.
    :param remote_host: IP address or hostname of the remote host.
    """
    # Validate the public key file
    if not os.path.exists(pubkey_path):
        raise Exception(f"Public key file not found: {pubkey_path}")

    # Read the public key content
    try:
        with open(pubkey_path, 'r') as file:
            pubkey = file.read().strip()
    except Exception as e:
        raise Exception(f"Failed to read public key file: {e}")

    # Construct the SSH command
    ssh_command = [
        "ssh", f"{remote_user}@{remote_host}",
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
        f"echo '{pubkey}' >> ~/.ssh/authorized_keys && "
        "chmod 600 ~/.ssh/authorized_keys"
    ]

    # Execute the command
    try:
        subprocess.run(ssh_command, check=True, text=True)
        logging.info(f"Public key added to the remote authorized_keys successfully for {remote_user}@{remote_host}")
    except subprocess.CalledProcessError as e:
        raise Exception(f"Failed to add public key to the remote host: {e}")

def create_ssh_configuration_on_localhost(key_path, git_user, remote_host, user_config_path):
    """
    Create user specific SSH configuration in local host.

    :param key_path: Path to the private key file.
    :param git_user: Git username.
    :param remote_host: IP address or hostname of the remote host.
    :param user_config_path: Path to the SSH configuration file.
    """

    # Validate the private key file
    if not os.path.exists(key_path):
        raise Exception(f"Private key file not found: {key_path}")

    # Read the template file
    try:
        with open("ssh_config.local", "r") as template_file:
            config_template = template_file.read()
    except Exception as e:
        raise Exception(f"Failed to read ssh_config.local file: {e}")

    # Replace placeholders in the template
    config_content = config_template.format(
        git_user=git_user,
        remote_host=remote_host,
        key_path=key_path
    )

    try:
        # Ensure the directory exists
        os.makedirs(os.path.dirname(user_config_path), exist_ok=True)

        # Write the configuration to the file
        with open(user_config_path, 'w') as file:
            file.write(config_content)
        logging.info(f"Local SSH configuration is written successfully to {user_config_path}")

        # Add the user_config_path to ~/.ssh/config using the Include directive
        global_config_path = os.path.join(get_ssh_directory(), "config")
        include_directive = f"# AUTOGENERATED BY USER\nInclude {user_config_path}\n# AUTOGENERATED BY USER\n"

        # Check if the Include directive is already present
        if os.path.exists(global_config_path):
            with open(global_config_path, 'r') as global_config_file:
                if include_directive.strip() in global_config_file.read():
                    logging.info(f"Local SSH configuration {user_config_path} already included in global {global_config_path}")
                    return

        # Prepend the Include directive to ~/.ssh/config
        if os.path.exists(global_config_path):
            with open(global_config_path, 'r') as global_config_file:
                existing_content = global_config_file.read()
            with open(global_config_path, 'w') as global_config_file:
                global_config_file.write(f"{include_directive}\n{existing_content}")
        else:
            with open(global_config_path, 'w') as global_config_file:
                global_config_file.write(include_directive)

        logging.info(f"Included local SSH configuration in global SSH configuration file")

    except Exception as e:
        raise Exception(f"Failed to write SSH configuration: {e}")

def create_ssh_configuration_on_remotehost(git_user, remote_user, remote_host):
    """
    Update the remote host's ~/.ssh/config file with specific configuration.

    :param git_user: Git username.
    :param remote_user: Username for the remote host.
    :param remote_host: IP address or hostname of the remote host.
    """
    # Read the template file
    try:
        with open("ssh_config.remote", "r") as template_file:
            config_template = template_file.read()
    except Exception as e:
        raise Exception(f"Failed to read ssh_config.local file: {e}")

    # Replace placeholders in the template
    config_content = config_template.format(
        git_user=git_user
    )

    # Construct the SSH command to check if the configuration already exists
    check_command = [
        "ssh", f"{remote_user}@{remote_host}",
        f"grep -qxF '{config_content}' ~/.ssh/config || echo 'NOT_FOUND'"
    ]

    try:
        # Check if the configuration is already present
        result = subprocess.run(check_command, capture_output=True, text=True, check=True)
        if "NOT_FOUND" not in result.stdout:
            logging.info(f"Remote SSH configuration already exists for {remote_user}@{remote_host}")
            return

        # Construct the SSH command to update the remote ~/.ssh/config
        update_command = [
            "ssh", f"{remote_user}@{remote_host}",
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
            f"echo '{config_content}' >> ~/.ssh/config && "
            "chmod 600 ~/.ssh/config"
        ]

        # Execute the command to update the configuration
        subprocess.run(update_command, check=True, text=True)
        logging.info(f"Remote SSH configuration updated successfully for {remote_user}@{remote_host}")

    except subprocess.CalledProcessError as e:
        raise Exception(f"Failed to update remote SSH configuration: {e}")

def authorize_localhost_to_access_remotehost(key_type, git_user, remote_user, remote_host):
    """
    Generate public/private key pair
    Copy public key to the remote host's authorized_keys file.
    Create SSH configuration for local and remote

    :param key_type: The type of SSH key to generate (e.g., 'rsa', 'ed25519').
    :param git_user: Git username.
    :param remote_user: Username for the remote host.
    :param remote_host: IP address or hostname of the remote host.
    """
    local_host_name = platform.node()
    ssh_path = get_ssh_directory()
    key_dir = os.path.join(ssh_path, remote_host)
    key_path = os.path.join(key_dir, f"id_{key_type}")
    comment = f"{remote_host}@{local_host_name}"
    ssh_config_path = os.path.join(key_dir, "config")

    # Ensure the key directory exists
    os.makedirs(key_dir, exist_ok=True)

    # Check if the key already exists
    if not os.path.exists(key_path):
        generate_ssh_key_pair(key_type=key_type, key_path=key_path, comment=comment)
        pub_key_path = f"{key_path}.pub"
        add_public_key_to_remote(pub_key_path, remote_user, remote_host)
        create_ssh_configuration_on_localhost(key_path, git_user, remote_host, ssh_config_path)
        create_ssh_configuration_on_remotehost(git_user, remote_user, remote_host)
    else:
        logging.info(f"SSH key already exists at {key_path}")
    return key_path
