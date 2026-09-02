# eden-for-mali

Downstream build tuning for the [Eden](https://git.eden-emu.dev/eden-emu/eden)
Switch emulator, targeting **Arm Mali / Immortalis GPUs** and specifically the
**Samsung Galaxy Tab S11 / S11 Ultra** (MediaTek Dimensity 9400+, Cortex-X925,
Arm Immortalis-G925 MC12).

This repository does **not** fork Eden. It holds a small, reviewable patch
series plus the scripts and CI needed to build a Tab S11-targeted APK from a
pinned upstream revision.

```
patches/           patch series applied on top of upstream Eden (git am)
eden-source.pin    the exact upstream commit the series is built against
scripts/           clone-and-patch, and a local APK build wrapper
.github/workflows/ CI that builds the APK and uploads it as an artifact
docs/              audit findings, Tab S11 tuning guide, build notes
```

## What this actually changes

Two patches. Both are deliberately small — see [`docs/FINDINGS.md`](docs/FINDINGS.md)
for why the list is short.

| Patch | Effect |
| --- | --- |
| `0001-cmake-add-armv9-x925-arm64-build-preset` | New `YUZU_BUILD_PRESET=armv9-x925`: builds at an `armv9-a` ISA baseline and schedules for the Cortex-X925 prime core of the Dimensity 9400+. This is the one change with a real, measurable performance effect, and Switch emulation is heavily CPU-bound. |
| `0002-video_core-identify-the-Arm-proprietary-driver-in-GP` | Eden's GPU log/crash-dump layer knew Turnip and Qualcomm but reported "Unknown" for Arm's Mali/Immortalis driver. Adds a `Mali` driver type so logs are usable for tuning. Also records in-source why Arm is (correctly) excluded from `Device::ShouldBoostClocks()`. |

> **The `armv9-x925` build requires Armv9 hardware.** It will not install-and-run
> on pre-Armv9 devices. Build the `optimized` or `generic` preset for those.

The bulk of the practical gain on a Tab S11 comes from **settings**, not from
patching Eden — see [`docs/TAB-S11-TUNING.md`](docs/TAB-S11-TUNING.md), and
[`docs/ANIMAL-CROSSING.md`](docs/ANIMAL-CROSSING.md) for a per-title study of
Animal Crossing: New Horizons.

## Getting an APK

**From the repository's Releases.** Every successful build publishes the APK to
a release tagged `apk-<preset>-<build-type>` — for the Tab S11 target that is
[`apk-armv9-x925-Release`](../../releases/tag/apk-armv9-x925-Release). Release
assets are a direct download and do not expire, unlike workflow artifacts.

**Building a fresh one.** Actions → *Build Eden APK (Mali / Galaxy Tab S11)* →
*Run workflow*. Pick a preset and build type; the APK and AAB are attached to
the matching release and also uploaded as a workflow artifact. The APK is signed
with Eden's checked-in debug key, so it installs alongside an official Eden
build rather than replacing it.

Attaching to a release needs the repository's Actions token to be writable
(**Settings → Actions → General → Workflow permissions → Read and write
permissions**). Without it the build still succeeds and the APK is still
downloadable from the run's artifacts — see [`docs/BUILD.md`](docs/BUILD.md).
The *Publish APK to a Release* workflow can then attach an already-finished
build without rebuilding it.

**Locally.**

```sh
./scripts/prepare-source.sh          # clone pinned Eden + apply the series
./scripts/build-apk.sh               # needs JDK 17 + Android SDK/NDK
# APK lands in eden-src/artifacts/
```

Prerequisites for a local build are listed at the top of
[`scripts/build-apk.sh`](scripts/build-apk.sh) and in
[`docs/BUILD.md`](docs/BUILD.md).

## Rebasing onto a newer Eden

Bump `EDEN_COMMIT` in `eden-source.pin`, re-run `scripts/prepare-source.sh`, and
fix any `git am` rejects. Both patches touch stable, rarely-edited code
(`CMakeLists.txt`, `gpu_logging`, `vulkan_device.cpp`), so drift should be rare.

## Licence

Eden is GPL-3.0-or-later; the patches here are derived from it and carry the
same licence. Eden is an emulator — it ships no Nintendo code, keys, firmware or
games, and neither does this repository.

## ภาษาไทย

คำอธิบายภาษาไทยอยู่ที่ [`docs/README-TH.md`](docs/README-TH.md)
