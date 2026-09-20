#!/usr/bin/env bash
#
# Download the official fnpack tool for the current host and verify it
# against the known SHA-256 for release 1.2.3.
# See https://developer.fnnas.com/docs/cli/fnpack/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FNPACK_VERSION="${FNPACK_VERSION:-1.2.3}"
DEST="${REPO_ROOT}/fnpack"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
MACHINE="$(uname -m)"

case "${MACHINE}" in
x86_64 | amd64) ARCH="amd64" ;;
aarch64 | arm64) ARCH="arm64" ;;
*)
    echo "Unsupported architecture: ${MACHINE}" >&2
    exit 1
    ;;
esac

case "${OS}" in
linux | darwin) ;;
*)
    echo "Unsupported OS: ${OS}. Download fnpack manually:" >&2
    echo "  https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-windows-amd64" >&2
    exit 1
    ;;
esac

# Known SHA-256 hashes for fnpack 1.2.3. The linux-arm64 build is not published
# by fnOS at the moment (the documented URL returns 404), so it is unavailable.
EXPECTED_SHA=""
if [ "${FNPACK_VERSION}" = "1.2.3" ]; then
    case "${OS}-${ARCH}" in
    linux-amd64) EXPECTED_SHA="54b97fa7b70968c4d05c79840f5daeff508957d0bb2062fdb0376d00d9615c93" ;;
    darwin-amd64) EXPECTED_SHA="30a9f50a35e8d8d425b687881761478c3c778e9c0da3a1b59f298b666dd7a268" ;;
    darwin-arm64) EXPECTED_SHA="d40cb00896cb2a5d211357d255750ed0cbe7f2d141df671c2b717afb4e74bf77" ;;
    linux-arm64)
        echo "fnpack ${FNPACK_VERSION} for linux-arm64 is not published by fnOS." >&2
        echo "Set FNPACK_SHA256 and fetch a trusted binary manually, or run on an amd64 host." >&2
        exit 1
        ;;
    esac
fi

# Allow an explicit override for other versions / mirrors.
if [ -n "${FNPACK_SHA256:-}" ]; then
    EXPECTED_SHA="${FNPACK_SHA256}"
fi

URL="https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-${OS}-${ARCH}"
echo "==> Downloading ${URL}"
curl -fL --retry 3 -o "${DEST}.part" "${URL}"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA="$(sha256sum "${DEST}.part" | cut -d' ' -f1)"
else
    ACTUAL_SHA="$(shasum -a 256 "${DEST}.part" | cut -d' ' -f1)"
fi

if [ -n "${EXPECTED_SHA}" ]; then
    if [ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]; then
        rm -f "${DEST}.part"
        echo "ERROR: sha256 mismatch for fnpack ${FNPACK_VERSION}-${OS}-${ARCH}" >&2
        echo "  expected ${EXPECTED_SHA}" >&2
        echo "  got      ${ACTUAL_SHA}" >&2
        exit 1
    fi
    echo "==> Verified sha256 ${ACTUAL_SHA}"
else
    echo "==> WARNING: no pinned hash for ${FNPACK_VERSION}-${OS}-${ARCH}; got ${ACTUAL_SHA}" >&2
fi

mv "${DEST}.part" "${DEST}"
chmod +x "${DEST}"

"${DEST}" --help >/dev/null
echo "==> fnpack ${FNPACK_VERSION} installed at ${DEST}"
