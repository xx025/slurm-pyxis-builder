#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PLATFORM=${PLATFORM:-linux/amd64}
EXTRA_BUILD_PACKAGES=${EXTRA_BUILD_PACKAGES:-}

declare -A BASE_IMAGES=(
    [ubuntu22]="ubuntu:22.04"
    [ubuntu24]="ubuntu:24.04"
    [debian12]="debian:12"
    [debian13]="debian:13"
)

declare -A OUTPUT_NAMES=(
    [ubuntu22]="ubuntu22.04"
    [ubuntu24]="ubuntu24.04"
    [debian12]="debian12"
    [debian13]="debian13"
)

TARGET=
SLURM_VERSION=26.05.4
PYXIS_VERSION=0.24.0

usage() {
    cat <<'EOF'
Usage: scripts/build.sh \
  --target ubuntu22|ubuntu24|debian12|debian13|all \
  [--slurm-version VERSION] \
  [--pyxis-version VERSION]

Defaults:
  Slurm 26.05.4
  Pyxis 0.24.0
EOF
}

while (($#)); do
    case "$1" in
        --target)
            TARGET=${2:?--target requires a value}
            shift 2
            ;;
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

if [[ -z "${TARGET}" ]]; then
    usage >&2
    exit 2
fi

version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([._+-][0-9A-Za-z.-]+)?$'
if [[ ! "${SLURM_VERSION}" =~ ${version_pattern} ]]; then
    printf 'Invalid Slurm version: %s\n' "${SLURM_VERSION}" >&2
    exit 2
fi
if [[ ! "${PYXIS_VERSION}" =~ ${version_pattern} ]]; then
    printf 'Invalid Pyxis version: %s\n' "${PYXIS_VERSION}" >&2
    exit 2
fi

if [[ "${TARGET}" == all ]]; then
    targets=(ubuntu22 ubuntu24 debian12 debian13)
elif [[ -n "${BASE_IMAGES[${TARGET}]+defined}" ]]; then
    targets=("${TARGET}")
else
    printf 'Unsupported target: %s\n' "${TARGET}" >&2
    exit 2
fi

command -v docker >/dev/null || {
    printf 'docker was not found in PATH\n' >&2
    exit 1
}

missing_source=0
for archive in \
    "${PROJECT_DIR}/sources/slurm-${SLURM_VERSION}.tar.bz2" \
    "${PROJECT_DIR}/sources/pyxis-${PYXIS_VERSION}.tar.gz"; do
    if [[ ! -s "${archive}" ]]; then
        missing_source=1
    fi
done

if ((missing_source)); then
    "${PROJECT_DIR}/scripts/download-sources.sh" \
        --slurm-version "${SLURM_VERSION}" \
        --pyxis-version "${PYXIS_VERSION}"
fi

output_root="${PROJECT_DIR}/output/slurm-${SLURM_VERSION}_pyxis-${PYXIS_VERSION}"
mkdir -p "${output_root}"

for target in "${targets[@]}"; do
    destination="${output_root}/${OUTPUT_NAMES[${target}]}"

    if [[ -e "${destination}" ]]; then
        backup="${destination}.backup.$(date +%Y%m%d%H%M%S)"
        mv -- "${destination}" "${backup}"
        printf 'Existing output preserved at %s\n' "${backup}"
    fi

    temporary=$(mktemp -d "${output_root}/.${target}.XXXXXX")
    printf 'Building %s with %s\n' "${target}" "${BASE_IMAGES[${target}]}"

    if ! DOCKER_BUILDKIT=1 docker build \
        --progress=plain \
        --platform "${PLATFORM}" \
        --build-arg "BASE_IMAGE=${BASE_IMAGES[${target}]}" \
        --build-arg "TARGET_NAME=${target}" \
        --build-arg "SLURM_VERSION=${SLURM_VERSION}" \
        --build-arg "PYXIS_VERSION=${PYXIS_VERSION}" \
        --build-arg "EXTRA_BUILD_PACKAGES=${EXTRA_BUILD_PACKAGES}" \
        --output "type=local,dest=${temporary}" \
        "${PROJECT_DIR}"; then
        rm -rf -- "${temporary}"
        printf 'Build failed for %s\n' "${target}" >&2
        exit 1
    fi

    mv -- "${temporary}" "${destination}"
    "${PROJECT_DIR}/scripts/verify-artifacts.sh" \
        --target "${target}" \
        --slurm-version "${SLURM_VERSION}" \
        --pyxis-version "${PYXIS_VERSION}"
    printf 'Artifacts written to %s\n' "${destination}"
done
