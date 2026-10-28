# Container environment for the equivalence checks: Python 3.14 + the OSS CAD Suite (GHDL, Yosys).
#
# Normally built and used automatically:   verification/equiv.py --all --env docker [--oss-cad-suite VERSION]
# Manual build (from the repository root):
#   docker build --build-arg OSS_CAD_SUITE_VERSION=2026-10-23 \
#                -t riscv-edu-equiv:oss-cad-suite-2026-10-23 verification/docker
#
# The OSS CAD Suite brings its own Python 3.11, which is too old for the runner (3.14 or newer),
# hence the official Python image as base. See README.md in this folder.

ARG PYTHON_IMAGE=python:3.14-slim
FROM ${PYTHON_IMAGE}

# 'latest' or a release date (YYYY-MM-DD) of https://github.com/YosysHQ/oss-cad-suite-build/releases
ARG OSS_CAD_SUITE_VERSION=latest

# Download and unpack in one layer; the archive is deleted again before the layer is stored
COPY install_oss_cad_suite.py /usr/local/bin/install_oss_cad_suite.py
RUN python3 /usr/local/bin/install_oss_cad_suite.py "${OSS_CAD_SUITE_VERSION}" /opt

# OSS_CAD_SUITE is where the runner's 'native' environment looks for the suite. The suite's bin/ is
# appended to PATH (not prepended) only for interactive use, so the image's Python 3.14 stays first.
ENV OSS_CAD_SUITE=/opt/oss-cad-suite \
    PATH=${PATH}:/opt/oss-cad-suite/bin \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

LABEL org.opencontainers.image.title="riscv-edu-platform equivalence checks" \
      org.opencontainers.image.description="Python 3.14 and the OSS CAD Suite (GHDL, Yosys) for verification/equiv.py" \
      riscv-edu.oss-cad-suite-version="${OSS_CAD_SUITE_VERSION}"

WORKDIR /work
CMD ["yosys", "-V"]
