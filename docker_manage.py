#!/usr/bin/env python3
"""Manage Docker Compose projects through a small action-first interface."""

from __future__ import annotations

import os
import platform
import shlex
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import Callable, Mapping, MutableMapping, Optional, Sequence, TextIO, Union


COMPOSE_OPTIONS_WITH_VALUE = {
    "-f",
    "--file",
    "-p",
    "--project-name",
    "--profile",
    "--env-file",
    "--project-directory",
    "--ansi",
    "--parallel",
    "--progress",
}
COMPOSE_OPTIONS_WITH_EQUALS = {
    "--file",
    "--project-name",
    "--profile",
    "--env-file",
    "--project-directory",
    "--ansi",
    "--parallel",
    "--progress",
}
COMPOSE_FLAG_OPTIONS = {"--all-resources", "--compatibility"}
COMPOSE_ACTIONS = {
    "start",
    "rebuild",
    "stop",
    "restart",
    "status",
    "logs",
    "shell",
    "exec",
    "run",
    "build",
    "pull",
    "config",
    "remove",
}
CONTAINER_CREATING_ACTIONS = {"start", "rebuild", "shell", "run"}
BASE_COMPOSE_FILES = (
    "compose.yaml",
    "compose.yml",
    "docker-compose.yaml",
    "docker-compose.yml",
)
OVERRIDE_COMPOSE_FILES = (
    "compose.override.yaml",
    "compose.override.yml",
    "docker-compose.override.yaml",
    "docker-compose.override.yml",
)


class DockerManager:
    """Cross-platform implementation of the docker management CLI."""

    def __init__(
        self,
        *,
        env: Optional[Mapping[str, str]] = None,
        cwd: Optional[Union[Path, str]] = None,
        stdin: Optional[TextIO] = None,
        stdout: Optional[TextIO] = None,
        stderr: Optional[TextIO] = None,
        system: Optional[str] = None,
        executable_finder: Callable[[str], Optional[str]] = shutil.which,
        process_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
        program_name: Optional[str] = None,
    ) -> None:
        self.env: MutableMapping[str, str] = dict(os.environ if env is None else env)
        self.cwd = (Path.cwd() if cwd is None else Path(cwd)).resolve()
        self.stdin = sys.stdin if stdin is None else stdin
        self.stdout = sys.stdout if stdout is None else stdout
        self.stderr = sys.stderr if stderr is None else stderr
        self.system = platform.system() if system is None else system
        self.executable_finder = executable_finder
        self.process_runner = process_runner
        self.program_name = program_name or f"python {Path(sys.argv[0]).name}"

        self.dry_run = False
        self.verbose = False
        self.no_color = False
        self.force = False
        self.docker_ready = False
        self.compose_ready = False
        self.compose_options: list[str] = []
        self.compose_action = ""
        self.compose_args: list[str] = []

        self.ssh_agent_overlay: Optional[Path] = None
        self.ssh_agent_base_file: Optional[Path] = None
        self.ssh_agent_default_override: Optional[Path] = None
        self.ssh_agent_error = ""

        self.red = ""
        self.green = ""
        self.yellow = ""
        self.cyan = ""
        self.reset = ""

    @staticmethod
    def _isatty(stream: TextIO) -> bool:
        try:
            return stream.isatty()
        except (AttributeError, OSError):
            return False

    def init_colors(self) -> None:
        if (
            not self.no_color
            and not self.env.get("NO_COLOR")
            and self._isatty(self.stderr)
        ):
            self.red = "\033[0;31m"
            self.green = "\033[0;32m"
            self.yellow = "\033[1;33m"
            self.cyan = "\033[0;36m"
            self.reset = "\033[0m"

    def _diagnostic(self, message: str, color: str = "") -> None:
        print(f"{color}{message}{self.reset}", file=self.stderr)

    def info(self, message: str) -> None:
        self._diagnostic(message, self.green)

    def warn(self, message: str) -> None:
        self._diagnostic(message, self.yellow)

    def error(self, message: str) -> None:
        self._diagnostic(message, self.red)

    def debug(self, message: str) -> None:
        if self.verbose:
            self._diagnostic(message, self.cyan)

    def format_command(self, command: Sequence[str]) -> str:
        if self.system == "Windows":
            return subprocess.list2cmdline(list(command))
        return shlex.join(command)

    def print_command(self, command: Sequence[str]) -> None:
        self._diagnostic(f"+ {self.format_command(command)}", self.cyan)

    def _invoke(self, command: Sequence[str], *, quiet: bool = False) -> int:
        kwargs: dict[str, object] = {
            "cwd": str(self.cwd),
            "env": dict(self.env),
            "check": False,
            "text": True,
            "shell": False,
        }
        if quiet:
            kwargs["stdout"] = subprocess.DEVNULL
            kwargs["stderr"] = subprocess.DEVNULL
        try:
            result = self.process_runner(list(command), **kwargs)
        except FileNotFoundError:
            self.error(f"Executable was not found: {command[0]}")
            return 127
        except OSError as exc:
            self.error(f"Unable to execute {command[0]}: {exc}")
            return 126
        return_code = int(result.returncode)
        if -128 < return_code < 0:
            return 128 - return_code
        return return_code

    def execute_command(self, command: Sequence[str]) -> int:
        if self.dry_run:
            self.print_command(command)
            return 0
        if self.verbose:
            self.print_command(command)
        return self._invoke(command)

    def usage(self, *, stream: Optional[TextIO] = None) -> None:
        destination = self.stdout if stream is None else stream
        print(
            f"""Usage:
  {self.program_name} [GLOBAL_OPTIONS] [COMPOSE_OPTIONS] ACTION [ARGS...]

Manage the Compose project selected by the current directory or by explicit
Compose options. All project actions use Docker Compose internally.

Global options (must precede Compose options and the action):
  --dry-run       Print commands without running them
  --verbose, -v   Print commands before running them
  --no-color      Disable colored diagnostic output
  --force         Skip this script's destructive-action confirmation
  --help, -h      Show this help

Compose options (must precede the action):
  -f, --file FILE
  -p, --project-name NAME
      --profile PROFILE
      --env-file FILE
      --project-directory DIR
      --ansi MODE
      --parallel LIMIT
      --progress MODE
      --all-resources
      --compatibility

Actions:
  start [ARGS...]                 Build, create, and start services
  rebuild [ARGS...]               Rebuild and force-recreate services
  stop [ARGS...]                  Stop services without removing them
  restart [ARGS...]               Restart services
  status [ARGS...]                Show all service containers
  logs [ARGS...]                  Show service logs
  shell SERVICE [COMMAND...]      Start a service and open a shell or command
  exec [OPTIONS] SERVICE COMMAND  Run a command in a running service
  run [OPTIONS] SERVICE [COMMAND] Build and run a disposable service container
  build [ARGS...]                 Build services
  pull [ARGS...]                  Pull service images
  config [ARGS...]                Render or validate the Compose configuration
  remove [SERVICE...]             Stop and remove a project or selected services
  cleanup                         Remove all unused Docker data globally

Examples:
  {self.program_name} start
  {self.program_name} shell app
  {self.program_name} rebuild app
  {self.program_name} run app bash
  {self.program_name} -f environments/app/compose.yml status
  {self.program_name} remove
  {self.program_name} --force cleanup

'remove' preserves images and volumes. 'cleanup' permanently removes stopped
containers and all Docker data unused by running containers. It is the only
action that uses Docker-wide commands because Compose cannot prune resources
across projects. On Linux and macOS, standalone project actions forward a
detected SSH agent. Native Windows continues without automatic forwarding; set
DOCKER_SSH_AUTH_SOCK and DOCKER_SSH_AUTH_GID to use an explicit agent bridge.""",
            file=destination,
        )

    def action_usage_error(self, action: str) -> int:
        self.error(f"Missing arguments for '{action}'.")
        self.usage(stream=self.stderr)
        return 2

    def require_arg_count(self, action: str, minimum: int, args: Sequence[str]) -> int:
        if len(args) < minimum:
            return self.action_usage_error(action)
        return 0

    def ensure_docker_cli(self) -> int:
        if self.executable_finder("docker") is None:
            self.error("Docker CLI was not found in PATH. Install Docker and try again.")
            return 127
        return 0

    def ensure_docker(self) -> int:
        status = self.ensure_docker_cli()
        if status:
            return status
        if self.dry_run or self.docker_ready:
            return 0
        status = self._invoke(["docker", "info"], quiet=True)
        if status:
            self.error(
                "Cannot access the Docker daemon. Start Docker and verify your "
                "current context and permissions."
            )
            return status
        self.docker_ready = True
        return 0

    def ensure_compose(self) -> int:
        status = self.ensure_docker()
        if status:
            return status
        if self.dry_run or self.compose_ready:
            return 0
        status = self._invoke(["docker", "compose", "version"], quiet=True)
        if status:
            self.error(
                "Docker Compose v2 is unavailable. Install or enable the Docker "
                "Compose plugin."
            )
            return status
        self.compose_ready = True
        return 0

    def run_docker(self, *args: str) -> int:
        if not self.dry_run:
            status = self.ensure_docker()
            if status:
                return status
        return self.execute_command(["docker", *args])

    def run_compose(self, *args: str) -> int:
        if not self.dry_run:
            status = self.ensure_compose()
            if status:
                return status
        return self.execute_command(["docker", "compose", *self.compose_options, *args])

    def confirm_destructive(self, description: str) -> int:
        if self.dry_run:
            self.debug("Skipping confirmation because dry-run mode cannot modify Docker resources.")
            return 0
        if self.force:
            self.debug("Skipping confirmation because global --force was supplied.")
            return 0
        if not self._isatty(self.stdin):
            self.error(
                f"{description} requires confirmation. Re-run with global --force "
                "in a non-interactive session."
            )
            return 2
        print(f"{self.red}{description} [y/N]: {self.reset}", end="", file=self.stderr, flush=True)
        response = self.stdin.readline()
        if response == "":
            self.error("Unable to read confirmation.")
            return 2
        if response.rstrip("\r\n") in {"y", "Y", "yes", "YES", "Yes"}:
            return 0
        self.warn("Cancelled.")
        return 1

    def parse_compose_options(self, args: Sequence[str]) -> int:
        self.compose_options = []
        self.compose_action = ""
        self.compose_args = []
        index = 0
        while index < len(args):
            argument = args[index]
            if argument in COMPOSE_OPTIONS_WITH_VALUE:
                if index + 1 >= len(args):
                    self.error(f"Compose option '{argument}' requires a value.")
                    return 2
                self.compose_options.extend((argument, args[index + 1]))
                index += 2
                continue
            if argument.startswith("--") and "=" in argument:
                name = argument.split("=", 1)[0]
                if name in COMPOSE_OPTIONS_WITH_EQUALS:
                    self.compose_options.append(argument)
                    index += 1
                    continue
            if argument in COMPOSE_FLAG_OPTIONS:
                self.compose_options.append(argument)
                index += 1
                continue
            if argument in {"--help", "-h"}:
                self.compose_action = argument
                self.compose_args = list(args[index + 1 :])
                return 0
            if argument == "--":
                if index + 1 < len(args):
                    self.compose_action = args[index + 1]
                    self.compose_args = list(args[index + 2 :])
                return 0
            if argument.startswith("-"):
                self.error(f"Unsupported Compose option before the action: {argument}")
                self.usage(stream=self.stderr)
                return 2
            self.compose_action = argument
            self.compose_args = list(args[index + 1 :])
            return 0
        return 0

    def _compose_option_value(self, short_name: str, long_name: str) -> str:
        value = ""
        index = 0
        while index < len(self.compose_options):
            option = self.compose_options[index]
            if option in {short_name, long_name}:
                index += 1
                if index < len(self.compose_options) and not value:
                    value = self.compose_options[index]
            elif option.startswith(f"{long_name}=") and not value:
                value = option.split("=", 1)[1]
            index += 1
        return value

    def discover_ssh_agent_overlay(self) -> bool:
        compose_file = self._compose_option_value("-f", "--file")
        project_directory = self._compose_option_value("", "--project-directory")
        self.ssh_agent_base_file = None
        self.ssh_agent_default_override = None

        if compose_file:
            if compose_file == "-":
                return False
            self.ssh_agent_base_file = Path(compose_file)
        else:
            search_directory = self.cwd / (project_directory or ".")
            try:
                search_directory = search_directory.resolve(strict=True)
            except (OSError, RuntimeError):
                return False
            if not search_directory.is_dir():
                return False
            while True:
                for filename in BASE_COMPOSE_FILES:
                    candidate = search_directory / filename
                    if candidate.is_file():
                        self.ssh_agent_base_file = candidate
                        break
                if self.ssh_agent_base_file is not None:
                    break
                parent = search_directory.parent
                if parent == search_directory:
                    break
                search_directory = parent

        if self.ssh_agent_base_file is None:
            return False
        search_directory = self.ssh_agent_base_file.parent
        if not compose_file:
            for filename in OVERRIDE_COMPOSE_FILES:
                candidate = search_directory / filename
                if candidate.is_file():
                    self.ssh_agent_default_override = candidate
                    break
        self.ssh_agent_overlay = search_directory / "docker-compose.ssh-agent.yml"
        overlay_on_host = self.ssh_agent_overlay
        if not overlay_on_host.is_absolute():
            overlay_on_host = self.cwd / overlay_on_host
        return overlay_on_host.is_file()

    def compose_options_include_file(self, expected: Path) -> bool:
        expected_text = str(expected)
        index = 0
        while index < len(self.compose_options):
            option = self.compose_options[index]
            if option in {"-f", "--file"}:
                index += 1
                if (
                    index < len(self.compose_options)
                    and self.compose_options[index] == expected_text
                ):
                    return True
            elif option.startswith("--file=") and option.split("=", 1)[1] == expected_text:
                return True
            index += 1
        return False

    @staticmethod
    def _is_socket(path: str) -> bool:
        try:
            return stat.S_ISSOCK(os.stat(path).st_mode)
        except (OSError, ValueError):
            return False

    @staticmethod
    def _socket_gid(path: str) -> Optional[int]:
        try:
            gid = os.stat(path).st_gid
        except (AttributeError, OSError, ValueError):
            return None
        return int(gid) if isinstance(gid, int) and gid >= 0 else None

    def validate_ssh_agent_gid(self) -> bool:
        gid = self.env.get("DOCKER_SSH_AUTH_GID", "")
        if not gid.isascii() or not gid.isdigit():
            self.ssh_agent_error = "DOCKER_SSH_AUTH_GID must be a numeric group ID."
            return False
        return True

    def resolve_ssh_agent_socket(self) -> bool:
        self.ssh_agent_error = ""
        override = self.env.get("DOCKER_SSH_AUTH_SOCK", "")
        override_gid = self.env.get("DOCKER_SSH_AUTH_GID", "")
        if override:
            if override_gid:
                return self.validate_ssh_agent_gid()
            if self.system == "Windows":
                self.ssh_agent_error = (
                    "Native Windows requires DOCKER_SSH_AUTH_GID when "
                    "DOCKER_SSH_AUTH_SOCK is set."
                )
                return False
            if self.system == "Darwin" and override == "/run/host-services/ssh-auth.sock":
                self.env["DOCKER_SSH_AUTH_GID"] = "0"
                return True
            if self._is_socket(override):
                gid = self._socket_gid(override)
                if gid is None:
                    self.ssh_agent_error = (
                        "Unable to determine the SSH-agent socket group; set "
                        "DOCKER_SSH_AUTH_GID explicitly."
                    )
                    return False
                self.env["DOCKER_SSH_AUTH_GID"] = str(gid)
                return True
            self.ssh_agent_error = (
                "The overridden SSH-agent socket is not locally inspectable; set "
                "DOCKER_SSH_AUTH_GID explicitly."
            )
            return False

        ssh_auth_sock = self.env.get("SSH_AUTH_SOCK", "")
        if self.system == "Darwin":
            if ssh_auth_sock and self._is_socket(ssh_auth_sock):
                self.env["DOCKER_SSH_AUTH_SOCK"] = "/run/host-services/ssh-auth.sock"
                self.env["DOCKER_SSH_AUTH_GID"] = "0"
                return True
            self.ssh_agent_error = "SSH_AUTH_SOCK is not set to a usable macOS agent socket."
        elif self.system == "Linux":
            if ssh_auth_sock and self._is_socket(ssh_auth_sock):
                gid = self._socket_gid(ssh_auth_sock)
                if gid is None:
                    self.ssh_agent_error = "Unable to determine the Linux SSH-agent socket group."
                    return False
                self.env["DOCKER_SSH_AUTH_SOCK"] = ssh_auth_sock
                self.env["DOCKER_SSH_AUTH_GID"] = str(gid)
                return True
            self.ssh_agent_error = "SSH_AUTH_SOCK is not set to a usable Linux agent socket."
        elif self.system == "Windows":
            self.ssh_agent_error = (
                "Automatic SSH-agent forwarding is unavailable on native Windows."
            )
        else:
            self.ssh_agent_error = (
                f"Automatic SSH-agent forwarding is unavailable on {self.system or 'this host OS'}."
            )
        return False

    def configure_ssh_agent(self, action: str) -> int:
        explicit_socket = bool(self.env.get("DOCKER_SSH_AUTH_SOCK", ""))
        if not self.discover_ssh_agent_overlay():
            return 0
        if not self.resolve_ssh_agent_socket():
            if explicit_socket:
                self.error(self.ssh_agent_error)
                return 2
            if action in CONTAINER_CREATING_ACTIONS:
                self.warn(
                    f"{self.ssh_agent_error} Continuing without SSH-agent forwarding. "
                    "Start an agent, load a key with ssh-add, and rerun the command "
                    "for private Git access."
                )
            return 0

        assert self.ssh_agent_base_file is not None
        assert self.ssh_agent_overlay is not None
        for compose_file in (
            self.ssh_agent_base_file,
            self.ssh_agent_default_override,
            self.ssh_agent_overlay,
        ):
            if compose_file is not None and not self.compose_options_include_file(compose_file):
                self.compose_options.extend(("-f", str(compose_file)))
        self.debug(
            "Forwarding SSH agent through Compose overlay: "
            f"{self.ssh_agent_overlay} (socket group {self.env['DOCKER_SSH_AUTH_GID']})"
        )
        return 0

    def compose_shell(self, args: Sequence[str]) -> int:
        status = self.require_arg_count("shell", 1, args)
        if status:
            return status
        service, *command = args
        no_tty = [] if self._isatty(self.stdin) and self._isatty(self.stdout) else ["-T"]
        status = self.run_compose("up", "-d", "--build", service)
        if status:
            return status
        if self.dry_run:
            if command:
                return self.run_compose("exec", *no_tty, service, *command)
            self.info("Dry run: default shell resolution would try bash, then sh.")
            return self.run_compose("exec", *no_tty, service, "bash")
        if command:
            return self.run_compose("exec", *no_tty, service, *command)

        base = ["docker", "compose", *self.compose_options, "exec", "-T", service]
        bash_status = self._invoke([*base, "bash", "-c", ":"], quiet=True)
        if bash_status == 0:
            return self.run_compose("exec", *no_tty, service, "bash")
        sh_status = self._invoke([*base, "sh", "-c", ":"], quiet=True)
        if sh_status == 0:
            return self.run_compose("exec", *no_tty, service, "sh")
        self.error(
            f"Unable to resolve a shell for Compose service '{service}' "
            f"(bash probe exited {bash_status}; sh probe exited {sh_status}). "
            "Supply an executable explicitly."
        )
        return sh_status

    def handle_remove(self, args: Sequence[str]) -> int:
        for service in args:
            if service.startswith("-"):
                self.error(
                    "'remove' accepts service names only; unsupported option: "
                    f"{service}"
                )
                return 2
        if not args:
            status = self.confirm_destructive(
                "Stop and remove the selected Compose project? Images and volumes "
                "will be preserved."
            )
            if status:
                return status
            return self.run_compose("down", "--remove-orphans")
        services = ", ".join(args)
        status = self.confirm_destructive(
            f"Stop and remove Compose service(s): {services}? Images and volumes "
            "will be preserved."
        )
        if status:
            return status
        return self.run_compose("rm", "--stop", "--force", *args)

    def handle_cleanup(self, args: Sequence[str]) -> int:
        if self.compose_options:
            self.error("'cleanup' is Docker-wide and does not accept Compose options.")
            return 2
        if args:
            self.error("'cleanup' does not accept arguments.")
            return 2
        status = self.confirm_destructive(
            "Remove stopped containers and all Docker images, networks, volumes, "
            "and build cache unused by running containers?"
        )
        if status:
            return status
        status = self.run_docker("system", "prune", "--all", "--volumes", "--force")
        if status:
            return status
        return self.run_docker("volume", "prune", "--all", "--force")

    def handle_action(self, action: str, args: Sequence[str]) -> int:
        if args and args[0] in {"--help", "-h"}:
            self.usage()
            return 0
        if action in COMPOSE_ACTIONS:
            status = self.configure_ssh_agent(action)
            if status:
                return status
        if action == "start":
            return self.run_compose("up", "-d", "--build", *args)
        if action == "rebuild":
            return self.run_compose("up", "-d", "--build", "--force-recreate", *args)
        if action in {"stop", "restart", "build", "pull", "config", "logs"}:
            return self.run_compose(action, *args)
        if action == "status":
            return self.run_compose("ps", "--all", *args)
        if action == "shell":
            return self.compose_shell(args)
        if action == "exec":
            status = self.require_arg_count("exec", 2, args)
            return status or self.run_compose("exec", *args)
        if action == "run":
            status = self.require_arg_count("run", 1, args)
            return status or self.run_compose("run", "--rm", "--build", *args)
        if action == "remove":
            return self.handle_remove(args)
        if action == "cleanup":
            return self.handle_cleanup(args)
        if action in {"container", "image", "compose"}:
            self.error(
                f"The '{action}' resource group was removed. Use a top-level action; "
                f"run '{self.program_name} --help'."
            )
            return 2
        self.error(f"Unknown action: {action}")
        self.usage(stream=self.stderr)
        return 2

    def run(self, argv: Sequence[str]) -> int:
        args = list(argv)
        index = 0
        while index < len(args):
            argument = args[index]
            if argument == "--dry-run":
                self.dry_run = True
            elif argument in {"--verbose", "-v"}:
                self.verbose = True
            elif argument == "--no-color":
                self.no_color = True
            elif argument == "--force":
                self.force = True
            elif argument in {"--help", "-h"}:
                self.init_colors()
                self.usage()
                return 0
            else:
                break
            index += 1

        self.init_colors()
        status = self.parse_compose_options(args[index:])
        if status:
            return status
        if not self.compose_action:
            self.error("An action is required.")
            self.usage(stream=self.stderr)
            return 2
        if self.compose_action in {"--help", "-h", "help"}:
            self.usage()
            return 0
        self.debug(f"Action: {self.compose_action}")
        return self.handle_action(self.compose_action, self.compose_args)


def main(argv: Optional[Sequence[str]] = None) -> int:
    if sys.version_info < (3, 9):
        print("Python 3.9 or newer is required.", file=sys.stderr)
        return 2
    manager = DockerManager()
    try:
        return manager.run(sys.argv[1:] if argv is None else argv)
    except KeyboardInterrupt:
        print(file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
