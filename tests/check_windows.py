"""Run a clean Godot import and launch tests in a Unicode Windows path.

Called by .github/workflows/windows.yml with GODOT_CONSOLE set to the official
Windows console executable. Never touches the user's normal save slot.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import traceback

# Windows console encodings vary. Preserve diagnostic output from Unicode
# project paths rather than failing to print it on non-UTF-8 code pages.
sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")

ERROR_LINE = re.compile(r"^(?:SCRIPT ERROR|Parse Error|ERROR:|SMOKE TESTS FAILED|.*ObjectDB instances leaked)", re.MULTILINE)


def run(label: str, args: list[str], *, require: str = "", optional: bool = False) -> bool:
    print(f"\n--- {label} ---", flush=True)
    try:
        result = subprocess.run(
            [os.environ["GODOT_CONSOLE"], *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=240,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        print(f"{label} timed out after {exc.timeout} seconds", flush=True)
        if optional:
            print(f"::warning::{label} could not finish on the CI virtual display", flush=True)
            return False
        raise
    print(result.stdout, flush=True)
    errors = ERROR_LINE.findall(result.stdout)
    missing_result = bool(require and require not in result.stdout)
    if result.returncode == 0 and not errors and not missing_result:
        return True
    lines = result.stdout.splitlines()
    details = "\n".join(lines[-60:])[-8000:]
    details = details.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    level = "warning" if optional else "error"
    print(f"::{level}::{label} exited {result.returncode}. {details}", flush=True)
    return False


def main() -> int:
    source = Path(os.environ["GITHUB_WORKSPACE"])
    # Match common Windows installations where the username or project folder
    # is Cyrillic; avoid sharing imported resources from another Godot version.
    destination = Path(tempfile.mkdtemp(prefix="godot-")) / "Проверка игры"
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".git", ".godot"))
    path = str(destination)
    os.environ["SHARDS_TEST_SAVE"] = "1"
    if not run("Clean project import", ["--headless", "--editor", "--path", path, "--quit"]):
        return 1
    if not run("Main scene startup", ["--verbose", "--headless", "--path", path, "--quit-after", "120"]):
        return 1
    if not run("Playable chapter", ["--headless", "--path", path, "--script", "res://tests/smoke_test.gd"], require="ALL SMOKE TESTS PASSED"):
        return 1
    # GitHub-hosted Windows VMs do not guarantee a usable graphics device.
    # This is an additional diagnostic, not a substitute for headless tests.
    run("Windowed game startup", ["--path", path, "--quit-after", "120"], optional=True)
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except Exception:
        details = traceback.format_exc()
        print(details, flush=True)
        details = details.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error::Windows startup check failed unexpectedly: {details}", flush=True)
        code = 1
    sys.exit(code)
