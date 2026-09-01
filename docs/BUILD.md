# Build notes

## Which preset to build

`YUZU_BUILD_PRESET` selects the arm64 compiler target.

| Preset | `-march` / `-mtune` | Runs on |
| --- | --- | --- |
| `armv9-x925` | `armv9-a`, `-mtune=cortex-x925` | **Armv9 devices only.** The Tab S11 target. |
| `armv9` | `armv9-a`, generic tuning | Armv9 devices only. |
| `optimized` | `armv8.2-a+lse+rcpc` | Most 64-bit Android devices from ~2017 on. |
| `generic` | `armv8-a` | Widest compatibility. |
| `custom` (default) | no flags added | Upstream default. |

`armv9-x925` raises the **ISA baseline**, so the resulting APK will not run on
pre-Armv9 hardware — installing it on an older device gives a crash on launch,
not a graceful fallback. The `-mtune` half is safe regardless: it changes only
instruction scheduling, never which instructions are emitted, so tuning for the
prime core stays correct on the cluster's smaller cores.

If your toolchain does not know `cortex-x925`, the CMake check downgrades to
generic tuning and prints a status line; the build still succeeds.

## Building in CI

Actions → *Build Eden APK (Mali / Galaxy Tab S11)* → *Run workflow*, then pick a
preset, build type and flavor. The workflow:

1. reclaims runner disk space (a full Eden native build is large),
2. installs JDK 17, plus `platforms;android-36`, `build-tools;36.0.0` and
   `ndk;28.2.13676358` — the NDK version Eden pins,
3. installs **CMake 3.31.6** into `$ANDROID_SDK_ROOT/cmake/3.31.6`, because
   `src/android/app/build.gradle.kts` pins that exact version via
   `externalNativeBuild.cmake.version` and the Android SDK repository does not
   publish it,
4. clones the pinned Eden commit and applies `patches/` with `git am`,
5. runs Eden's own `.ci/android/build.sh`,
6. uploads `artifacts/*.apk` and `artifacts/*.aab` as a workflow artifact,
7. publishes them to a GitHub Release tagged `apk-<preset>-<build-type>`,
   renamed to `eden-mali-<preset>-<build-type>-<eden-commit>.apk`.

The release is a rolling one: re-running the workflow with the same preset and
build type replaces the assets on that tag rather than creating a new release.
Publishing needs `contents: write`, which the workflow requests.

Expect a cold build to take a long time; `ccache` is cached between runs, so
re-runs on the same pin are much faster.

## Building locally

```sh
./scripts/prepare-source.sh            # clone pinned Eden + apply patches
PRESET=armv9-x925 BUILD_TYPE=Release ./scripts/build-apk.sh
```

You need JDK 17, an Android SDK with the three packages listed above, CMake
3.31.6 discoverable at `$ANDROID_SDK_ROOT/cmake/3.31.6/bin/cmake`, and
`ANDROID_SDK_ROOT` exported. Eden fetches its C++ dependencies with CPM at
configure time, so the first build needs network access.

To build against upstream `git.eden-emu.dev` instead of the GitHub mirror:

```sh
EDEN_REMOTE=upstream ./scripts/prepare-source.sh
```

Both remotes carry the same commit; the mirror exists because
`git.eden-emu.dev` is not reachable from every network.

## Signing

With no `ANDROID_KEYSTORE_B64` set, Eden's build signs with the debug keystore
checked into `src/android/app/debug.keystore`. That APK installs fine and, thanks
to Eden's `applicationIdSuffix`, sits alongside an official Eden install rather
than replacing it. To sign with your own key, set `ANDROID_KEYSTORE_B64`,
`ANDROID_KEYSTORE_PASS` and `ANDROID_KEY_ALIAS` — Eden's `.ci/android/build.sh`
picks them up.

## Installing

```sh
adb install -r eden-src/artifacts/app-mainline-release.apk
```

Or copy the APK to the tablet and install it from the file manager, with
"install unknown apps" allowed for that app.

Eden ships no Nintendo firmware, keys or games. You need to supply those from
hardware you own.
