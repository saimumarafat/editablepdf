#!/usr/bin/env python3
"""Optional Mac helper: run Tesseract CLI on an image (same role as dev_ocr_compare.rb)."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <image.png>", file=sys.stderr)
        sys.exit(1)
    path = Path(sys.argv[1])
    if not path.is_file():
        print("File not found:", path, file=sys.stderr)
        sys.exit(1)
    ts = shutil.which("tesseract")
    if not ts:
        print(
            "tesseract not in PATH. Install: brew install tesseract\n"
            "The iOS app uses Apple Vision; this is only for desktop comparison.",
            file=sys.stderr,
        )
        sys.exit(1)
    with tempfile.TemporaryDirectory(prefix="ocr_compare_") as d:
        out = Path(d) / "out"
        subprocess.run([ts, str(path), str(out), "-l", "eng"], check=True)
        print((out.with_suffix(".txt")).read_text())


if __name__ == "__main__":
    main()
