from __future__ import annotations

import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Optional, Sequence
from unittest import mock


REPO_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_DIR))

from docker_manage import DockerManager, main  # noqa: E402


class TTYStringIO(io.StringIO):
    def isatty(self) -> bool:
        return True


class FakeRunner:
    def __init__(self) -> None:
        self.calls: List[List[str]] = []
        self.environments: List[Dict[str, str]] = []
        self.info_status = 0
        self.compose_status = 0
        self.bash_status = 0
        self.sh_status = 0
        self.fail_match: Optional[Sequence[str]] = None
        self.fail_status = 1

    def __call__(self, command: Sequence[str], **kwargs: object) -> subprocess.CompletedProcess:
        call = list(command)
        self.calls.append(call)
        self.environments.append(dict(kwargs.get("env", {})))
        status = 0
        if call == ["docker", "info"]:
            status = self.info_status
        elif call == ["docker", "compose", "version"]:
            status = self.compose_status
        elif len(call) >= 3 and call[-3:] == ["bash", "-c", ":"]:
            status = self.bash_status
        elif len(call) >= 3 and call[-3:] == ["sh", "-c", ":"]:
            status = self.sh_status
        elif self.fail_match and all(part in call for part in self.fail_match):
            status = self.fail_status
        return subprocess.CompletedProcess(call, status)


class DockerManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name).resolve()
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        self.runner = FakeRunner()
        self.env: Dict[str, str] = {}

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def manager(
        self,
        *,
        system: str = "Linux",
        cwd: Optional[Path] = None,
        stdin: Optional[io.StringIO] = None,
        stdout: Optional[io.StringIO] = None,
        stderr: Optional[io.StringIO] = None,
    ) -> DockerManager:
        return DockerManager(
            env=self.env,
            cwd=cwd or self.root,
            stdin=stdin or io.StringIO(),
            stdout=stdout or self.stdout,
            stderr=stderr or self.stderr,
            system=system,
            executable_finder=lambda name: f"/mock/{name}",
            process_runner=self.runner,
            program_name="python docker_manage.py",
        )

    def run_cli(self, *args: str, **kwargs: object) -> int:
        return self.manager(**kwargs).run(args)

    def action_calls(self) -> List[List[str]]:
        return [
            call
            for call in self.runner.calls
            if call not in (["docker", "info"], ["docker", "compose", "version"])
        ]

    def make_compose_project(self, directory: Optional[Path] = None) -> Path:
        project = directory or self.root
        project.mkdir(parents=True, exist_ok=True)
        (project / "compose.yaml").touch()
        (project / "docker-compose.ssh-agent.yml").touch()
        return project

    def test_help_and_usage_errors_do_not_contact_docker(self) -> None:
        self.assertEqual(self.run_cli("--help"), 0)
        help_text = self.stdout.getvalue()
        self.assertIn("[COMPOSE_OPTIONS] ACTION", help_text)
        self.assertIn("cleanup", help_text)
        actions_text = help_text.split("Actions:\n", 1)[1].split("\n\nExamples:", 1)[0]
        self.assertEqual(
            [line.strip().split()[0] for line in actions_text.splitlines()],
            [
                "start",
                "status",
                "logs",
                "shell",
                "exec",
                "restart",
                "stop",
                "rebuild",
                "build",
                "run",
                "pull",
                "config",
                "remove",
                "cleanup",
            ],
        )
        examples_text = help_text.split("Examples:\n", 1)[1]
        example_lines = []
        for line in examples_text.splitlines():
            if not line.strip():
                break
            example_lines.append(line.strip())
        self.assertEqual(
            example_lines,
            [
                "python docker_manage.py start",
                "python docker_manage.py -f environments/app/compose.yml status",
                "python docker_manage.py shell app",
                "python docker_manage.py rebuild app",
                "python docker_manage.py run app bash",
                "python docker_manage.py remove",
                "python docker_manage.py --force cleanup",
            ],
        )
        self.assertEqual(self.runner.calls, [])

        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli(), 2)
        self.assertIn("An action is required", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

    def test_start_and_rebuild_construct_compose_commands(self) -> None:
        status = self.run_cli(
            "-f", "first.yml", "--file", "second.yml", "--profile", "dev",
            "-p", "demo", "start", "api", "worker",
        )
        self.assertEqual(status, 0)
        self.assertEqual(
            self.action_calls(),
            [[
                "docker", "compose", "-f", "first.yml", "--file", "second.yml",
                "--profile", "dev", "-p", "demo", "up", "-d", "api", "worker",
            ]],
        )

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("rebuild", "api"), 0)
        self.assertEqual(
            self.action_calls(),
            [["docker", "compose", "up", "-d", "--build", "--force-recreate", "api"]],
        )

    def test_non_build_actions_do_not_inject_image_builds(self) -> None:
        for args in (("start", "api"), ("run", "api", "true"), ("shell", "api", "true")):
            with self.subTest(action=args[0]):
                self.runner.calls.clear()
                self.assertEqual(self.run_cli(*args), 0)
                self.assertNotIn(
                    "--build",
                    [part for call in self.action_calls() for part in call],
                )

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("rebuild", "api"), 0)
        self.assertIn("--build", self.action_calls()[0])

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("build", "api"), 0)
        self.assertEqual(
            self.action_calls(),
            [["docker", "compose", "build", "api"]],
        )

    def test_callers_can_explicitly_request_builds(self) -> None:
        expectations = {
            ("start", "--build", "api"): ["up", "-d", "--build", "api"],
            ("run", "--build", "api"): ["run", "--rm", "--build", "api"],
        }
        for args, expected in expectations.items():
            with self.subTest(action=args[0]):
                self.runner.calls.clear()
                self.assertEqual(self.run_cli(*args), 0)
                self.assertEqual(
                    self.action_calls(),
                    [["docker", "compose", *expected]],
                )

    def test_compose_option_forms_and_action_delimiter_are_preserved(self) -> None:
        self.assertEqual(
            self.run_cli(
                "--file=stack.yml",
                "--project-name=demo",
                "--profile=tools",
                "--all-resources",
                "--compatibility",
                "--",
                "status",
                "api",
            ),
            0,
        )
        self.assertEqual(
            self.action_calls(),
            [[
                "docker",
                "compose",
                "--file=stack.yml",
                "--project-name=demo",
                "--profile=tools",
                "--all-resources",
                "--compatibility",
                "ps",
                "--all",
                "api",
            ]],
        )

    def test_direct_actions_forward_arguments(self) -> None:
        expectations = {
            "stop": ["stop", "--timeout", "15", "api"],
            "restart": ["restart", "api"],
            "build": ["build", "api"],
            "pull": ["pull", "api"],
            "config": ["config", "api"],
            "logs": ["logs", "api"],
            "status": ["ps", "--all", "api"],
        }
        for action, expected in expectations.items():
            with self.subTest(action=action):
                self.runner.calls.clear()
                args = (action, "--timeout", "15", "api") if action == "stop" else (action, "api")
                self.assertEqual(self.run_cli(*args), 0)
                self.assertEqual(self.action_calls(), [["docker", "compose", *expected]])

    def test_exec_and_run_validate_then_forward(self) -> None:
        self.assertEqual(self.run_cli("exec", "api"), 2)
        self.assertIn("Missing arguments for 'exec'", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("exec", "-T", "api", "env", "FOO=bar"), 0)
        self.assertEqual(
            self.action_calls(),
            [["docker", "compose", "exec", "-T", "api", "env", "FOO=bar"]],
        )

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("run"), 2)
        self.assertEqual(self.runner.calls, [])

        self.runner.calls.clear()
        self.assertEqual(
            self.run_cli("--env-file", "dev.env", "run", "-e", "MODE=test", "api", "bash"),
            0,
        )
        self.assertEqual(
            self.action_calls(),
            [[
                "docker", "compose", "--env-file", "dev.env", "run", "--rm",
                "-e", "MODE=test", "api", "bash",
            ]],
        )

    def test_shell_prefers_bash_and_falls_back_to_sh(self) -> None:
        self.assertEqual(self.run_cli("-f", "stack.yml", "shell", "api"), 0)
        calls = self.action_calls()
        self.assertIn(["docker", "compose", "-f", "stack.yml", "up", "-d", "api"], calls)
        self.assertIn(["docker", "compose", "-f", "stack.yml", "exec", "-T", "api", "bash"], calls)

        self.runner.calls.clear()
        self.runner.bash_status = 1
        self.assertEqual(self.run_cli("shell", "api"), 0)
        self.assertIn(["docker", "compose", "exec", "-T", "api", "sh"], self.action_calls())

        self.runner = FakeRunner()
        tty_input = TTYStringIO()
        tty_output = TTYStringIO()
        self.assertEqual(
            self.run_cli("shell", "api", stdin=tty_input, stdout=tty_output),
            0,
        )
        self.assertIn(["docker", "compose", "exec", "api", "bash"], self.action_calls())

    def test_shell_failure_explicit_command_and_dry_run(self) -> None:
        self.runner.bash_status = 44
        self.runner.sh_status = 45
        self.assertEqual(self.run_cli("shell", "api"), 45)
        self.assertIn("bash probe exited 44; sh probe exited 45", self.stderr.getvalue())

        self.runner = FakeRunner()
        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("shell", "api", "python3", "-V"), 0)
        self.assertNotIn(["bash", "-c", ":"], [call[-3:] for call in self.runner.calls])
        self.assertIn(
            ["docker", "compose", "exec", "-T", "api", "python3", "-V"],
            self.action_calls(),
        )

        self.runner.calls.clear()
        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("--dry-run", "shell", "api"), 0)
        output = self.stderr.getvalue()
        self.assertIn("+ docker compose up -d api", output)
        self.assertIn("+ docker compose exec -T api bash", output)
        self.assertEqual(self.runner.calls, [])

    def test_dry_run_skips_docker_preflight(self) -> None:
        self.assertEqual(self.run_cli("--dry-run", "-f", "stack.yml", "start", "api"), 0)
        self.assertIn("+ docker compose -f stack.yml up -d api", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

    def test_linux_agent_forwarding_and_overlay(self) -> None:
        project = self.make_compose_project()
        self.env["SSH_AUTH_SOCK"] = "/tmp/agent.sock"
        with mock.patch.object(DockerManager, "_is_socket", return_value=True), mock.patch.object(
            DockerManager, "_socket_gid", return_value=1234
        ):
            self.assertEqual(self.run_cli("-f", str(project / "compose.yaml"), "start", "api"), 0)
        action = self.action_calls()[0]
        self.assertEqual(
            action,
            [
                "docker", "compose", "-f", str(project / "compose.yaml"), "-f",
                str(project / "docker-compose.ssh-agent.yml"), "up", "-d", "api",
            ],
        )
        environment = self.runner.environments[-1]
        self.assertEqual(environment["DOCKER_SSH_AUTH_SOCK"], "/tmp/agent.sock")
        self.assertEqual(environment["DOCKER_SSH_AUTH_GID"], "1234")

    def test_macos_agent_uses_docker_desktop_bridge(self) -> None:
        project = self.make_compose_project()
        self.env["SSH_AUTH_SOCK"] = "/private/tmp/agent.sock"
        with mock.patch.object(DockerManager, "_is_socket", return_value=True):
            self.assertEqual(
                self.run_cli("-f", str(project / "compose.yaml"), "status", system="Darwin"),
                0,
            )
        environment = self.runner.environments[-1]
        self.assertEqual(environment["DOCKER_SSH_AUTH_SOCK"], "/run/host-services/ssh-auth.sock")
        self.assertEqual(environment["DOCKER_SSH_AUTH_GID"], "0")

    def test_parent_discovery_preserves_default_override_order(self) -> None:
        project = self.make_compose_project(self.root / "project with spaces")
        nested = project / "nested"
        nested.mkdir()
        (project / "compose.override.yaml").touch()
        self.env.update(
            {"DOCKER_SSH_AUTH_SOCK": "/daemon/agent.sock", "DOCKER_SSH_AUTH_GID": "1234"}
        )
        self.assertEqual(self.run_cli("start", "api", cwd=nested), 0)
        self.assertEqual(
            self.action_calls()[0],
            [
                "docker", "compose", "-f", str(project / "compose.yaml"), "-f",
                str(project / "compose.override.yaml"), "-f",
                str(project / "docker-compose.ssh-agent.yml"), "up", "-d", "api",
            ],
        )

    def test_explicit_agent_override_is_cross_platform(self) -> None:
        project = self.make_compose_project()
        self.env.update(
            {
                "DOCKER_SSH_AUTH_SOCK": "/run/custom/ssh-agent.sock",
                "DOCKER_SSH_AUTH_GID": "1000",
            }
        )
        self.assertEqual(self.run_cli("start", "api", system="Windows", cwd=project), 0)
        environment = self.runner.environments[-1]
        self.assertEqual(environment["DOCKER_SSH_AUTH_SOCK"], "/run/custom/ssh-agent.sock")
        self.assertEqual(environment["DOCKER_SSH_AUTH_GID"], "1000")
        self.assertIn(str(project / "docker-compose.ssh-agent.yml"), self.action_calls()[0])

    def test_relative_compose_path_with_spaces_keeps_relative_overlay_paths(self) -> None:
        project = self.make_compose_project(self.root / "project with spaces")
        relative_compose = project.relative_to(self.root) / "compose.yaml"
        relative_overlay = project.relative_to(self.root) / "docker-compose.ssh-agent.yml"
        self.env.update(
            {"DOCKER_SSH_AUTH_SOCK": "/daemon/agent.sock", "DOCKER_SSH_AUTH_GID": "1234"}
        )
        self.assertEqual(self.run_cli("-f", str(relative_compose), "status"), 0)
        self.assertEqual(
            self.action_calls()[0],
            [
                "docker",
                "compose",
                "-f",
                str(relative_compose),
                "-f",
                str(relative_overlay),
                "ps",
                "--all",
            ],
        )

    def test_invalid_explicit_agent_configuration_fails_before_docker(self) -> None:
        self.make_compose_project()
        self.env["DOCKER_SSH_AUTH_SOCK"] = "/daemon/agent.sock"
        self.assertEqual(self.run_cli("start", "api"), 2)
        self.assertIn("set DOCKER_SSH_AUTH_GID explicitly", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

        self.stderr = io.StringIO()
        self.env["DOCKER_SSH_AUTH_GID"] = "not-a-number"
        self.assertEqual(self.run_cli("start", "api"), 2)
        self.assertIn("must be a numeric group ID", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

        self.stderr = io.StringIO()
        self.env["DOCKER_SSH_AUTH_GID"] = "١٢٣٤"
        self.assertEqual(self.run_cli("start", "api"), 2)
        self.assertIn("must be a numeric group ID", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

    def test_native_windows_warns_only_for_container_creation(self) -> None:
        self.make_compose_project()
        self.assertEqual(self.run_cli("start", "api", system="Windows"), 0)
        self.assertIn("unavailable on native Windows", self.stderr.getvalue())
        self.assertIn("Continuing without SSH-agent forwarding", self.stderr.getvalue())
        self.assertNotIn("docker-compose.ssh-agent.yml", self.action_calls()[0])

        self.stderr = io.StringIO()
        self.runner.calls.clear()
        self.assertEqual(self.run_cli("status", system="Windows"), 0)
        self.assertNotIn("Continuing without SSH-agent forwarding", self.stderr.getvalue())

    def test_windows_command_rendering_quotes_paths_with_spaces(self) -> None:
        self.assertEqual(
            self.run_cli(
                "--dry-run",
                "-f",
                r"C:\Work Space\compose.yml",
                "start",
                system="Windows",
            ),
            0,
        )
        self.assertIn('"C:\\Work Space\\compose.yml"', self.stderr.getvalue())

    def test_remove_safety_and_commands(self) -> None:
        self.assertEqual(self.run_cli("remove"), 2)
        self.assertIn("Re-run with global --force", self.stderr.getvalue())
        self.assertEqual(self.runner.calls, [])

        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("--force", "-f", "stack.yml", "remove"), 0)
        self.assertEqual(
            self.action_calls(),
            [["docker", "compose", "-f", "stack.yml", "down", "--remove-orphans"]],
        )

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("--force", "remove", "api", "worker"), 0)
        self.assertEqual(
            self.action_calls(),
            [["docker", "compose", "rm", "--stop", "--force", "api", "worker"]],
        )

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("--force", "remove", "--volumes"), 2)
        self.assertEqual(self.runner.calls, [])

    def test_interactive_confirmation_accepts_and_rejects(self) -> None:
        accepted = TTYStringIO("yes\n")
        self.assertEqual(self.run_cli("remove", stdin=accepted), 0)
        self.assertIn(["docker", "compose", "down", "--remove-orphans"], self.action_calls())

        self.runner.calls.clear()
        self.stderr = io.StringIO()
        rejected = TTYStringIO("no\n")
        self.assertEqual(self.run_cli("remove", stdin=rejected), 1)
        self.assertEqual(self.runner.calls, [])

        self.stderr = io.StringIO()
        whitespace = TTYStringIO(" yes \n")
        self.assertEqual(self.run_cli("remove", stdin=whitespace), 1)
        self.assertEqual(self.runner.calls, [])

    def test_cleanup_scope_dry_run_and_failures(self) -> None:
        self.assertEqual(self.run_cli("cleanup"), 2)
        self.assertEqual(self.runner.calls, [])

        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("--dry-run", "cleanup"), 0)
        output = self.stderr.getvalue()
        self.assertIn("+ docker system prune --all --volumes --force", output)
        self.assertIn("+ docker volume prune --all --force", output)

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("--force", "-f", "stack.yml", "cleanup"), 2)
        self.assertEqual(self.runner.calls, [])
        self.assertEqual(self.run_cli("--force", "cleanup", "extra"), 2)

        self.runner.calls.clear()
        self.assertEqual(self.run_cli("--force", "cleanup"), 0)
        self.assertEqual(
            self.action_calls(),
            [
                ["docker", "system", "prune", "--all", "--volumes", "--force"],
                ["docker", "volume", "prune", "--all", "--force"],
            ],
        )

        self.runner.calls.clear()
        self.runner.fail_match = ("system", "prune")
        self.runner.fail_status = 41
        self.assertEqual(self.run_cli("--force", "cleanup"), 41)
        self.assertNotIn("volume", [part for call in self.action_calls() for part in call])

        self.runner = FakeRunner()
        self.runner.fail_match = ("volume", "prune")
        self.runner.fail_status = 42
        self.assertEqual(self.run_cli("--force", "cleanup"), 42)

    def test_legacy_unknown_and_compose_option_errors(self) -> None:
        for action in ("container", "image", "compose"):
            with self.subTest(action=action):
                self.stderr = io.StringIO()
                self.assertEqual(self.run_cli(action, "list"), 2)
                self.assertIn("resource group was removed", self.stderr.getvalue())
        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("explode", "target"), 2)
        self.assertIn("Unknown action: explode", self.stderr.getvalue())
        self.assertEqual(self.run_cli("--file"), 2)
        self.assertIn("requires a value", self.stderr.getvalue())

    def test_preflight_and_action_exit_codes_propagate(self) -> None:
        self.runner.info_status = 55
        self.assertEqual(self.run_cli("status"), 55)
        self.assertIn("Cannot access the Docker daemon", self.stderr.getvalue())

        self.runner = FakeRunner()
        self.runner.compose_status = 56
        self.stderr = io.StringIO()
        self.assertEqual(self.run_cli("status"), 56)
        self.assertIn("Docker Compose v2 is unavailable", self.stderr.getvalue())

        self.runner = FakeRunner()
        self.runner.fail_match = ("logs", "broken")
        self.runner.fail_status = 43
        self.assertEqual(self.run_cli("logs", "broken"), 43)

        self.runner = FakeRunner()
        self.runner.fail_match = ("logs", "interrupted")
        self.runner.fail_status = -15
        self.assertEqual(self.run_cli("logs", "interrupted"), 143)

    def test_missing_docker_cli_is_reported(self) -> None:
        manager = DockerManager(
            env={}, cwd=self.root, stdin=io.StringIO(), stdout=self.stdout,
            stderr=self.stderr, system="Linux", executable_finder=lambda name: None,
            process_runner=self.runner, program_name="python docker_manage.py",
        )
        self.assertEqual(manager.run(["status"]), 127)
        self.assertIn("Docker CLI was not found", self.stderr.getvalue())

    def test_verbose_no_color_and_no_color_environment(self) -> None:
        self.assertEqual(self.run_cli("--no-color", "--verbose", "status"), 0)
        self.assertNotIn("\033", self.stderr.getvalue())
        self.assertIn("+ docker compose ps --all", self.stderr.getvalue())

        colored_stderr = TTYStringIO()
        self.env["NO_COLOR"] = "1"
        self.assertEqual(self.run_cli("--verbose", "status", stderr=colored_stderr), 0)
        self.assertNotIn("\033", colored_stderr.getvalue())

        colored_stderr = TTYStringIO()
        self.env["NO_COLOR"] = ""
        self.assertEqual(self.run_cli("--verbose", "status", stderr=colored_stderr), 0)
        self.assertIn("\033", colored_stderr.getvalue())

    def test_invalid_project_directory_does_not_discover_parent_overlay(self) -> None:
        project = self.make_compose_project()
        invalid_directory = project / "not-a-directory"
        invalid_directory.touch()
        self.env.update(
            {"DOCKER_SSH_AUTH_SOCK": "/daemon/agent.sock", "DOCKER_SSH_AUTH_GID": "1234"}
        )
        self.assertEqual(
            self.run_cli("--project-directory", str(invalid_directory), "start", "api"),
            0,
        )
        self.assertNotIn("docker-compose.ssh-agent.yml", self.action_calls()[0])

    def test_project_actions_use_compose_only(self) -> None:
        actions = (
            "start",
            "rebuild",
            "stop",
            "restart",
            "status",
            "logs",
            "build",
            "pull",
            "config",
        )
        for action in actions:
            with self.subTest(action=action):
                self.runner.calls.clear()
                self.run_cli(action)
                for call in self.action_calls():
                    self.assertEqual(call[:2], ["docker", "compose"])

    def test_devcontainer_launches_do_not_load_management_overlay(self) -> None:
        for devcontainer_file in (
            REPO_DIR / "generic/.devcontainer/devcontainer.json",
            REPO_DIR / "zephyr/.devcontainer/devcontainer.json",
            REPO_DIR / "tock/.devcontainer/devcontainer.json",
        ):
            content = devcontainer_file.read_text(encoding="utf-8")
            self.assertIn('"dockerComposeFile": "../docker-compose.yml"', content)
            self.assertNotIn("docker-compose.ssh-agent.yml", content)

    def test_keyboard_interrupt_returns_standard_shell_status(self) -> None:
        stderr = io.StringIO()
        with mock.patch.object(DockerManager, "run", side_effect=KeyboardInterrupt), mock.patch(
            "sys.stderr", stderr
        ):
            self.assertEqual(main(["status"]), 130)
        self.assertEqual(stderr.getvalue(), "\n")


class DirectScriptSmokeTests(unittest.TestCase):
    def test_help_runs_through_python_entry_point(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docker manage ") as working_directory:
            result = subprocess.run(
                [sys.executable, str(REPO_DIR / "docker_manage.py"), "--help"],
                cwd=working_directory,
                check=False,
                text=True,
                capture_output=True,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("python docker_manage.py [GLOBAL_OPTIONS]", result.stdout)


if __name__ == "__main__":
    unittest.main()
