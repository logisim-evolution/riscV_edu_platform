# Docker environment

A container with Python 3.14 and the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)
(GHDL, Yosys), for machines without a local installation and for CI.

## Use

```sh
verification/equiv.py --all --env docker                              # 'latest' release
verification/equiv.py --all --env docker --oss-cad-suite 2026-10-23   # pinned release (also 20261023)
export OSS_CAD_SUITE_VERSION=2026-10-23                               # default for --oss-cad-suite
verification/equiv.py --all --env docker --rebuild-image              # refresh the image
```

All other options work as without Docker. `--list` and `--check` don't need the tools and run on
the host without starting a container.

## What happens (`verification/equivlib/container.py`)

1. The image `riscv-edu-equiv:oss-cad-suite-<version>` is built from this folder if it doesn't
   exist (or with `--rebuild-image`, then with `--pull --no-cache`).
2. The runner is started once inside the container, with the same entry point (`equiv.py` or the
   module's `run.py`) and arguments, plus `--env native` to use the suite of the image:

   ```sh
   docker run --rm --init --env TINI_KILL_PROCESS_GROUP=1 --user <uid>:<gid> \
       --volume <repo>:<repo> --workdir <repo> <image> python3 verification/equiv.py <args> --env native
   ```

   - Same paths inside and outside: logs, VCDs and `results.csv` in `verification/build/` are
     identical to a local run, and file paths in them are valid on the host.
   - `--user`: the build artifacts belong to you, not to root.
   - `--init` + `TINI_KILL_PROCESS_GROUP`: Ctrl-C stops the runner and its GHDL/Yosys processes.
     No `--tty`, because docker only forwards signals without one.
3. The container's exit code is the runner's exit code.

## Versions

- `latest` is resolved **when the image is built** and then kept: the run prints the image's build
  date; use `--rebuild-image` to update it. For reproducible results (CI, sign-off) pin a date.
- Each version gets its own image; remove old ones with `docker image rm riscv-edu-equiv:oss-cad-suite-<version>`.
- Releases are listed at https://github.com/YosysHQ/oss-cad-suite-build/releases (one per day).
  Very old releases may no longer be available; the build then fails with a "not found" message.
- The OSS CAD Suite bundles Python 3.11, too old for the runner, so the image is based on
  `python:3.14-slim` (override with `--build-arg PYTHON_IMAGE=...` for a manual build).

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | `python:3.14-slim` + the suite in `/opt/oss-cad-suite`, `OSS_CAD_SUITE` set |
| `install_oss_cad_suite.py` | downloads and unpacks a release (`latest` via GitHub's redirect, no API rate limit); also usable outside Docker: `install_oss_cad_suite.py <version> <target dir>` |

Manual build and test, from the repository root:

```sh
docker build --build-arg OSS_CAD_SUITE_VERSION=2026-10-23 -t riscv-edu-equiv:oss-cad-suite-2026-10-23 verification/docker
docker run --rm riscv-edu-equiv:oss-cad-suite-2026-10-23            # prints the Yosys version
```

Needs about 3.5 GB of free disk space while building (download + unpacked suite).
