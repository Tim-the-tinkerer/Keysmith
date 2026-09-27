#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

LAUNCH=true
for arg in "$@"; do
    case "${arg}" in
        --no-launch) LAUNCH=false ;;
    esac
done

APP="Keysmith.app"
BUNDLE_ID="com.keysmith.passwords"

VERSION="$(sed -n '1p' VERSION | tr -d '[:space:]')"
BUILD="$(sed -n '2p' VERSION | tr -d '[:space:]')"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION file line 1 must be a semantic version (got '${VERSION}')" >&2
    exit 1
fi
if [[ ! "${BUILD}" =~ ^[0-9]+$ ]]; then
    echo "error: VERSION file line 2 must be a build number (got '${BUILD}')" >&2
    exit 1
fi

write_version_swift() {
    local tmp
    tmp="$(mktemp)"
    cat > "${tmp}" <<EOF
enum AppVersion {
    static let short = "${VERSION}"
    static let build = "${BUILD}"
}
EOF
    if ! cmp -s "${tmp}" Sources/Keysmith/Version.swift 2>/dev/null; then
        mv "${tmp}" Sources/Keysmith/Version.swift
    else
        rm -f "${tmp}"
    fi
}

stamp_plist() {
    local plist="$1"
    plutil -replace CFBundleShortVersionString -string "${VERSION}" "${plist}"
    plutil -replace CFBundleVersion -string "${BUILD}" "${plist}"
    plutil -replace CFBundleGetInfoString -string "Keysmith ${VERSION}" "${plist}"
}

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -f Assets/AppIcon.icns ]]; then
    echo "Generating app icon..."
    swift Scripts/GenerateAppIcon.swift
fi

write_version_swift

echo "Building Keysmith ${VERSION} (build ${BUILD}, release)..."
swift build -c release

BIN=".build/release/Keysmith"
if [[ ! -x "${BIN}" ]]; then
    echo "error: expected binary not found at ${BIN}" >&2
    exit 1
fi

echo "Running self-test..."
"${BIN}" --self-test

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/Keysmith"
chmod +x "${APP}/Contents/MacOS/Keysmith"
cp AppInfo.plist "${APP}/Contents/Info.plist"
stamp_plist "${APP}/Contents/Info.plist"

if [[ -f Assets/AppIcon.icns ]]; then
    cp Assets/AppIcon.icns "${APP}/Contents/Resources/"
fi

echo "Signing ${APP}..."
xattr -cr "${APP}" 2>/dev/null || true
codesign --force --sign - --identifier "${BUNDLE_ID}" --timestamp=none "${APP}/Contents/MacOS/Keysmith"
codesign --force --sign - --identifier "${BUNDLE_ID}" --timestamp=none "${APP}"

plutil -lint "${APP}/Contents/Info.plist" >/dev/null
codesign --verify --verbose=2 "${APP}" 2>/dev/null || codesign --verify "${APP}"

echo "Done: ${APP} (v${VERSION} build ${BUILD})"
if [[ "${LAUNCH}" == "true" ]]; then
    pkill -x Keysmith 2>/dev/null || true
    sleep 0.2
    echo "Launching..."
    open "${APP}"
fi
