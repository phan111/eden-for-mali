# Audit: Eden's Mali / Immortalis code paths

All line references are against the pinned revision in `../eden-source.pin`
(upstream Eden `c0a85d0e`, 2026-08-29).

## Summary

**Eden's Mali support is already mature, and it is mostly capability-driven
rather than vendor-hardcoded.** That is the main finding, and it is why the
patch series in this repository is two patches long instead of twenty.

The Vulkan backend already special-cases `VK_DRIVER_ID_ARM_PROPRIETARY` in six
places, treats Mali as a tile-based renderer throughout, and derives every
shader-compiler decision from reported device features rather than from a vendor
allow-list. There is no large untapped Mali win sitting in the renderer that can
be claimed without hardware measurement — and inventing driver "bug workarounds"
for a GPU nobody has profiled would make things slower, not faster.

So the gains here are taken where they are real and verifiable: the **compiler
target** (patch 0001), **diagnostics** (patch 0002), and **settings**
([`TAB-S11-TUNING.md`](TAB-S11-TUNING.md)).

## What is already handled for Mali

| Area | Where | Behaviour |
| --- | --- | --- |
| Tiler classification | `vulkan_device.h:317` `Device::IsTiler()` | Returns true for `ARM_PROPRIETARY`. |
| MSAA on tilers | `vk_texture_cache.cpp:3034,3039`, `vk_graphics_pipeline.cpp:142` | Tiler-specific multisample handling, so Mali takes the tiler path. |
| Descriptor buffer sizing | `vk_descriptor_buffer.cpp:29` | Uses `TILER_FRAME_SIZE` instead of `DESKTOP_FRAME_SIZE` on Mali. |
| Query sync fast path | `vk_query_cache.cpp:240` (`PresyncWrites`) | Mali skips the expensive query resolve, alongside Adreno/Turnip. |
| Host conditional rendering | `vk_query_cache.cpp:1524` | Mali bails out early instead of emulating it. |
| Compute shared memory | `vk_pipeline_cache.cpp:936-938` | Clamps requested shared memory to the device maximum on Mali. |
| Dynamic storage buffers | `vk_buffer_cache.cpp:353-354` | Limits dynamic storage buffer descriptors on Mali. |
| Vendor mapping | `game_settings.cpp:45-47` | `"Mali"` and `"PanVK"` map to `GPUVendor::ARM`. |
| Driver naming | `vulkan_wrapper.cpp:1083-1084` | Reports `ARM_PROPRIETARY` as `"Mali"`. |
| Swapchain image count | `vk_present_manager.cpp:359-368` | `MAX_FRAMES_IN_FLIGHT` is 7 and Mali reports 6; the `std::min` clamp is already correct. |
| ASTC | `vulkan_device.cpp:809-839` `ComputeIsOptimalAstcSupported()` | Pure format-capability probe. Immortalis-G925 exposes native ASTC, so textures are sampled directly with **no decode pass**. |
| Shader profile | `vk_pipeline_cache.cpp:373+` | Every `support_*` field comes from a device query. No vendor branch to extend. |
| NCE | `CMakeLists.txt:299-302` | `HAS_NCE=1` on arm64 Android, so the native code execution fast path is already active. |

Note also what is *deliberately not* applied to Mali: the large `is_qualcomm`
block in `vulkan_device.cpp:508-566` disables `VK_EXT_color_write_enable`,
`shaderInt64` atomics and workgroup-memory-explicit-layout, forces scaled vertex
format emulation, and patches BCn support into the driver via `adrenotools`.
Those are Adreno defects. Copying them to Mali would cost performance and
correctness for no reason. Arm GPUs do not expose the BCn family at all, and
Eden's format-capability checks already account for that.

## Confirmed defect: "Force maximum clocks" is a no-op on Mali

`Device::ShouldBoostClocks()` (`vulkan_device.cpp:866-885`) lists AMD, NVIDIA,
Intel, Qualcomm, Turnip and Samsung — but not Arm. That omission looks like a
bug, and the obvious "fix" of adding `VK_DRIVER_ID_ARM_PROPRIETARY` to the list
is wrong.

The reason is in `vk_turbo_mode.cpp`: the portable clock-boosting mechanism is a
compute shader submitted in a loop to keep the GPU fed, and that entire
mechanism is compiled out under `#ifndef __ANDROID__` (lines 43-154, 195-227).
What remains on Android is:

```cpp
#if defined(__ANDROID__) && defined(ARCHITECTURE_arm64)
        adrenotools_set_turbo(true);
#endif
```

`adrenotools_set_turbo()` drives Qualcomm's KGSL interface. It cannot raise
clocks on a Mali GPU. Adding Arm to `ShouldBoostClocks()` would therefore spawn a
thread that wakes continuously, raises no clocks, and burns battery — and on a
thermally limited tablet, wasted power actively reduces sustained frame rates.

Patch 0002 records this in-source so the omission is not "corrected" later, and
the tuning guide tells Tab S11 users to leave the setting off. Giving Android a
real Mali boost path would mean implementing one (the compute-shader path, or an
Arm-specific interface) — that is a genuine upstream feature, not a one-line fix,
and it needs on-device power and thermal measurement to justify.

## Why the CPU target is the lever that matters

Switch emulation is heavily CPU-bound: the guest CPU is emulated by Dynarmic (or
run natively under NCE), and the shader recompiler, texture cache and command
processor are all host CPU work. Before this series, the arm64 build presets
(`CMakeLists.txt:341-350`) topped out at `armv8.2-a+lse+rcpc` ("optimized") or
`armv9-a` with `-mtune=generic` ("armv9"). Nothing targeted a specific modern
core.

The Tab S11's Dimensity 9400+ is an Armv9.2 SoC with a Cortex-X925 prime core.
Patch 0001 adds a preset that raises the ISA baseline to `armv9-a` and points
`-mtune` at `cortex-x925`. `-mtune` only affects instruction scheduling and cost
modelling — never instruction selection — so it stays correct across the
big.LITTLE cluster, and the value is probed with `check_cxx_compiler_flag` so an
older toolchain degrades to generic tuning instead of failing to configure.

## Not measured

Nothing in this repository has been benchmarked on a physical Galaxy Tab S11 —
there is no such device in the build environment, and no Android device of any
kind. The patches are conservative by design for exactly that reason: patch 0001
changes only compiler flags, and patch 0002 changes only log output plus a
comment. Neither alters renderer behaviour.

Treat the settings guide as a starting point to measure from, not as a set of
proven numbers.
