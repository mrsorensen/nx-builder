#!/bin/bash
# Builds "NX Builder.app" into build/ (run it from /Applications, not from build/: the next build replaces it).
#   ./build.sh            build only
#   ./build.sh --install  also copy it to /Applications (NX Builder must not be running)
#   ./build.sh --release  also make build/NX-Builder-<version>.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

NAME="NX Builder"
APP="build/${NAME}.app"
VERSION="$(/bin/cat VERSION)"
MODE="${1:-}"

/bin/rm -rf "${APP}" build/AppIcon.iconset
/bin/mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" build

echo "Compiling ${NAME} ${VERSION} …"
/usr/bin/swiftc -O -swift-version 6 -parse-as-library \
  -target arm64-apple-macos15.0 \
  Sources/*.swift \
  -o "${APP}/Contents/MacOS/NXBuilder"

echo "Drawing the icon …"
/usr/bin/swiftc -O Tools/MakeIcon.swift -o build/makeicon
build/makeicon build/icon_1024.png
/bin/mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  /usr/bin/sips -z "$s" "$s" build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  /usr/bin/sips -z "$d" "$d" build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns build/AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns"
/bin/cp -R Localizations "${APP}/Contents/Resources/Localizations"

/bin/cat > "${APP}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>NXBuilder</string>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundleDisplayName</key><string>${NAME}</string>
  <key>CFBundleIdentifier</key><string>io.github.mrsorensen.nxbuilder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>nb</string><string>de</string><string>fr</string><string>es</string><string>pt-BR</string><string>ja</string><string>zh-Hans</string></array>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licence. Uses nxnative by seedds (MIT).</string>
</dict>
</plist>
EOF

/usr/bin/codesign --force --sign - "${APP}" >/dev/null 2>&1
echo "Built: ${APP}"

case "${MODE}" in
  --install)
    if /usr/bin/pgrep -f "/Applications/${NAME}.app/Contents/MacOS/NXBuilder" >/dev/null; then
      echo "${NAME} is running from /Applications: quit it first, then run ./build.sh --install again." >&2
      exit 1
    fi
    /bin/rm -rf "/Applications/${NAME}.app"
    /bin/cp -R "${APP}" /Applications/
    echo "Installed: /Applications/${NAME}.app"
    ;;
  --release)
    ZIP="build/NX-Builder-${VERSION}.zip"
    /bin/rm -f "${ZIP}"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
    echo "Release: ${ZIP}"
    /usr/bin/shasum -a 256 "${ZIP}"
    ;;
esac
