#!/usr/bin/env python3
"""Run the equivalence checks of this module only. See verification/README.md in the repository root."""

import sys
from pathlib import Path

# HERE is <repo>/hdl/modules/<module>/verification, so parents[3] is the repository root. Putting
# <repo>/verification on the module search path makes the shared equivlib package importable.
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[3] / "verification"))

from equivlib.cli import main

if __name__ == "__main__":
    sys.exit(main(module=HERE.parent.name))
