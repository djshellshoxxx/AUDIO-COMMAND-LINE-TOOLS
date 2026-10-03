#!/usr/bin/env python3
"""Map consecutive near-full-scale samples by channel instead of reporting only a peak."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="railruns"))
