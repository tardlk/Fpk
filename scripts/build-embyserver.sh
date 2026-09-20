#!/usr/bin/env bash
#
# Build an Emby Server .fpk for fnOS using the official fnpack toolchain.
#
# Usage:
#   scripts/build.sh [--arch x86|arm] [--version <emby-version>]
#
# The script downloads the upstream Emby .deb for the requested target
# architecture (verifying its SHA-256 against the GitHub release metadata),
# assembles the official fnpack project under embyserver/, and packages it
# with `fnpack build`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${REPO_ROOT}/embyserver"
SRC_DIR="${REPO_ROOT}/src/embyserver/app"
DIST_DIR="${REPO_ROOT}/dist"
WORK_DIR="${REPO_ROOT}/build"
FNPACK="${REPO_ROOT}/fnpack"
RELEASES_API="${EMBY_RELEASES_API:-https://api.github.com/repos/MediaBrowser/Emby.Releases/releases}"

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
  --version <version>   Emby version (default: latest stable release)
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
    DEB_ARCH="amd64"
    PLATFORM="x86"
    ;;
arm)
    DEB_ARCH="arm64"
    PLATFORM="arm"
    ;;
*) error "Unsupported arch: ${ARCH} (use x86 or arm)" ;;
esac

for cmd in curl ar tar; do
    command -v "${cmd}" >/dev/null 2>&1 || error "Missing required command: ${cmd}"
done
[ -x "${FNPACK}" ] || error "fnpack not found at ${FNPACK}. Run scripts/fetch-fnpack.sh first."

# Use GITHUB_TOKEN/GH_TOKEN when available to avoid anonymous API rate limits.
AUTH_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
elif [ -n "${GH_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

if [ -z "${VERSION}" ]; then
    info "Resolving latest Emby release ..."
    VERSION="$(curl -fsSL --retry 3 --retry-delay 2 ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
        -H "Accept: application/vnd.github+json" "${RELEASES_API}/latest" |
        sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -n "${VERSION}" ] || error "Could not resolve Emby version; pass --version"

info "Building Emby ${VERSION} (${ARCH}/${DEB_ARCH})"

ASSET="emby-server-deb_${VERSION}_${DEB_ARCH}.deb"
mkdir -p "${WORK_DIR}"
DEB="${WORK_DIR}/${ASSET}"

# Resolve the upstream SHA-256 from the release metadata.
EXPECTED_SHA=""
if command -v python3 >/dev/null 2>&1; then
    if RELEASE_JSON="$(curl -fsSL --retry 3 --retry-delay 2 ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
        -H "Accept: application/vnd.github+json" "${RELEASES_API}/tags/${VERSION}" 2>/dev/null)"; then
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
' "${ASSET}" || true)"
    else
        warn "Could not fetch release metadata for ${VERSION}; skipping digest lookup"
    fi
fi

if [ ! -f "${DEB}" ]; then
    URL="https://github.com/MediaBrowser/Emby.Releases/releases/download/${VERSION}/${ASSET}"
    info "Downloading ${URL}"
    curl -fL --retry 3 -o "${DEB}.part" "${URL}"
    mv "${DEB}.part" "${DEB}"
fi

# Verify the downloaded artifact.
if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA="$(sha256sum "${DEB}" | cut -d' ' -f1)"
    if [ -n "${EXPECTED_SHA}" ]; then
        [ "${ACTUAL_SHA}" = "${EXPECTED_SHA}" ] ||
            error "sha256 mismatch for ${ASSET}: expected ${EXPECTED_SHA}, got ${ACTUAL_SHA}"
        info "Verified sha256 ${ACTUAL_SHA}"
    else
        warn "No upstream digest available; ${ASSET} sha256=${ACTUAL_SHA}"
    fi
fi

info "Extracting .deb ..."
EXTRACT="${WORK_DIR}/extract"
rm -rf "${EXTRACT}"
mkdir -p "${EXTRACT}"
(
    cd "${WORK_DIR}"
    ar -x "${ASSET}"
    tar -xf data.tar.xz -C "${EXTRACT}"
)

SRC_EMBY="${EXTRACT}/opt/emby-server"
[ -d "${SRC_EMBY}" ] || error "Unexpected deb layout: ${SRC_EMBY} not found"

# 1. Assemble app/ from the upstream payload.
info "Assembling embyserver/app ..."
rm -rf "${APP_DIR}/app"
mkdir -p "${APP_DIR}/app"
for d in bin etc extra lib licenses share system; do
    if [ -e "${SRC_EMBY}/${d}" ]; then
        cp -a "${SRC_EMBY}/${d}" "${APP_DIR}/app/"
    fi
done

# 2. Overlay fnOS-specific files (launcher, UI entry, icons). This must happen
#    after the upstream copy so our launcher wins over bin/emby-server.
cp -a "${SRC_DIR}/." "${APP_DIR}/app/"

# 3. Ensure scripts stay executable even if the checkout lost their mode.
chmod +x "${APP_DIR}"/cmd/* 2>/dev/null || true
chmod +x "${APP_DIR}/app/bin/emby-server" 2>/dev/null || true

# 4. Pin version and platform in the manifest.
sed -i.tmp "s/^version.*/version               = ${VERSION}/" "${APP_DIR}/manifest"
sed -i.tmp "s/^platform.*/platform              = ${PLATFORM}/" "${APP_DIR}/manifest"
rm -f "${APP_DIR}/manifest.tmp"

# 5. Package with the official tool.
info "Running fnpack build ..."
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}"/*.fpk
(cd "${DIST_DIR}" && "${FNPACK}" build --directory "${APP_DIR}")

FPK="$(ls "${DIST_DIR}"/*.fpk | head -1)"
info "Built ${FPK} ($(du -h "${FPK}" | cut -f1))"
