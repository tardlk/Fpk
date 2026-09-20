#!/usr/bin/env bash
#
# Structural / contract verification for a built Emby .fpk.
#
# Checks (no fnOS device required):
#   - the .fpk is a valid gzip tar
#   - required top-level entries exist
#   - manifest fields are present and platform matches the expected one
#   - manifest.checksum equals md5(app.tgz)
#   - cmd/* and app/ui are executable / valid JSON
#   - every ELF binary in app.tgz matches the target architecture
#
# Usage: scripts/verify-fpk.sh <fpk-path> <x86|arm> [required-payload-path ...]
#
# Extra arguments are payload paths (relative to app.tgz) that must exist,
# e.g. bin/emby-server or bin/qbittorrent-nox.

set -euo pipefail

FPK="${1:-}"
PLATFORM="${2:-}"

if [ -z "${FPK}" ] || [ -z "${PLATFORM}" ]; then
    echo "Usage: $0 <fpk-path> <x86|arm> [required-payload-path ...]" >&2
    exit 2
fi

shift 2
PAYLOAD_REQUIRED=(ui/config ui/images/icon_64.png ui/images/icon_256.png)
PAYLOAD_EXEC=("$@")
[ -f "${FPK}" ] || {
    echo "fpk not found: ${FPK}" >&2
    exit 1
}

case "${PLATFORM}" in
x86) EXPECTED_ELF="x86-64" ;;
arm) EXPECTED_ELF="aarch64" ;;
*)
    echo "Unsupported platform: ${PLATFORM}" >&2
    exit 2
    ;;
esac

FAIL=0
pass() { echo "  [ OK ] $1"; }
fail() {
    echo "  [FAIL] $1"
    FAIL=1
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

manifest_get() {
    sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "${WORK}/manifest" | head -1 | tr -d ' '
}

json_ok() {
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null
}

# 1. gzip tar
if tar -tzf "${FPK}" >/dev/null 2>&1; then
    pass "fpk is a valid tar.gz"
else
    fail "fpk is not a valid tar.gz"
    echo "FAILED"
    exit 1
fi

# 2. required entries
REQUIRED=(
    manifest
    app.tgz
    cmd/main
    cmd/install_init
    cmd/install_callback
    cmd/uninstall_init
    cmd/uninstall_callback
    cmd/upgrade_init
    cmd/upgrade_callback
    config/privilege
    config/resource
    ICON.PNG
    ICON_256.PNG
)
LISTING="$(tar -tzf "${FPK}")"
MISSING=()
for entry in "${REQUIRED[@]}"; do
    grep -qxF "${entry}" <<<"${LISTING}" || MISSING+=("${entry}")
done
if [ "${#MISSING[@]}" -eq 0 ]; then
    pass "all required entries present"
else
    fail "missing entries: ${MISSING[*]}"
fi

# 3. extract
if tar -xzf "${FPK}" -C "${WORK}" 2>/dev/null; then
    pass "fpk extracts cleanly"
else
    fail "fpk extraction failed"
    echo "FAILED"
    exit 1
fi

# 4. manifest fields + platform
APPNAME="$(manifest_get appname)"
VERSION="$(manifest_get version)"
PLATFORM_FIELD="$(manifest_get platform)"
if [ -n "${APPNAME}" ] && [ -n "${VERSION}" ] && [ -n "${PLATFORM_FIELD}" ]; then
    pass "manifest fields present (appname=${APPNAME} version=${VERSION})"
else
    fail "manifest is missing required fields"
fi
if [ "${PLATFORM_FIELD}" = "${PLATFORM}" ]; then
    pass "manifest.platform=${PLATFORM} matches target"
else
    fail "manifest.platform='${PLATFORM_FIELD}' but target is '${PLATFORM}'"
fi

# 5. checksum
DECLARED="$(manifest_get checksum)"
COMPUTED="$(md5sum "${WORK}/app.tgz" | cut -d' ' -f1)"
if [ -n "${DECLARED}" ] && [ "${DECLARED}" = "${COMPUTED}" ]; then
    pass "manifest.checksum matches md5(app.tgz)"
else
    fail "checksum mismatch: declared='${DECLARED}' computed='${COMPUTED}'"
fi

# 6. executable lifecycle scripts
for script in cmd/main cmd/install_init cmd/uninstall_init; do
    if [ -x "${WORK}/${script}" ]; then
        pass "${script} is executable"
    else
        fail "${script} is not executable"
    fi
done

# 7. JSON validity (fpk level)
for json in config/privilege config/resource; do
    if json_ok "${WORK}/${json}"; then
        pass "${json} is valid JSON"
    else
        fail "${json} is not valid JSON"
    fi
done

# 8. app.tgz payload
if tar -xzf "${WORK}/app.tgz" -C "${WORK}" 2>/dev/null; then
    pass "app.tgz extracts cleanly"
else
    fail "app.tgz extraction failed"
fi

for entry in "${PAYLOAD_REQUIRED[@]}"; do
    if [ -e "${WORK}/${entry}" ]; then
        pass "payload contains ${entry}"
    else
        fail "payload is missing ${entry}"
    fi
done
for entry in ${PAYLOAD_EXEC[@]+"${PAYLOAD_EXEC[@]}"}; do
    if [ -x "${WORK}/${entry}" ]; then
        pass "payload contains executable ${entry}"
    else
        fail "payload is missing executable ${entry}"
    fi
done
if json_ok "${WORK}/ui/config"; then
    pass "ui/config is valid JSON"
else
    fail "ui/config is not valid JSON"
fi

# 9. ELF architecture (scan only binary-bearing directories)
ELF_DIRS=()
for d in system lib bin extra; do
    [ -d "${WORK}/${d}" ] && ELF_DIRS+=("${WORK}/${d}")
done
ELF_LIST=""
if [ "${#ELF_DIRS[@]}" -gt 0 ]; then
    ELF_LIST="$(find "${ELF_DIRS[@]}" -type f -exec file -b {} + 2>/dev/null | grep '^ELF ' || true)"
fi
if [ -z "${ELF_LIST}" ]; then
    fail "no ELF binary found in app.tgz"
else
    WRONG="$(echo "${ELF_LIST}" | grep -v "${EXPECTED_ELF}" || true)"
    if [ -z "${WRONG}" ]; then
        pass "all ELF binaries match '${EXPECTED_ELF}' ($(echo "${ELF_LIST}" | wc -l) checked)"
    else
        fail "ELF binaries with unexpected arch (want ${EXPECTED_ELF}):"
        echo "${WRONG}" | head -5 | sed 's/^/         /'
    fi
fi

echo
if [ "${FAIL}" -eq 0 ]; then
    echo "PASS: ${FPK} (${PLATFORM})"
else
    echo "FAIL: ${FPK} (${PLATFORM})"
fi
exit "${FAIL}"
