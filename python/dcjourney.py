#!/usr/bin/env python3
"""Measure DC offset over time and distinguish local drift from the whole-file mean."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="dcjourney"))
