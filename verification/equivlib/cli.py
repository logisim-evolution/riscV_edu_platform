"""Command line shared by verification/equiv.py and the per-module run.py launchers."""

import argparse
import fnmatch
import os
import shlex
import sys
from pathlib import Path

from . import container, flow, runner
from .config import LEVELS, ConfigError, discover, load_module
from .toolchain import ENVIRONMENTS, NoLocalToolchain, ToolchainError, resolve

REPO_ROOT = Path(__file__).resolve().parents[2]    # <repo>/verification/equivlib/cli.py -> <repo>
BUILD_ROOT = REPO_ROOT / "verification" / "build"

EXIT_FAILED = 1     # At least one check was not proven (failed, timeout, killed, error, or skipped by --fail-fast)
EXIT_USAGE = 2      # Usage or configuration error: bad arguments (argparse also exits with 2), unknown
                    # module or test name, invalid equivalence.toml, no tests selected
EXIT_TOOLCHAIN = 3  # No GHDL/Yosys found for the requested --env, or Docker missing / image build failed


def main(argv: list[str] | None = None, module: str | None = None) -> int:
    """Entry point. With 'module' set, only that module is tested (per-module launcher)."""
    parser = _parser(module)            # CLI argument parser
    args = parser.parse_args(argv)      # Parse the command line arguments (None: sys.argv)
    available = discover(REPO_ROOT)     # Discovered modules with equivalence.toml under hdl/modules

    # Testing just a module, all modules or a list of modules?
    if module is not None:
        names = [module]
    elif args.all:
        names = list(available)
    elif args.modules:
        names = list(dict.fromkeys(args.modules))   # Drop modules named twice, keep the order
    else:
        parser.error(f"name at least one module or pass --all (available: {', '.join(available) or 'none'})")

    # Check that all requested modules have an equivalence.toml
    unknown = [n for n in names if n not in available]
    if unknown:
        print(f"error: no hdl/modules/<module>/verification/equivalence.toml for {', '.join(unknown)} "
              f"(available: {', '.join(available) or 'none'})", file=sys.stderr)
        return EXIT_USAGE

    # Load the tests for the requested module(s) at the requested level (basic or extensive)
    try:
        tests = [t for name in names for t in load_module(name, available[name], args.level)]
    except ConfigError as error:
        print(f"error: {error}", file=sys.stderr)
        return EXIT_USAGE

    # Filter the tests by exact test name, if requested. An unknown name is an error (typo), while
    # a -k pattern below that matches nothing only leaves no tests.
    if args.tests:
        unknown = sorted(set(args.tests) - {t.name for t in tests})
        if unknown:
            print(f"error: unknown test(s) {', '.join(unknown)} "
                  f"(available: {', '.join(dict.fromkeys(t.name for t in tests))})", file=sys.stderr)
            return EXIT_USAGE
        tests = [t for t in tests if t.name in args.tests]

    # Filter the tests by pattern, if requested
    if args.patterns:
        tests = [t for t in tests if any(_matches(f"{t.module}/{t.id}", p) for p in args.patterns)]
    if not tests:
        print("error: no tests selected", file=sys.stderr)
        return EXIT_USAGE

    # List or validate without running the tools (no toolchain needed).
    if args.list:
        for test in tests:
            print(f"{test.module}/{test.id}")
        print(f"\n{len(tests)} test(s) at level '{args.level}'")
        return 0
    if args.check:
        return _check(tests, args.vcd)

    # Docker: run this whole program again inside the container, with the same arguments. The
    # selection above already happened on the host, so typos are reported before a container starts.
    if args.env == "docker":
        return _run_in_container(args, argv, module)

    # Fetch the toolchain (GHDL/Yosys binaries and environment) for the requested environment or auto-detect it
    try:
        toolchain = resolve(args.env)
    except NoLocalToolchain as error:
        # 'auto' found nothing locally: offer Docker as a last resort
        return _docker_fallback(str(error), args, argv, module)
    except ToolchainError as error:
        print(f"error: {error}", file=sys.stderr)
        return EXIT_TOOLCHAIN

    # Run the selected tests in parallel, with the requested timeout and fail-fast behavior
    try:
        results = runner.run_tests(tests, toolchain, BUILD_ROOT, REPO_ROOT, max(args.jobs, 1),
                                   args.timeout, args.fail_fast, args.vcd)
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130

    # Return 0 if all tests were proven, 1 otherwise (see EXIT_FAILED)
    return 0 if all(r.status == "proven" for r in results) else EXIT_FAILED


def _docker_fallback(reason: str, args: argparse.Namespace, argv: list[str] | None, module: str | None) -> int:
    """Ask whether to run in Docker after 'auto' found no local GHDL/Yosys ('reason'), and do so if accepted."""
    try:
        version = container.normalize_version(args.oss_cad_suite)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return EXIT_USAGE
    try:
        accepted = container.prompt_docker(version)
    except container.ContainerError as error:
        print(f"error: {reason}, and the Docker fallback is unavailable: {error}. "
              f"Install the OSS CAD Suite or choose another environment with --env.", file=sys.stderr)
        return EXIT_TOOLCHAIN
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130
    if not accepted:
        print(f"error: {reason}, and the Docker fallback was declined. Install the OSS CAD Suite, "
              f"or run in Docker without asking with --env docker.", file=sys.stderr)
        return EXIT_TOOLCHAIN
    return _run_in_container(args, argv, module, version)


def _run_in_container(args: argparse.Namespace, argv: list[str] | None, module: str | None,
                      version: str | None = None) -> int:
    """Run this program with the same arguments inside the Docker container; return its exit code."""
    if version is None:
        try:
            version = container.normalize_version(args.oss_cad_suite)
        except ValueError as error:
            print(f"error: {error}", file=sys.stderr)
            return EXIT_USAGE
    try:
        return container.run(sys.argv[1:] if argv is None else argv, module, REPO_ROOT,
                             version, args.rebuild_image)
    except container.ContainerError as error:
        print(f"error: {error}", file=sys.stderr)
        return EXIT_TOOLCHAIN


def _parser(module: str | None) -> argparse.ArgumentParser:
    """Create the command line parser.

    With 'module' set (per-module launcher), the MODULE arguments and --all don't exist, because
    the module is given by the launcher's location.
    """
    if module is None:
        parser = argparse.ArgumentParser(
            prog="verification/equiv.py",
            description="Formally prove the VHDL modules equivalent to their Verilog reference.")
        parser.add_argument("modules", nargs="*", metavar="MODULE", help="module(s) under hdl/modules to test")
        parser.add_argument("--all", action="store_true", help="test every module that has an equivalence.toml")
    else:
        parser = argparse.ArgumentParser(
            description=f"Formally prove the VHDL '{module}' module equivalent to its Verilog reference.")

    # Options shared by both entry points
    parser.add_argument("--level", choices=LEVELS, default="basic",
                        help="basic: one configuration per test (default), extensive: all configurations")
    parser.add_argument("-j", "--jobs", type=int, default=_default_jobs(),
                        help="number of tests to run in parallel (default: %(default)s, "
                             "leaving some CPU threads free for the rest of the system)")
    parser.add_argument("-t", "--test", dest="tests", action="append", metavar="NAME",
                        help="only run the test with this exact 'name' from equivalence.toml; repeatable")
    parser.add_argument("-k", dest="patterns", action="append", metavar="PATTERN",
                        help="only run tests whose 'module/id' matches the glob (substring without wildcards); "
                             "repeatable")
    parser.add_argument("--list", action="store_true", help="list the selected tests and exit")
    parser.add_argument("--check", action="store_true",
                        help="validate the configuration, print the commands and exit without running them")
    parser.add_argument("--vcd", action="store_true",
                        help="dump the counterexample of a failing proof, with all signals, "
                             "to <top>_counterexample.vcd")
    parser.add_argument("--fail-fast", action="store_true", help="stop starting new tests after the first failure")
    parser.add_argument("--timeout", type=float, metavar="SECONDS", help="time limit per test")
    parser.add_argument("--env", choices=ENVIRONMENTS, default="auto",
                        help="where GHDL/Yosys come from (default: auto = OSS CAD Suite, then PATH, then "
                             "asks to fall back to Docker; docker = run everything in a container)")
    # Only used with --env docker (or when --env auto falls back to Docker)
    parser.add_argument("--oss-cad-suite", default=container.DEFAULT_VERSION, metavar="VERSION",
                        help="--env docker: OSS CAD Suite release, 'latest' or a date YYYY-MM-DD "
                             "(default: $OSS_CAD_SUITE_VERSION or latest)")
    parser.add_argument("--rebuild-image", action="store_true",
                        help="--env docker: rebuild the image, e.g. to update a 'latest' image")
    return parser


def _default_jobs() -> int:
    """
    Return the default number of jobs to run in parallel.

    All usable CPU threads but about one in six (at least one), e.g. 20 of 24 or 7 of 8,
    to leave some for the rest of the system.
    """
    # process_cpu_count() only counts the threads this process may use (e.g. limited by taskset or
    # a container), unlike os.cpu_count()
    threads = os.process_cpu_count() or 1
    return max(1, threads - max(1, threads // 6))


def _matches(name: str, pattern: str) -> bool:
    """Return True if 'name' contains 'pattern', or, if the pattern has a wildcard (* ? [),
    if 'name' matches it as a glob. Both are case-sensitive."""
    if not any(c in pattern for c in "*?["):
        return pattern in name
    return fnmatch.fnmatchcase(name, pattern)


def _check(tests, dump_vcd: bool) -> int:
    """Plan every test and print the commands that would be run, without running them.

    Planning catches what loading the TOML can't, e.g. a top-level entity missing from the VHDL files.
    """
    for test in tests:
        try:
            plan = flow.plan(test, BUILD_ROOT, dump_vcd)
        except flow.FlowError as error:
            print(f"error: {test.module}/{test.id}: {error}", file=sys.stderr)
            return EXIT_USAGE
        print(f"### {test.module}/{test.id}")
        if plan.vhdl_override:
            print(f"# patched top-level copy: {plan.vhdl_override[0]}")
        print(f"$ ghdl {shlex.join(plan.ghdl_args)} > {plan.silver}")
        print(f"$ yosys -s {plan.script}")
        print(plan.script_text)
    print(f"{len(tests)} test(s) OK")
    return 0
