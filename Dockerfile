ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGET_NAME=unknown
ARG SLURM_VERSION
ARG PYXIS_VERSION
ARG EXTRA_BUILD_PACKAGES=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN test -n "${SLURM_VERSION}" && \
    test -n "${PYXIS_VERSION}" && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        debhelper \
        devscripts \
        dpkg-dev \
        equivs \
        fakeroot \
        git \
        pkg-config \
        python3 && \
    if [[ -n "${EXTRA_BUILD_PACKAGES}" ]]; then \
        apt-get install -y --no-install-recommends ${EXTRA_BUILD_PACKAGES}; \
    fi && \
    rm -rf /var/lib/apt/lists/*

COPY sources/slurm-${SLURM_VERSION}.tar.bz2 /sources/
COPY sources/pyxis-${PYXIS_VERSION}.tar.gz /sources/

WORKDIR /build

# Slurm 23.11 and newer release tarballs contain the official Debian packaging.
RUN apt-get update && \
    tar -xaf "/sources/slurm-${SLURM_VERSION}.tar.bz2" && \
    cd "/build/slurm-${SLURM_VERSION}" && \
    mk-build-deps \
        -i \
        -r \
        -t "apt-get -y --no-install-recommends" \
        debian/control && \
    debuild -b -uc -us && \
    rm -rf /var/lib/apt/lists/*

# Install this build's Slurm headers and client into the same image. Pyxis is
# therefore compiled against the exact Slurm release shipped in the artifacts.
RUN apt-get update && \
    apt-get install -y \
        /build/slurm-smd_${SLURM_VERSION}-*.deb \
        /build/slurm-smd-client_${SLURM_VERSION}-*.deb \
        /build/slurm-smd-dev_${SLURM_VERSION}-*.deb && \
    dpkg-query -W -f='${Package} ${Version}\n' \
        slurm-smd slurm-smd-client slurm-smd-dev && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /build/pyxis && \
    tar -xaf "/sources/pyxis-${PYXIS_VERSION}.tar.gz" \
        --strip-components=1 \
        -C /build/pyxis

WORKDIR /build/pyxis

RUN make PYXIS_VER="${PYXIS_VERSION}"

RUN mkdir -p /artifacts && \
    cp /build/slurm-smd*.deb /artifacts/ && \
    cp /build/pyxis/spank_pyxis.so /artifacts/ && \
    { \
        printf 'target=%s\n' "${TARGET_NAME}"; \
        printf 'base_image_os_release_begin\n'; \
        cat /etc/os-release; \
        printf 'base_image_os_release_end\n'; \
        printf 'slurm_version=%s\n' "${SLURM_VERSION}"; \
        printf 'pyxis_version=%s\n' "${PYXIS_VERSION}"; \
        printf 'architecture=%s\n' "$(dpkg --print-architecture)"; \
        printf 'built_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
    } > /artifacts/build-info.txt && \
    cd /artifacts && \
    for package in ./*.deb; do \
        dpkg-deb -f "${package}" Package Version Architecture; \
    done > packages.txt && \
    sha256sum ./*.deb ./spank_pyxis.so > SHA256SUMS

FROM scratch AS artifacts
COPY --from=builder /artifacts/ /
