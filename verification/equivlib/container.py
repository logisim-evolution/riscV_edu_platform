"""Running the equivalence checks inside a Docker container (--env docker).

The whole runner is started once inside the container, instead of one container per GHDL/Yosys
call: the repository is mounted at the same path (/c/... on Windows), the runner inside uses the OSS CAD Suite of the
image (--env native), and build artifacts land in verification/build/ exactly as with a local
installation. The image is built from verification/docker/ when it doesn't exist yet.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

IMAGE_REPOSITORY = "riscv-edu-equiv"
DOCKER_DIR = Path(__file__).resolve().parents[1] / "docker"     # verification/docker/
DEFAULT_VERSION = os.environ.get("OSS_CAD_SUITE_VERSION", "latest")
DOCKER_RUN_FAILED = 125     # docker run's own exit code if the container could not be started


class ContainerError(Exception):
    """Docker is missing, or the image could not be built or started."""


def normalize_version(version: str) -> str:
    """'latest', or a release date as YYYY-MM-DD (YYYYMMDD is accepted as well); ValueError otherwise."""
    if re.fullmatch(r"\d{8}", version):
        version = f"{version[:4]}-{version[4:6]}-{version[6:]}"
    if version != "latest" and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", version):
        raise ValueError(f"invalid OSS CAD Suite version '{version}', expected latest or YYYY-MM-DD")
    return version


def image_name(version: str) -> str:
    """One image per OSS CAD Suite version, e.g. riscv-edu-equiv:oss-cad-suite-2026-10-23."""
    return f"{IMAGE_REPOSITORY}:oss-cad-suite-{version}"


def prompt_docker(version: str) -> bool:
    """Ask the user whether to run the checks inside Docker, after 'auto' found no local GHDL/Yosys.

    Returns ``True`` if the user accepts, ``False`` if they decline (or end the input with Ctrl-D).
    Raises :exc:`ContainerError` if Docker can't be used, or if there is no terminal to ask on
    (e.g. in CI), where waiting for an answer would fail.
    """
    docker = require_docker()
    if not sys.stdin.isatty():
        raise ContainerError("no interactive terminal to confirm the Docker fallback")
    image = image_name(version)
    if _exists(docker, image):
        print(f"\nNo local GHDL/Yosys found. The equivalence checks can run inside the cached\n"
              f"Docker image {image} ({_created(docker, image)}).\n")
    else:
        print(f"\nNo local GHDL/Yosys found. The equivalence checks can run inside a Docker container.\n"
              f"Building its image {image} downloads the OSS CAD Suite (~750 MB download,\n"
              f"~2.8 GB disk); the image is built once and reused for subsequent runs.\n")
    try:
        answer = input("Proceed with docker? [y/N] ")
    except EOFError:
        print()
        return False
    return answer.strip().lower() in ("y", "yes")


def require_docker() -> str:
    """Return the path of the docker client, after checking that its daemon can be reached."""
    docker = shutil.which("docker")
    if not docker:
        raise ContainerError("docker not found on PATH")
    try:
        result = subprocess.run([docker, "info", "--format", "{{.ServerVersion}}"],
                                capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        raise ContainerError(f"docker could not be started: {error}") from None
    if result.returncode != 0:
        # E.g. the daemon isn't running, or the user may not access its socket (docker group)
        lines = result.stderr.strip().splitlines()
        raise ContainerError(f"the Docker daemon can't be reached ({lines[-1] if lines else 'docker info failed'})")
    return docker


def run(argv: list[str], module: str | None, repo_root: Path, version: str, rebuild: bool) -> int:
    """Run the runner with the same arguments inside the container; return its exit code.

    'version' must already be normalized (normalize_version).
    """
    docker = require_docker()
    image = _ensure_image(docker, version, rebuild)

    # The same entry point as on the host, so a module launcher stays limited to its module.
    # '--env native' is appended last: argparse keeps the last value, overriding '--env docker'.
    script = f"hdl/modules/{module}/verification/run.py" if module else "verification/equiv.py"
    work_dir = _container_path(repo_root)
    # No --tty: docker only forwards signals (Ctrl-C) to the container without a TTY. The output
    # still appears immediately, because the image sets PYTHONUNBUFFERED.
    command = [
        docker, "run", "--rm",
        # tini as PID 1 forwards signals; with TINI_KILL_PROCESS_GROUP to the whole process group,
        # so GHDL/Yosys stop on Ctrl-C as well, like they do on the host
        "--init", "--env", "TINI_KILL_PROCESS_GROUP=1",
    ]
    if hasattr(os, "getuid"):
        # Build artifacts belong to the user, not root. Docker Desktop on Windows has no uids;
        # its file sharing gives the files to the Windows user anyway.
        command += ["--user", f"{os.getuid()}:{os.getgid()}"]
    command += [
        # --mount instead of --volume: a Windows drive letter's colon would split the --volume spec
        "--mount", f"type=bind,source={repo_root},target={work_dir}",
        "--workdir", work_dir,
        image, "python3", script, *argv, "--env", "native",
    ]
    print(f"Running in container {image} ({_created(docker, image)})", flush=True)
    process = subprocess.Popen(command)
    while True:
        try:
            code = process.wait()
            break
        except KeyboardInterrupt:
            # The docker client passes Ctrl-C on to the container; wait until the runner has stopped
            # instead of killing the client, which would leave the container running.
            continue
    if code == DOCKER_RUN_FAILED:
        raise ContainerError(f"'docker run' failed for {image}, see the message above")
    return code


def _container_path(path: Path) -> str:
    """The path of the repository inside the container: the same as on the host, except on Windows,
    where C:\\Users\\x becomes /c/Users/x (as in Git Bash), since the container is Linux."""
    if os.name != "nt":
        return str(path)
    drive, rest = os.path.splitdrive(str(path))
    return f"/{drive.rstrip(':').lower()}{rest.replace(chr(92), '/')}"


def _ensure_image(docker: str, version: str, rebuild: bool) -> str:
    """Build the image of this OSS CAD Suite version if it doesn't exist (or if 'rebuild')."""
    image = image_name(version)
    if not rebuild and _exists(docker, image):
        return image
    print(f"Building {image} from {DOCKER_DIR} (downloads the OSS CAD Suite, about 750 MB) ...", flush=True)
    command = [docker, "build", "--build-arg", f"OSS_CAD_SUITE_VERSION={version}", "--tag", image]
    if rebuild:
        # Docker caches the install step by its arguments, and 'latest' stays the same string:
        # without --no-cache a rebuild would reuse the old suite. --pull refreshes the Python image.
        command += ["--pull", "--no-cache"]
    if subprocess.run([*command, str(DOCKER_DIR)]).returncode != 0:
        raise ContainerError(f"building {image} failed, see the docker output above")
    return image


def _exists(docker: str, image: str) -> bool:
    return subprocess.run([docker, "image", "inspect", image],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def _created(docker: str, image: str) -> str:
    """'built YYYY-MM-DD', so it is visible how old a 'latest' image is."""
    result = subprocess.run([docker, "image", "inspect", "--format", "{{.Created}}", image],
                            capture_output=True, text=True)
    return f"built {result.stdout[:10]}" if result.returncode == 0 and result.stdout else "build date unknown"
