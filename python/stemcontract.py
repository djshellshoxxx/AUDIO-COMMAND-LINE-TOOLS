#!/usr/bin/env python3
"""Check exported files against an explicit rate, channel, length and filename contract."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="stemcontract"))
