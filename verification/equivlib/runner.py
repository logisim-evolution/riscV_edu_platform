"""Parallel execution of equivalence tests with progress output and a results summary."""

import csv
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

from . import flow
from .config import EquivTest
from .toolchain import Toolchain

ICONS = {"proven": "✅", "skipped": "⏭️"}   # Every other status is shown as ❌
TAIL_LINES = 15         # Log lines shown for a failure without counterexample analysis
REPORT_LINES = 25       # Lines of the counterexample analysis shown for a failure


@dataclass
class Result:
    """The result of one equivalence test."""
    test: EquivTest         # The equivalence test that was run
    status: str             # proven, ghdl-synth-failed, equivalence-failed, timeout, killed, error or skipped
    seconds: float          # The elapsed time of the test, in seconds
    plan: flow.Plan | None  # The flow plan that was executed, or None if the test was skipped or failed to plan


def run_tests(tests: list[EquivTest], toolchain: Toolchain, build_root: Path, repo_root: Path,
              jobs: int, timeout: float | None, fail_fast: bool,
              dump_vcd: bool = False) -> list[Result]:
    """
    Run the given equivalence tests in parallel, with the given toolchain and timeout, and return the results.

    Parameters:
        tests: The equivalence tests to run.
        toolchain: The toolchain to use for running the tests.
        build_root: The root directory for build artifacts.
        repo_root: The root directory of the repository, for relative paths in output.
        jobs: The number of tests to run in parallel.
        timeout: The time limit for each test, in seconds. None means no limit.
        fail_fast: If True, stop starting new tests after the first failure.
        dump_vcd: If True, dump the counterexample of a failing proof to a VCD file.
    Returns:
        A list of Result objects, one for each test, in the same order as the input tests.
    """
    build_root.mkdir(parents=True, exist_ok=True)
    versions = toolchain.versions()
    # Write the toolchain description and versions to a file in the build root, for reproducibility.
    (build_root / "toolchain.txt").write_text(
        f"environment: {toolchain.description}\n" + "".join(f"{k}: {v}\n" for k, v in versions.items()))
    print(f"Running {len(tests)} equivalence check(s) on {jobs} worker(s), {toolchain.description}")
    print(f"  {versions['ghdl']}\n  {versions['yosys']}\n")

    stop = threading.Event()        # Set by --fail-fast or Ctrl-C: tests not started yet are skipped
    results: list[Result] = []      # Filled in completion order, sorted at the end
    width = len(str(len(tests)))    # Digits of the test count, to align the [ n/total] progress
    started = time.monotonic()

    def work(test: EquivTest) -> Result:
        """Run one equivalence test and return its result. Runs in a worker thread."""
        if stop.is_set():
            return Result(test, "skipped", 0.0, None)
        begin = time.monotonic()
        plan = None

        # Failing proofs and tool errors are statuses returned by execute(). Exceptions only occur
        # if the test can't be set up (FlowError) or files can't be written (OSError).
        try:
            plan = flow.plan(test, build_root, dump_vcd)
            status = flow.execute(plan, toolchain, timeout)
        except (flow.FlowError, OSError) as error:
            status = "error"
            # Write the error into the log if the work directory exists, otherwise print it right away
            if plan and plan.workdir.is_dir():
                with plan.log.open("a") as f:
                    f.write(f"\n*** {error} ***\n")
            else:
                print(f"    {test.module}/{test.id}: {error}")
        return Result(test, status, time.monotonic() - begin, plan)

    # Run the tests in parallel, with progress output and fail-fast behavior. The threads only
    # wait for the GHDL/Yosys processes, so threads are enough (no multiprocessing needed).
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = [executor.submit(work, test) for test in tests]
        # as_completed() returns each test as soon as it finishes. Only this (main) thread prints
        # and collects results, so the output doesn't interleave and no locks are needed.
        try:
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                if result.status == "skipped":
                    continue
                print(f"[{len(results):>{width}}/{len(tests)}] {ICONS.get(result.status, '❌')} "
                      f"{result.test.module}/{result.test.id} ({result.seconds:.1f} s)", flush=True)
                if result.status != "proven":
                    _report_failure(result, repo_root)
                    if fail_fast:
                        stop.set()
        except KeyboardInterrupt:
            # Ctrl-C: drop queued tests. Running GHDL/Yosys processes receive the SIGINT from the
            # terminal themselves; leaving the 'with' block waits until they have ended.
            stop.set()
            executor.shutdown(cancel_futures=True)
            raise

    # Sort the results in the same order as the input tests, write them to a CSV file, and print a summary.
    results.sort(key=lambda r: tests.index(r.test))
    _write_csv(results, build_root / "results.csv", repo_root)
    _summary(results, time.monotonic() - started, build_root / "results.csv", repo_root)
    return results


def _report_failure(result: Result, repo_root: Path):
    """Print the status and log path of a failing test, then its counterexample analysis
    (if --vcd produced one) or else the end of its log."""
    plan = result.plan
    print(f"    {result.status}", end="")
    if not (plan and plan.log.is_file()):
        print()
        return
    print(f", log: {_relative(plan.log, repo_root)}")

    # Print the counterexample analysis if available, otherwise the last lines of the log.
    if plan.divergence and plan.divergence.is_file():
        # The analysis says more than the end of the Yosys output
        lines = plan.divergence.read_text(errors="replace").splitlines()
        for line in lines[:REPORT_LINES]:
            print(f"    | {line}")
        if len(lines) > REPORT_LINES:
            print(f"    | ... {len(lines) - REPORT_LINES} more line(s) in {_relative(plan.divergence, repo_root)}")
    else:
        for line in plan.log.read_text(errors="replace").splitlines()[-TAIL_LINES:]:
            print(f"    | {line}")

    # Print the path to the counterexample VCD if it exists.
    if plan.vcd and plan.vcd.is_file():
        print(f"    counterexample: {_relative(plan.vcd, repo_root)}")


def _write_csv(results: list[Result], path: Path, repo_root: Path):
    """Write the results of the tests to a CSV file."""
    with path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["module", "test", "status", "seconds", "log"])
        for r in results:
            writer.writerow([r.test.module, r.test.id, r.status, f"{r.seconds:.1f}",
                             _relative(r.plan.log, repo_root) if r.plan else ""])


def _summary(results: list[Result], seconds: float, csv_path: Path, repo_root: Path):
    """Print a summary of the results of the tests."""
    counts = Counter(r.status for r in results)
    print(f"\n{len(results)} check(s) in {seconds:.1f} s: "
          + ", ".join(f"{count} {status}" for status, count in counts.most_common()))
    failed = [r for r in results if r.status not in ("proven", "skipped")]
    for r in failed:
        print(f"  ❌ {r.test.module}/{r.test.id}: {r.status}")
    print(f"Results: {_relative(csv_path, repo_root)}")


def _relative(path: Path, root: Path) -> str:
    """Return the path relative to the root, or the absolute path if not under the root."""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)
