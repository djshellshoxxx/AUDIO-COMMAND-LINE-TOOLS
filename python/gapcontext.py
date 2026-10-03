#!/usr/bin/env python3
"""Find interior quiet runs bordered by active audio, with context energy attached."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="gapcontext"))
