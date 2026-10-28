"""Selection of the environment that provides GHDL and Yosys."""

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

ENVIRONMENTS = ("auto", "native", "path", "docker")
DEFAULT_OSS_CAD_SUITE = "/opt/oss-cad-suite"


class ToolchainError(Exception):
    """No usable GHDL/Yosys installation was found for the requested environment."""


class NoLocalToolchain(ToolchainError):
    """'auto' found no local GHDL/Yosys; the caller may fall back to Docker."""


@dataclass
class Toolchain:
    """A toolchain is a set of GHDL and Yosys binaries with an environment to run them in."""
    name: str           # native, path or docker
    description: str    # Shown at the start of a run and written to build/toolchain.txt
    ghdl: str           # Absolute paths, so the tools don't depend on PATH lookups
    yosys: str
    env: dict[str, str] # Environment variables for the GHDL and Yosys processes

    def versions(self) -> dict[str, str]:
        """Return the versions of GHDL and Yosys (first output line), or 'unknown' if they can't be determined."""
        result = {}
        for tool, argv in (("ghdl", [self.ghdl, "--version"]), ("yosys", [self.yosys, "-V"])):
            try:
                output = subprocess.run(argv, env=self.env, capture_output=True, text=True, timeout=30).stdout
                result[tool] = output.splitlines()[0] if output else "unknown"
            except (OSError, subprocess.SubprocessError):
                result[tool] = "unknown"
        return result


def resolve(choice: str) -> Toolchain:
    """Return the toolchain for 'native' or 'path'; 'auto' tries native, then path.

    Raises :exc:`NoLocalToolchain` when 'auto' finds neither, so the caller can offer the Docker
    fallback, and :exc:`ToolchainError` when an explicitly requested environment is missing.
    """
    if choice == "docker":
        return _docker()
    if choice in ("auto", "native"):
        toolchain = _native()
        # Found, or 'native' explicitly requested: no fallback (_missing raises)
        if toolchain or choice == "native":
            return toolchain or _missing(
                f"OSS CAD Suite not found at {_oss_cad_suite_root()} (set OSS_CAD_SUITE to its location)")

    # 'path', or 'auto' without an OSS CAD Suite
    toolchain = _path()
    if toolchain:
        return toolchain
    if choice == "auto":
        raise NoLocalToolchain(
            f"neither the OSS CAD Suite ({_oss_cad_suite_root()}) nor ghdl/yosys on PATH were found")
    _missing("ghdl and/or yosys not found on PATH")


def _oss_cad_suite_root() -> Path:
    """The OSS CAD Suite installation: $OSS_CAD_SUITE, or /opt/oss-cad-suite if it isn't set."""
    return Path(os.environ.get("OSS_CAD_SUITE", DEFAULT_OSS_CAD_SUITE))


def _native() -> Toolchain | None:
    """The OSS CAD Suite, with the same variables its environment script sets."""
    root = _oss_cad_suite_root()
    ghdl, yosys = root / "bin" / "ghdl", root / "bin" / "yosys"
    if not (ghdl.is_file() and yosys.is_file()):
        return None
    # Equivalent of 'source environment.fish', but only for the child processes: the suite's
    # tools first on PATH, its own GHDL libraries and Verilator, and no foreign PYTHONHOME
    env = dict(os.environ)
    env.pop("PYTHONHOME", None)
    env["PATH"] = os.pathsep.join([str(root / "bin"), str(root / "py3bin"), env.get("PATH", "")])
    env["GHDL_PREFIX"] = str(root / "lib" / "ghdl")
    env["VERILATOR_ROOT"] = str(root / "share" / "verilator")
    return Toolchain("native", f"OSS CAD Suite at {root}", str(ghdl), str(yosys), env)


def _path() -> Toolchain | None:
    """Whatever ghdl and yosys are on PATH, e.g. distribution packages or inside a container."""
    ghdl, yosys = shutil.which("ghdl"), shutil.which("yosys")
    if not (ghdl and yosys):
        return None
    return Toolchain("path", "ghdl/yosys from PATH", ghdl, yosys, dict(os.environ))


def _docker() -> Toolchain:
    # Docker is no toolchain in this process: cli.main() runs the whole runner inside a container
    # instead (see container.py), where it uses --env native. Getting here is a programming error.
    raise ToolchainError("--env docker is handled by equivlib.container, not by toolchain.resolve()")


def _missing(reason: str):
    """Raise a ToolchainError with the reason and a hint how to fix it."""
    raise ToolchainError(f"{reason}. Install the OSS CAD Suite or choose another environment with --env.")
