#!/usr/bin/env python3
"""
Watch a folder for AirDrop/iPhone HEIC photos and convert them to JPG or PNG.

Defaults are intentionally safe:
- watches ~/Downloads, where AirDrop stores incoming files on macOS
- writes .JPG files next to the .HEIC files
- asks once before deleting the original .HEIC files after a successful batch
"""

from __future__ import annotations

import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


LABEL = "AirDrop HEIC Converter"
DEFAULT_POLL_SECONDS = 5
SUPPORTED_OUTPUTS = {
    "jpg": ("jpeg", ".JPG"),
    "jpeg": ("jpeg", ".JPG"),
    "png": ("png", ".PNG"),
}

running = True


def env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "y", "on", "si", "sí"}


def running_as_launch_agent() -> bool:
    return os.environ.get("XPC_SERVICE_NAME") == "com.juma.airdrop-heic-converter"


def detach_launch_agent_stdio() -> None:
    if not running_as_launch_agent():
        return

    log_dir = Path.home() / "Library" / "Logs" / "airdrop-heic-converter"
    log_dir.mkdir(parents=True, exist_ok=True)

    with open(os.devnull, "rb", buffering=0) as stdin_file:
        os.dup2(stdin_file.fileno(), 0)
    with open(log_dir / "launchd.out.log", "ab", buffering=0) as stdout_file:
        os.dup2(stdout_file.fileno(), 1)
    with open(log_dir / "launchd.err.log", "ab", buffering=0) as stderr_file:
        os.dup2(stderr_file.fileno(), 2)


def setup_logging() -> None:
    log_dir = Path.home() / "Library" / "Logs" / "airdrop-heic-converter"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "watcher.log"

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[
            logging.FileHandler(log_file, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


def stop(_signum: int, _frame: object) -> None:
    global running
    running = False


def run_osascript(script: str, timeout_seconds: int = 20) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        logging.warning("Could not run macOS UI script: %s", exc)
        return None


def apple_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str) -> None:
    script = (
        f'display notification "{apple_quote(message)}" '
        f'with title "{apple_quote(title)}"'
    )
    run_osascript(script)


def ask_to_delete_originals(converted: list[tuple[Path, Path]], extension: str) -> bool:
    count = len(converted)
    if count == 0:
        return False

    photo_word = "foto" if count == 1 else "fotos"
    pronoun = "La eliminamos" if count == 1 else "Las eliminamos"
    message = (
        f"{count} {photo_word} procesadas a {extension.lower()}.\\n\\n"
        f"¿{pronoun}?"
    )
    script = (
        f'set answer to display dialog "{apple_quote(message)}" '
        'buttons {"Cerrar", "No", "Si"} '
        'default button "No" cancel button "Cerrar" '
        'with title "AirDrop HEIC Converter" '
        'with icon note '
        'giving up after 180\n'
        'if button returned of answer is "Si" then\n'
        '  return "delete"\n'
        'else\n'
        '  return "keep"\n'
        'end if'
    )
    result = run_osascript(script, timeout_seconds=190)
    return bool(result and result.returncode == 0 and result.stdout.strip() == "delete")


def is_stable(path: Path, wait_seconds: float = 1.0) -> bool:
    """Return True when the file size is unchanged, so AirDrop likely finished."""
    try:
        first = path.stat()
        time.sleep(wait_seconds)
        second = path.stat()
    except FileNotFoundError:
        return False

    return first.st_size > 0 and first.st_size == second.st_size


def output_path_for(source: Path, extension: str) -> Path:
    candidate = source.with_suffix(extension)
    if not candidate.exists():
        return candidate

    try:
        if candidate.stat().st_mtime >= source.stat().st_mtime and candidate.stat().st_size > 0:
            return candidate
    except FileNotFoundError:
        return candidate

    index = 1
    while True:
        candidate = source.with_name(f"{source.stem}-{index}{extension}")
        if not candidate.exists():
            return candidate
        index += 1


def should_skip(source: Path, destination: Path, delete_original: bool) -> bool:
    if delete_original:
        return False
    if not destination.exists():
        return False

    try:
        return destination.stat().st_mtime >= source.stat().st_mtime and destination.stat().st_size > 0
    except FileNotFoundError:
        return False


def convert(
    source: Path,
    sips_format: str,
    extension: str,
    delete_original: bool,
) -> tuple[Path, Path] | None:
    destination = output_path_for(source, extension)

    if should_skip(source, destination, delete_original):
        logging.debug("Already converted: %s", source)
        return None

    if not is_stable(source):
        logging.info("Waiting for transfer to finish: %s", source.name)
        return None

    tmp_destination = destination.with_name(f".{destination.name}.tmp")
    command = [
        "/usr/bin/sips",
        "-s",
        "format",
        sips_format,
        str(source),
        "--out",
        str(tmp_destination),
    ]

    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
        tmp_destination.replace(destination)
        logging.info("Converted %s -> %s", source.name, destination.name)

        if delete_original:
            source.unlink()
            logging.info("Deleted original %s", source.name)
            return None

        return (source, destination)
    except subprocess.CalledProcessError as exc:
        logging.error("Conversion failed for %s: %s%s", source, exc.stdout, exc.stderr)
    except OSError as exc:
        logging.error("Could not convert %s: %s", source, exc)
    finally:
        if tmp_destination.exists():
            try:
                tmp_destination.unlink()
            except OSError:
                pass

    return None


def delete_originals(converted: list[tuple[Path, Path]]) -> None:
    for source, _destination in converted:
        try:
            source.unlink()
            logging.info("Deleted original %s", source.name)
        except FileNotFoundError:
            continue
        except OSError as exc:
            logging.error("Could not delete original %s: %s", source, exc)


def iter_heic_files(folder: Path) -> list[Path]:
    try:
        return sorted(
            [path for path in folder.iterdir() if path.is_file() and path.suffix.lower() == ".heic"],
            key=lambda path: path.stat().st_mtime,
        )
    except FileNotFoundError:
        folder.mkdir(parents=True, exist_ok=True)
        return []


def main() -> int:
    detach_launch_agent_stdio()
    setup_logging()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    watch_dir = Path(os.environ.get("AIRDROP_CONVERT_DIR", "~/Downloads")).expanduser()
    output_format = os.environ.get("AIRDROP_OUTPUT_FORMAT", "jpg").strip().lower()
    delete_original = env_bool("AIRDROP_DELETE_ORIGINAL", False)
    ask_delete_original = env_bool("AIRDROP_ASK_DELETE_ORIGINAL", True)
    notify_start = env_bool("AIRDROP_NOTIFY_START", True)
    poll_seconds = float(os.environ.get("AIRDROP_POLL_SECONDS", DEFAULT_POLL_SECONDS))

    if output_format not in SUPPORTED_OUTPUTS:
        logging.error("Unsupported AIRDROP_OUTPUT_FORMAT=%r. Use jpg or png.", output_format)
        return 2

    sips_format, extension = SUPPORTED_OUTPUTS[output_format]
    logging.info(
        "%s started. Watching %s, output=%s, delete_original=%s",
        LABEL,
        watch_dir,
        extension,
        delete_original,
    )
    if notify_start:
        notify("AirDrop HEIC Converter activo", f"Vigilando {watch_dir}")

    while running:
        converted: list[tuple[Path, Path]] = []
        for source in iter_heic_files(watch_dir):
            result = convert(source, sips_format, extension, delete_original)
            if result is not None:
                converted.append(result)

        if converted:
            count = len(converted)
            photo_word = "foto" if count == 1 else "fotos"
            notify("Fotos convertidas", f"{count} {photo_word} procesadas a {extension.lower()}")
            logging.info("Processed batch: %s %s to %s", count, photo_word, extension)
            if ask_delete_original and not delete_original and ask_to_delete_originals(converted, extension):
                delete_originals(converted)

        time.sleep(poll_seconds)

    logging.info("%s stopped.", LABEL)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
