#!/usr/bin/env bash
#
# Build an Emby Server .fpk for fnOS using the official fnpack toolchain.
#
# Usage:
#   scripts/build.sh [--arch x86|arm] [--version <emby-version>]
#
# The script downloads the upstream Emby .deb for the requested target
# architecture, assembles the official fnpack project under embyserver/,
# and packages it with `fnpack build`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${REPO_ROOT}/embyserver"
SRC_DIR="${REPO_ROOT}/src/app"
DIST_DIR="${REPO_ROOT}/dist"
WORK_DIR="${REPO_ROOT}/build"
FNPACK="${REPO_ROOT}/fnpack"

ARCH="x86"
VERSION=""

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --arch x86|arm        Target architecture (default: x86)
  --version <version>   Emby version (default: latest stable release)
  -h, --help            Show this help
EOF
}

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
*)
    echo "Unsupported arch: ${ARCH} (use x86 or arm)" >&2
    exit 2
    ;;
esac

for cmd in curl ar tar; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        echo "Missing required command: ${cmd}" >&2
        exit 1
    }
done

if [ ! -x "${FNPACK}" ]; then
    echo "fnpack not found at ${FNPACK}. Run scripts/fetch-fnpack.sh first." >&2
    exit 1
fi

if [ -z "${VERSION}" ]; then
    echo "==> Resolving latest Emby release ..."
    VERSION="$(curl -fsSL "https://api.github.com/repos/MediaBrowser/Emby.Releases/releases/latest" |
        sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -n "${VERSION}" ] || {
    echo "Could not resolve Emby version; pass --version" >&2
    exit 1
}

echo "==> Building Emby ${VERSION} (${ARCH}/${DEB_ARCH})"

mkdir -p "${WORK_DIR}"
DEB="${WORK_DIR}/emby-server-deb_${VERSION}_${DEB_ARCH}.deb"
if [ ! -f "${DEB}" ]; then
    URL="https://github.com/MediaBrowser/Emby.Releases/releases/download/${VERSION}/emby-server-deb_${VERSION}_${DEB_ARCH}.deb"
    echo "==> Downloading ${URL}"
    curl -fL --retry 3 -o "${DEB}.part" "${URL}"
    mv "${DEB}.part" "${DEB}"
fi

echo "==> Extracting .deb ..."
EXTRACT="${WORK_DIR}/extract"
rm -rf "${EXTRACT}"
mkdir -p "${EXTRACT}"
(
    cd "${WORK_DIR}"
    ar -x "$(basename "${DEB}")"
    tar -xf data.tar.xz -C "${EXTRACT}"
)

SRC_EMBY="${EXTRACT}/opt/emby-server"
[ -d "${SRC_EMBY}" ] || {
    echo "Unexpected deb layout: ${SRC_EMBY} not found" >&2
    exit 1
}

# 1. Assemble app/ from the upstream payload.
echo "==> Assembling embyserver/app ..."
rm -rf "${APP_DIR}/app"
mkdir -p "${APP_DIR}/app"
for d in bin etc extra lib licenses share system; do
    [ -e "${SRC_EMBY}/${d}" ] && cp -a "${SRC_EMBY}/${d}" "${APP_DIR}/app/"
done

# 2. Overlay fnOS-specific files (launcher, UI entry, icons).
#    This must happen after the upstream copy so our launcher wins over the
#    upstream bin/emby-server.
cp -a "${SRC_DIR}/." "${APP_DIR}/app/"

# 3. Pin version and platform in the manifest.
sed -i.tmp "s/^version.*/version               = ${VERSION}/" "${APP_DIR}/manifest"
sed -i.tmp "s/^platform.*/platform              = ${PLATFORM}/" "${APP_DIR}/manifest"
rm -f "${APP_DIR}/manifest.tmp"

# 4. Package with the official tool.
echo "==> Running fnpack build ..."
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}"/*.fpk
(cd "${DIST_DIR}" && "${FNPACK}" build --directory "${APP_DIR}")

FPK="$(ls "${DIST_DIR}"/*.fpk | head -1)"
echo "==> Built ${FPK} ($(du -h "${FPK}" | cut -f1))"
