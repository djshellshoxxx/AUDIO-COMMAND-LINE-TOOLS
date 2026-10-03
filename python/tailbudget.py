#!/usr/bin/env python3
"""Find the last sample above a threshold and budget how much quiet tail to keep."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="tailbudget"))
