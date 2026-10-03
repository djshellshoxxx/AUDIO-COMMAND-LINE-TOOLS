#!/usr/bin/env python3
"""Calculate a gain budget before changing audio and show which channels set the limit."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="gainbudget"))
