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

### Releases need a writable Actions token

Publishing requires `contents: write`, which the workflow requests — but a
repository can *cap* its Actions token at read-only, and that cap wins over
anything declared in a workflow file. When it is set, `gh release create` fails
with `HTTP 403: Resource not accessible by integration`.

Enable it once, under **Settings → Actions → General → Workflow permissions**,
by selecting **Read and write permissions**.

The build step never fails because of this: the APK is uploaded as a workflow
artifact before the release is attempted, and if publishing is denied the job
warns, writes instructions into the run summary, and still succeeds.

### Publishing a build you already have

`publish-release.yml` attaches an APK from an earlier build run to a release
**without recompiling Eden**. Actions → *Publish APK to a Release* → *Run
workflow*, and give it the run id of the build (it is in that run's URL). Use
this after enabling the token permission, instead of spending another hour on a
rebuild.

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

## Telling two builds apart on the device

Every preset builds the same `applicationId` (`dev.eden.eden_emulator`) with the
same app name, so installing one replaces the other and nothing in the launcher
distinguishes them. To make an A/B interpretable, CI stamps each build with its
preset.

It does that through a mechanism Eden already has: `GIT-TAG` and `GIT-RELEASE`
files in the source root, read by `externals/cmake-modules/GetSCMRev.cmake`, with
`CMakeModules/GenerateSCMRev.cmake` then using `GIT_TAG` verbatim as
`BUILD_VERSION`. No patch is involved.

The stamp is `<preset><-hyphens-removed>-r<repo commit>`, e.g.
`armv9x925-re6adf29`. It shows up in three places:

- the **in-game overlay**, which renders the segment before the first hyphen as
  the build id — so it reads `armv9x925` or `custom` next to the FPS counter, and
  a screen recording identifies the build with no extra effort;
- **Settings → Apps → Eden**, as the app version;
- the **release asset filename**, which also carries the commit.

Hyphens are stripped from the preset because the overlay splits on the first one.

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
