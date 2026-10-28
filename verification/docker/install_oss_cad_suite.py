#!/usr/bin/env python3
"""Download and unpack an OSS CAD Suite release from github.com/YosysHQ/oss-cad-suite-build.

Usage: install_oss_cad_suite.py <latest | YYYY-MM-DD | YYYYMMDD> <target directory>

Used by the Dockerfile, but works on any Linux machine (x64 or arm64). The suite ends up in
<target directory>/oss-cad-suite/; the installed release tag is written to its RELEASE file.
Standard library only, plus the 'tar' command.
"""

import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPOSITORY = "https://github.com/YosysHQ/oss-cad-suite-build"
# platform.machine() -> architecture name in the release asset names
ARCHITECTURES = {"x86_64": "x64", "amd64": "x64", "aarch64": "arm64", "arm64": "arm64"}
PROGRESS_STEP = 100 * 1024 * 1024   # Print the download progress every 100 MiB


def release_tag(version: str) -> str:
    """Return the release tag (YYYY-MM-DD) for 'latest' or a date given as YYYY-MM-DD or YYYYMMDD."""
    if version == "latest":
        # .../releases/latest redirects to .../releases/tag/<tag>. Following that redirect needs no
        # GitHub API call, so it isn't subject to the API's rate limit.
        request = urllib.request.Request(f"{REPOSITORY}/releases/latest", method="HEAD")
        with urllib.request.urlopen(request, timeout=60) as response:
            version = response.geturl().rstrip("/").rsplit("/", 1)[-1]
    if re.fullmatch(r"\d{8}", version):
        version = f"{version[:4]}-{version[4:6]}-{version[6:]}"
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", version):
        sys.exit(f"error: invalid OSS CAD Suite version '{version}', expected latest or YYYY-MM-DD")
    return version


def download(url: str, target) -> None:
    """Download 'url' into the open binary file 'target', printing the progress."""
    try:
        response = urllib.request.urlopen(url, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            sys.exit(f"error: {url} not found. Is the release date correct? See {REPOSITORY}/releases")
        raise
    with response:
        total = int(response.headers.get("Content-Length", 0))
        done, reported = 0, 0
        while chunk := response.read(1024 * 1024):
            target.write(chunk)
            done += len(chunk)
            if done - reported >= PROGRESS_STEP:
                reported = done
                print(f"  {done >> 20} MiB" + (f" of {total >> 20} MiB" if total else ""), flush=True)


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2])
    version, target = sys.argv[1], Path(sys.argv[2])
    machine = platform.machine().lower()
    if machine not in ARCHITECTURES:
        sys.exit(f"error: no OSS CAD Suite builds for the architecture '{machine}'")

    tag = release_tag(version)
    # Assets are named after the release date without dashes, e.g. oss-cad-suite-linux-x64-20261023.tgz
    asset = f"oss-cad-suite-linux-{ARCHITECTURES[machine]}-{tag.replace('-', '')}.tgz"
    url = f"{REPOSITORY}/releases/download/{tag}/{asset}"
    print(f"Installing OSS CAD Suite {tag} ({version}) from {url}", flush=True)

    target.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(target / "oss-cad-suite", ignore_errors=True)
    # Download to a temporary file next to the target, then unpack with tar (keeps the symlinks of
    # the archive as they are). The archive contains a single top-level 'oss-cad-suite' folder.
    with tempfile.NamedTemporaryFile(suffix=".tgz", dir=target) as archive:
        download(url, archive)
        archive.flush()
        print("Unpacking ...", flush=True)
        subprocess.run(["tar", "-xzf", archive.name, "-C", str(target)], check=True)

    suite = target / "oss-cad-suite"
    for tool in ("ghdl", "yosys"):
        if not (suite / "bin" / tool).is_file():
            sys.exit(f"error: {suite / 'bin' / tool} missing after unpacking {asset}")
    (suite / "RELEASE").write_text(f"{tag}\n")
    print(f"OSS CAD Suite {tag} installed in {suite}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
