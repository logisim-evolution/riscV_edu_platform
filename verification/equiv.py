#!/usr/bin/env python3
"""Run the equivalence checks of one, several or all modules. See verification/README.md."""

import sys

# Python puts this script's folder on the module search path, so equivlib is found from any
# working directory
from equivlib.cli import main

if __name__ == "__main__":
    sys.exit(main())
