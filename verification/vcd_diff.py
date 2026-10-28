#!/usr/bin/env python3
"""Show which gold/gate signals of a failed equivalence check differ, and since which SAT step.

Usage: verification/vcd_diff.py <build dir>/<module>/<test>/<top>_counterexample.vcd [--step N]
The runner does this automatically for failing checks run with --vcd. See verification/README.md.
"""

import argparse
import sys
from pathlib import Path

from equivlib import vcddiff


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("vcd", type=Path, help="counterexample written by an equivalence check with --vcd")
    parser.add_argument("--step", type=int, help="show the differences at this SAT step instead of the first one")
    parser.add_argument("--netlist", type=Path,
                        help="GHDL netlist to identify the outputs (default: <top>.v next to the VCD)")
    args = parser.parse_args()

    if not args.vcd.is_file():
        parser.error(f"file not found: {args.vcd}")
    # <top>_counterexample.vcd -> <top>.v, the GHDL netlist the runner writes next to it
    netlist = args.netlist or args.vcd.with_name(args.vcd.name.removesuffix("_counterexample.vcd") + ".v")
    analysis = vcddiff.analyze(args.vcd, netlist)
    if args.step is not None and not 1 <= args.step <= analysis.steps:
        parser.error(f"--step must be between 1 and {analysis.steps}")
    print(vcddiff.report(analysis, args.vcd, args.step), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
