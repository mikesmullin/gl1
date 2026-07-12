#!/usr/bin/env python3
"""Build, package, and publish gl1 releases to GitHub.

Produces one .zip per OS (linux, windows, macos), each containing the
executable and runtime assets, then uploads them with `gh release`.

Examples:
  ./tools/release.py                  # build all possible, upload as v{VERSION}
  ./tools/release.py --version 0.2.0  # override tag/version string
  ./tools/release.py --skip-upload    # build + zip only → dist/
  ./tools/release.py --platforms linux,windows
  ./tools/release.py --draft          # create as draft release

Requirements:
  - zig (master / project-tested version)
  - gh (authenticated: gh auth login)
  - On Linux: windows cross-compile works; macOS needs macOS SDK (usually skip)
"""

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
ZIG_OUT = ROOT / "zig-out"

# Runtime assets shipped next to the binary (cwd = install dir when running).
ASSET_FILES = [
    Path("assets/fonts/glyphs-outline.bmp"),
    Path("assets/icons/icons.png"),
    Path("assets/icons/icons.yaml"),
    # Optional demo image (also embedded, but useful for runtime reload later)
    Path("assets/demo/fire-dragon.png"),
]


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def run(cmd: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, cwd=cwd or ROOT, check=check)


def read_version_from_source() -> str:
    main_zig = ROOT / "src" / "main.zig"
    text = main_zig.read_text(encoding="utf-8")
    m = re.search(r'const VERSION = "([^"]+)"', text)
    if not m:
        die(f"could not find VERSION in {main_zig}")
    return m.group(1)


def host_linux_triple() -> str:
    machine = platform.machine().lower()
    arch = {
        "x86_64": "x86_64",
        "amd64": "x86_64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
    }.get(machine, machine)
    return f"{arch}-linux"


def copy_assets(dest_root: Path) -> None:
    for rel in ASSET_FILES:
        src = ROOT / rel
        if not src.is_file():
            print(f"  warning: missing asset {rel} (skipped)")
            continue
        dst = dest_root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  + {rel}")


def zip_dir(src_dir: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(src_dir.rglob("*")):
            if path.is_file():
                arc = path.relative_to(src_dir.parent)
                zf.write(path, arcname=str(arc))
    size = zip_path.stat().st_size
    print(f"  packed {zip_path.name} ({size / 1024:.0f} KiB)")


def build_linux(optimize: str) -> Path:
    """Native Linux Release build → zig-out/bin/gl1"""
    run(["zig", "build", f"-Doptimize={optimize}"])
    exe = ZIG_OUT / "bin" / "gl1"
    if not exe.is_file():
        die(f"linux build missing {exe}")
    return exe


def build_windows(optimize: str) -> Path:
    """Cross-compile Windows from Linux → zig-out/windows/gl1-windows.exe"""
    run(["zig", "build", "windows", f"-Doptimize={optimize}"])
    exe = ZIG_OUT / "windows" / "gl1-windows.exe"
    if not exe.is_file():
        die(f"windows build missing {exe}")
    return exe


def build_macos(optimize: str, arch: str) -> Path | None:
    """Cross-compile macOS. Returns None if frameworks/SDK unavailable."""
    step = "macos-arm64" if arch == "arm64" else "macos-x64"
    name = "gl1-macos-arm64" if arch == "arm64" else "gl1-macos-x64"
    r = run(["zig", "build", step, f"-Doptimize={optimize}"], check=False)
    if r.returncode != 0:
        print(f"  warning: {step} build failed (need macOS SDK/frameworks on this host)")
        return None
    exe = ZIG_OUT / step / name
    if not exe.is_file():
        print(f"  warning: {step} produced no binary at {exe}")
        return None
    return exe


def package(
    *,
    platform_id: str,
    version: str,
    exe: Path,
    binary_name: str,
) -> Path:
    """
    Create dist/gl1-{version}-{platform_id}/ with binary + assets, then zip it.
    Returns path to the .zip.
    """
    folder_name = f"gl1-{version}-{platform_id}"
    staging = DIST / folder_name
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    dest_exe = staging / binary_name
    shutil.copy2(exe, dest_exe)
    dest_exe.chmod(dest_exe.stat().st_mode | 0o111)
    print(f"  binary → {dest_exe.relative_to(DIST)}")

    copy_assets(staging)

    # Small readme inside the package
    (staging / "README.txt").write_text(
        f"""gl1 {version} ({platform_id})

Run from this directory so relative assets/ paths resolve:

  Linux / macOS:  ./gl1
  Windows:        gl1.exe

Optional:
  gl1 --scene canvas
  gl1 --story-tab Button

Source: https://github.com/mikesmullin/gl1
""",
        encoding="utf-8",
    )

    zip_path = DIST / f"{folder_name}.zip"
    zip_dir(staging, zip_path)
    return zip_path


def gh_release(
    version: str,
    zips: list[Path],
    *,
    draft: bool,
    notes: str | None,
    title: str | None,
) -> None:
    tag = version if version.startswith("v") else f"v{version}"
    title = title or f"gl1 {tag}"

    # Prefer creating; if tag exists, upload only.
    list_r = subprocess.run(
        ["gh", "release", "view", tag],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    exists = list_r.returncode == 0

    if not exists:
        cmd = ["gh", "release", "create", tag, "--title", title]
        if draft:
            cmd.append("--draft")
        if notes:
            cmd.extend(["--notes", notes])
        else:
            cmd.extend(["--notes", f"Release {tag} of gl1.\n\nSee README for run instructions."])
        for z in zips:
            cmd.append(str(z))
        run(cmd)
    else:
        print(f"release {tag} already exists — uploading assets (clobber)")
        for z in zips:
            run(["gh", "release", "upload", tag, str(z), "--clobber"])


def main() -> None:
    ap = argparse.ArgumentParser(description="Build and publish gl1 release zips to GitHub")
    ap.add_argument(
        "--version",
        default=None,
        help="Release version (default: VERSION from src/main.zig)",
    )
    ap.add_argument(
        "--platforms",
        default="linux,windows,macos",
        help="Comma list: linux,windows,macos (default: all)",
    )
    ap.add_argument(
        "--optimize",
        default="ReleaseSafe",
        choices=["Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"],
        help="Zig optimize mode (default: ReleaseSafe)",
    )
    ap.add_argument(
        "--macos-arch",
        default="arm64",
        choices=["arm64", "x64", "both"],
        help="macOS arch when building macos (default: arm64)",
    )
    ap.add_argument("--skip-upload", action="store_true", help="Only build + zip into dist/")
    ap.add_argument("--draft", action="store_true", help="Create GitHub release as draft")
    ap.add_argument("--notes", default=None, help="Release notes body")
    ap.add_argument("--title", default=None, help="Release title")
    args = ap.parse_args()

    version = args.version or read_version_from_source()
    # strip leading v for folder names
    ver_clean = version[1:] if version.startswith("v") else version

    platforms = {p.strip().lower() for p in args.platforms.split(",") if p.strip()}
    valid = {"linux", "windows", "macos"}
    unknown = platforms - valid
    if unknown:
        die(f"unknown platforms: {', '.join(sorted(unknown))}")

    if not shutil.which("zig"):
        die("zig not found on PATH")
    if not args.skip_upload and not shutil.which("gh"):
        die("gh not found on PATH (or use --skip-upload)")

    DIST.mkdir(parents=True, exist_ok=True)
    zips: list[Path] = []

    print(f"== gl1 release {ver_clean} ==")
    print(f"   optimize={args.optimize}  platforms={','.join(sorted(platforms))}")
    print(f"   dist={DIST}")

    if "linux" in platforms:
        print("\n[linux]")
        if sys.platform != "linux":
            print("  warning: building linux binary on non-Linux host may fail")
        exe = build_linux(args.optimize)
        triple = host_linux_triple() if sys.platform == "linux" else "x86_64-linux"
        zips.append(
            package(
                platform_id=triple,
                version=ver_clean,
                exe=exe,
                binary_name="gl1",
            )
        )

    if "windows" in platforms:
        print("\n[windows]")
        exe = build_windows(args.optimize)
        zips.append(
            package(
                platform_id="x86_64-windows",
                version=ver_clean,
                exe=exe,
                binary_name="gl1.exe",
            )
        )

    if "macos" in platforms:
        arches = ["arm64", "x64"] if args.macos_arch == "both" else [args.macos_arch]
        for arch in arches:
            print(f"\n[macos {arch}]")
            exe = build_macos(args.optimize, arch)
            if exe is None:
                continue
            plat = "aarch64-macos" if arch == "arm64" else "x86_64-macos"
            zips.append(
                package(
                    platform_id=plat,
                    version=ver_clean,
                    exe=exe,
                    binary_name="gl1",
                )
            )

    if not zips:
        die("no packages produced")

    print("\n== packages ==")
    for z in zips:
        print(f"  {z}")

    if args.skip_upload:
        print("\n--skip-upload: not publishing to GitHub")
        return

    print("\n== upload ==")
    gh_release(ver_clean, zips, draft=args.draft, notes=args.notes, title=args.title)
    print(f"\nDone. https://github.com/mikesmullin/gl1/releases/tag/v{ver_clean}")


if __name__ == "__main__":
    main()
