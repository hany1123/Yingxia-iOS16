#!/bin/bash
# Build an unsigned iOS 16 IPA with Xcode 16 / iOS 18 SDK on the CI runner.
set -e

PROJECT_NAME="Yingxia16"
SCHEME="Yingxia16"
CONFIGURATION="Release"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
IPA_DIR="${BUILD_DIR}/ipa"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app"

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found"; exit 1; }

echo "==> xcodegen generate"
xcodegen generate

echo "==> clean"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> xcodebuild archive (unsigned)"
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM=""

if [ ! -d "${APP_PATH}" ]; then
  echo "!! archive did not produce ${APP_PATH}"
  exit 1
fi

echo "==> verify deployment target in built Info.plist"
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "${APP_PATH}/Info.plist"

echo "==> package IPA"
mkdir -p "${IPA_DIR}/Payload"
cp -R "${APP_PATH}" "${IPA_DIR}/Payload/"
cd "${IPA_DIR}"
zip -qr "${PROJECT_NAME}.ipa" Payload
cd -

echo "==> done"
ls -la "${IPA_DIR}/${PROJECT_NAME}.ipa"
