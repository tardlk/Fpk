#!/usr/bin/env bash
#
# Build a qBittorrent .fpk for fnOS using the official fnpack toolchain.
#
# Usage:
#   scripts/build-qbittorrent.sh [--arch x86|arm] [--version <version>]
#
# Downloads the official qbittorrent-nox-static binary for the requested target
# architecture (verifying its SHA-256 against the GitHub release metadata),
# assembles the official fnpack project under qbittorrent/, and packages it
# with `fnpack build`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${REPO_ROOT}/qbittorrent"
SRC_DIR="${REPO_ROOT}/src/qbittorrent/app"
DIST_DIR="${REPO_ROOT}/dist"
WORK_DIR="${REPO_ROOT}/build"
FNPACK="${REPO_ROOT}/fnpack"
UPSTREAM_REPO="userdocs/qbittorrent-nox-static"
RELEASES_API="${QBIT_RELEASES_API:-https://api.github.com/repos/${UPSTREAM_REPO}/releases}"

info() { echo "==> $1"; }
warn() { echo "WARNING: $1" >&2; }
error() {
    echo "ERROR: $1" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --arch x86|arm        Target architecture (default: x86)
  --version <version>   qBittorrent version, e.g. 5.2.3 (default: latest)
  -h, --help            Show this help
EOF
}

ARCH="x86"
VERSION=""

while [ "$#" -gt 0 ]; do
    case "$1" in
    --arch)
        ARCH="$2"
        shift 2
        ;;
    --arch=*)
        ARCH="${1#*=}"
        shift
        ;;
    --version)
        VERSION="$2"
        shift 2
        ;;
    --version=*)
        VERSION="${1#*=}"
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
done

case "${ARCH}" in
x86)
    ASSET_ARCH="x86_64"
    PLATFORM="x86"
    ;;
arm)
    ASSET_ARCH="aarch64"
    PLATFORM="arm"
    ;;
*) error "Unsupported arch: ${ARCH} (use x86 or arm)" ;;
esac

for cmd in curl tar; do
    command -v "${cmd}" >/dev/null 2>&1 || error "Missing required command: ${cmd}"
done
[ -x "${FNPACK}" ] || error "fnpack not found at ${FNPACK}. Run scripts/fetch-fnpack.sh first."

AUTH_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
elif [ -n "${GH_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

api_get() {
    curl -fsSL --retry 3 --retry-delay 2 ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
        -H "Accept: application/vnd.github+json" "$1"
}

# Resolve the upstream release tag.
if [ -z "${VERSION}" ]; then
    info "Resolving latest qbittorrent-nox-static release ..."
    RELEASE_JSON="$(api_get "${RELEASES_API}/latest")"
    TAG="$(printf '%s' "${RELEASE_JSON}" |
        sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
else
    info "Looking up qbittorrent-nox-static release for ${VERSION} ..."
    TAG="$(api_get "${RELEASES_API}?per_page=100" | python3 -c '
import json, sys
version = sys.argv[1]
data = json.load(sys.stdin)
if isinstance(data, dict):
    data = [data]
for r in data:
    tag = r.get("tag_name", "")
    if tag in ("release-" + version, "release-" + version + "_v") or tag.startswith("release-" + version + "_v"):
        print(tag)
        break
' "${VERSION}")"
    [ -n "${TAG}" ] || error "No release found for qBittorrent ${VERSION}"
    RELEASE_JSON="$(api_get "${RELEASES_API}/tags/${TAG}")"
fi
[ -n "${TAG}" ] || error "Could not resolve qbittorrent-nox-static tag"

# 5.2.3_v2.0.14 -> 5.2.3
QBT_VERSION="${VERSION:-$(printf '%s' "${TAG}" | sed -E 's/^release-//; s/_v[0-9].*$//')}"
[ -n "${QBT_VERSION}" ] || error "Could not determine qBittorrent version"

ASSET="${ASSET_ARCH}-qbittorrent-nox"
info "Building qBittorrent ${QBT_VERSION} (${ARCH}/${ASSET_ARCH}), tag ${TAG}"

EXPECTED_SHA="$(printf '%s' "${RELEASE_JSON}" | python3 -c '
import json, sys
asset = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in data.get("assets", []):
    if a.get("name") == asset:
        digest = a.get("digest") or ""
        print(digest.split("sha256:")[-1] if digest else "")
        break
' "${ASSET}")"

mkdir -p "${WORK_DIR}"
BIN="${WORK_DIR}/${ASSET}"
if [ ! -f "${BIN}" ]; then
    URL="https://github.com/${UPSTREAM_REPO}/releases/download/${TAG}/${ASSET}"
    info "Downloading ${URL}"
    curl -fL --retry 3 -o "${BIN}.part" "${URL}"
    mv "${BIN}.part" "${BIN}"
fi

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA="$(sha256sum "${BIN}" | cut -d' ' -f1)"
else
    ACTUAL_SHA="$(shasum -a 256 "${BIN}" | cut -d' ' -f1)"
fi
if [ -n "${EXPECTED_SHA}" ]; then
    [ "${ACTUAL_SHA}" = "${EXPECTED_SHA}" ] ||
        error "sha256 mismatch for ${ASSET}: expected ${EXPECTED_SHA}, got ${ACTUAL_SHA}"
    info "Verified sha256 ${ACTUAL_SHA}"
else
    warn "No upstream digest available; ${ASSET} sha256=${ACTUAL_SHA}"
fi

# Assemble the official fnpack project.
info "Assembling qbittorrent/app ..."
rm -rf "${APP_DIR}/app"
mkdir -p "${APP_DIR}/app/bin"
cp "${BIN}" "${APP_DIR}/app/bin/qbittorrent-nox"
chmod +x "${APP_DIR}/app/bin/qbittorrent-nox"

# Overlay fnOS-specific files (default config template, desktop entry, icons).
cp -a "${SRC_DIR}/." "${APP_DIR}/app/"

# Defensive exec bits (in case the checkout lost them).
chmod +x "${APP_DIR}"/cmd/* 2>/dev/null || true

# Pin version and platform in the manifest.
sed -i.tmp "s/^version.*/version               = ${QBT_VERSION}/" "${APP_DIR}/manifest"
sed -i.tmp "s/^platform.*/platform              = ${PLATFORM}/" "${APP_DIR}/manifest"
rm -f "${APP_DIR}/manifest.tmp"

info "Running fnpack build ..."
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}"/qbittorrent*.fpk
(cd "${DIST_DIR}" && "${FNPACK}" build --directory "${APP_DIR}")

FPK="$(ls "${DIST_DIR}"/qbittorrent.fpk | head -1)"
info "Built ${FPK} ($(du -h "${FPK}" | cut -f1))"
