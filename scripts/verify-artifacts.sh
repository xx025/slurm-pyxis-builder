#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TARGET=
SLURM_VERSION=
PYXIS_VERSION=

while (($#)); do
    case "$1" in
        --target) TARGET=${2:?}; shift 2 ;;
        --slurm-version) SLURM_VERSION=${2:?}; shift 2 ;;
        --pyxis-version) PYXIS_VERSION=${2:?}; shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

if [[ -z "${TARGET}" || -z "${SLURM_VERSION}" || -z "${PYXIS_VERSION}" ]]; then
    printf 'target, Slurm version and Pyxis version are required\n' >&2
    exit 2
fi

declare -A OUTPUT_NAMES=(
    [ubuntu22]="ubuntu22.04"
    [ubuntu24]="ubuntu24.04"
    [debian12]="debian12"
    [debian13]="debian13"
)

if [[ -z "${OUTPUT_NAMES[${TARGET}]+defined}" ]]; then
    printf 'Unsupported target: %s\n' "${TARGET}" >&2
    exit 2
fi

directory="${PROJECT_DIR}/output/slurm-${SLURM_VERSION}_pyxis-${PYXIS_VERSION}/${OUTPUT_NAMES[${TARGET}]}"

(
    cd "${directory}"
    sha256sum --check SHA256SUMS
)

shopt -s nullglob
slurmd_packages=("${directory}"/slurm-smd-slurmd_*.deb)
shopt -u nullglob

if ((${#slurmd_packages[@]} != 1)); then
    printf 'Expected one slurmd package, found %d\n' \
        "${#slurmd_packages[@]}" >&2
    exit 1
fi

if [[ ! -s "${directory}/spank_pyxis.so" ]]; then
    printf 'Missing Pyxis plugin: %s/spank_pyxis.so\n' "${directory}" >&2
    exit 1
fi

file "${directory}/spank_pyxis.so" | grep -F 'shared object' >/dev/null
strings "${directory}/spank_pyxis.so" | \
    grep -F "pyxis: version v${PYXIS_VERSION}" >/dev/null

grep -F "slurm_version=${SLURM_VERSION}" \
    "${directory}/build-info.txt" >/dev/null
grep -F "pyxis_version=${PYXIS_VERSION}" \
    "${directory}/build-info.txt" >/dev/null

printf 'Artifact verification passed: %s\n' "${directory}"
