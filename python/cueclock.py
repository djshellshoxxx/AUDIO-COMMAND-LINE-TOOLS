#!/usr/bin/env python3
"""Generate a musical cue grid rounded independently to exact audio frames."""
import sys
from drift_audio import main
if __name__ == "__main__": sys.exit(main(fixed_tool="cueclock"))
