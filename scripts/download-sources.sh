#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_DIR="${PROJECT_DIR}/sources"
SLURM_VERSION=
PYXIS_VERSION=

usage() {
    cat <<'EOF'
Usage: scripts/download-sources.sh \
  --slurm-version VERSION \
  --pyxis-version VERSION
EOF
}

while (($#)); do
    case "$1" in
        --slurm-version)
            SLURM_VERSION=${2:?--slurm-version requires a value}
            shift 2
            ;;
        --pyxis-version)
            PYXIS_VERSION=${2:?--pyxis-version requires a value}
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "${SLURM_VERSION}" || -z "${PYXIS_VERSION}" ]]; then
    usage >&2
    exit 2
fi

version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([._+-][0-9A-Za-z.-]+)?$'
if [[ ! "${SLURM_VERSION}" =~ ${version_pattern} || \
      ! "${PYXIS_VERSION}" =~ ${version_pattern} ]]; then
    printf 'Invalid version value\n' >&2
    exit 2
fi

mkdir -p "${SOURCE_DIR}"

download() {
    local url=$1
    local destination=$2
    local partial="${destination}.part"

    if [[ -s "${destination}" ]]; then
        printf 'Using existing source: %s\n' "${destination}"
        return
    fi

    rm -f -- "${partial}"
    curl --fail --location --retry 3 --retry-delay 2 \
        --output "${partial}" "${url}"
    mv -- "${partial}" "${destination}"
}

slurm_archive="${SOURCE_DIR}/slurm-${SLURM_VERSION}.tar.bz2"
pyxis_archive="${SOURCE_DIR}/pyxis-${PYXIS_VERSION}.tar.gz"

download \
    "https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2" \
    "${slurm_archive}"
download \
    "https://github.com/NVIDIA/pyxis/archive/refs/tags/v${PYXIS_VERSION}.tar.gz" \
    "${pyxis_archive}"

tar -taf "${slurm_archive}" >/dev/null
tar -taf "${pyxis_archive}" >/dev/null

(
    cd "${SOURCE_DIR}"
    sha256sum \
        "$(basename -- "${slurm_archive}")" \
        "$(basename -- "${pyxis_archive}")" \
        > "SHA256SUMS.slurm-${SLURM_VERSION}_pyxis-${PYXIS_VERSION}"
)
