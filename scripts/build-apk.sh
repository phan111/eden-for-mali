#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build the patched Eden Android APK locally.
#
# Requirements:
#   * JDK 17
#   * Android SDK with platforms;android-36, build-tools;36.0.0
#     and ndk;28.2.13676358
#   * CMake 3.31.6 reachable as $ANDROID_SDK_ROOT/cmake/3.31.6/bin/cmake
#     (Eden pins this exact version in src/android/app/build.gradle.kts)
#   * ANDROID_SDK_ROOT (or ANDROID_HOME) exported
#
# Usage: scripts/build-apk.sh [eden-src-dir]
#
# Environment:
#   PRESET      arm64 build preset, default armv9-x925 (Cortex-X925 / Armv9.2)
#   BUILD_TYPE  Release (default) or RelWithDebInfo
#   FLAVOR      standard (default), legacy or optimized

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDEN_SRC="${1:-${REPO_ROOT}/eden-src}"

PRESET="${PRESET:-armv9-x925}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
FLAVOR="${FLAVOR:-standard}"

: "${ANDROID_SDK_ROOT:=${ANDROID_HOME:-}}"
if [ -z "${ANDROID_SDK_ROOT}" ]; then
    echo "!! Export ANDROID_SDK_ROOT (or ANDROID_HOME) first." >&2
    exit 1
fi
export ANDROID_SDK_ROOT

if [ ! -d "${EDEN_SRC}" ]; then
    echo "!! ${EDEN_SRC} not found. Run scripts/prepare-source.sh first." >&2
    exit 1
fi

echo "-- Eden source : ${EDEN_SRC}"
echo "-- preset      : ${PRESET}"
echo "-- build type  : ${BUILD_TYPE}"
echo "-- flavor      : ${FLAVOR}"
echo

cd "${EDEN_SRC}"
chmod +x .ci/android/build.sh src/android/gradlew

CCACHE="${CCACHE:-true}" ./.ci/android/build.sh \
    -t "${FLAVOR}" \
    -b "${BUILD_TYPE}" \
    -DYUZU_BUILD_PRESET="${PRESET}"

echo
echo "-- APK / AAB in ${EDEN_SRC}/artifacts"
