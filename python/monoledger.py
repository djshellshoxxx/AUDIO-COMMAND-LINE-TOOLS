#!/usr/bin/env python3
"""Locate active stereo windows that lose energy when folded to mono."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="monoledger"))
