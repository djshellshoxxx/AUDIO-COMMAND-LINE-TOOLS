#!/usr/bin/env python3
"""Compare two renders at a supplied sample offset and report changed sections."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="renderdelta"))
