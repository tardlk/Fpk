#!/usr/bin/env bash
#
# Download the official fnpack tool for the current host.
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
    echo "Unsupported OS: ${OS}. Download fnpack manually from:" >&2
    echo "  https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-windows-amd64" >&2
    exit 1
    ;;
esac

URL="https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-${OS}-${ARCH}"
echo "==> Downloading ${URL}"
curl -fL --retry 3 -o "${DEST}.part" "${URL}"
mv "${DEST}.part" "${DEST}"
chmod +x "${DEST}"

"${DEST}" --help >/dev/null
echo "==> fnpack ${FNPACK_VERSION} installed at ${DEST}"
