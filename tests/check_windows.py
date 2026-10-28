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


def run(label: str, args: list[str], *, require: str = "", forbid: str = "") -> bool:
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
        raise
    print(result.stdout, flush=True)
    errors = ERROR_LINE.findall(result.stdout)
    missing_result = bool(require and require not in result.stdout)
    eager_load = bool(forbid and forbid in result.stdout)
    if result.returncode == 0 and not errors and not missing_result and not eager_load:
        return True
    lines = result.stdout.splitlines()
    details = "\n".join(lines[-60:])[-8000:]
    details = details.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error::{label} exited {result.returncode} (missing expected result: {missing_result}; unexpected eager load: {eager_load}). {details}", flush=True)
    return False


def run_editor_f5_probe(path: Path) -> bool:
    # Install the test plugin only in a disposable copy. The actual project
    # has no enabled editor plugins, and a player's setup must remain intact.
    with tempfile.TemporaryDirectory(prefix="shards-editor-test-") as temp_dir:
        project = Path(temp_dir) / "Проверка редактора F5"
        shutil.copytree(path, project)
        plugin = project / "addons" / "f5_probe"
        plugin.mkdir(parents=True)
        shutil.copyfile(project / "tests" / "editor_f5_probe.gd.txt", plugin / "plugin.gd")
        (plugin / "plugin.cfg").write_text(
            '[plugin]\nname="Temporary F5 probe"\ndescription="CI-only startup test"\n'
            'author="CI"\nversion="1.0"\nscript="plugin.gd"\n',
            encoding="utf-8",
        )
        # The editor's audio-driver argument is not forwarded to the game.
        # The Windows runner has no sound device, so pass Dummy to both.
        with (project / "project.godot").open("a", encoding="utf-8") as config:
            config.write(
                '\n[editor]\nrun/main_run_args="--audio-driver Dummy"\n'
                '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/f5_probe/plugin.cfg")\n'
            )
        return run(
            "Windowed editor F5 startup",
            ["--audio-driver", "Dummy", "--editor", "--max-fps", "60", "--path", str(project)],
            require="EDITOR F5 STARTUP PASSED",
        )


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
    if not run("Main scene startup", ["--verbose", "--headless", "--path", path, "--max-fps", "60", "--quit-after", "120"], forbid="Loading resource: res://assets/models/environment/user_island.glb"):
        return 1
    if not run("Playable chapter", ["--headless", "--path", path, "--script", "res://tests/smoke_test.gd"], require="ALL SMOKE TESTS PASSED"):
        return 1
    # Hosted Windows VMs use software graphics and have no sound device, so
    # choose Dummy audio while checking that an actual window and menu render.
    if not run("Windowed menu startup", ["--audio-driver", "Dummy", "--path", path, "--script", "res://tests/startup_test.gd"], require="MAIN MENU STARTUP PASSED"):
        return 1
    if not run("Windowed new game and legacy save", ["--audio-driver", "Dummy", "--path", path, "--max-fps", "60", "--resolution", "960x540", "--script", "res://tests/windowed_game_test.gd"], require="WINDOWED GAME STARTUP PASSED"):
        return 1
    if not run_editor_f5_probe(destination):
        return 1
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
