# Galaxy Tab S11 tuning guide

For **Galaxy Tab S11 / S11 Ultra** — MediaTek Dimensity 9400+ (Armv9.2, Cortex-X925
prime core), **Arm Immortalis-G925 MC12** GPU, 12–16 GB unified LPDDR5X memory,
120 Hz display.

Settings are in Eden's Android UI under *Settings → Graphics* and
*Settings → Advanced Graphics*. The `key` column is the name written to
`config.ini`, so you can confirm you changed the right thing.

## Verified from Eden's source

These follow from code paths audited in [`FINDINGS.md`](FINDINGS.md), not from
guesswork.

| Setting | key | Value | Why |
| --- | --- | --- | --- |
| Force maximum clocks | `force_max_clock` | **Off** | On Android this is implemented purely through `adrenotools_set_turbo()`, which is Qualcomm-only. On Mali it cannot raise clocks; leaving it on only wastes power, which costs you sustained frame rate on a tablet. |
| ASTC recompression | `astc_recompression` | **Uncompressed** (default) | Immortalis-G925 exposes native ASTC, so `ComputeIsOptimalAstcSupported()` passes and textures are sampled with no decode pass at all. Recompressing would throw that away — and Arm GPUs do not expose BCn targets. |
| Accelerate ASTC decoding | `accelerate_astc` | **GPU** (default) | Only used when native ASTC is unavailable. Harmless to leave alone. |
| Vulkan driver pipeline cache | `use_vulkan_driver_pipeline_cache` | **On** (default) | The Arm driver has a working pipeline cache; this cuts repeat shader build cost across launches. |

## Worth measuring on your device

Reasonable starting points given the hardware. Change **one at a time** and watch
sustained frame rate over 10+ minutes, not the first 30 seconds — thermal
behaviour is what decides playability on a tablet.

| Setting | key | Suggested | Notes |
| --- | --- | --- | --- |
| VRAM usage mode | `vram_usage_mode` | **Aggressive** | Default is `Conservative`, which is tuned for 6–8 GB phones. With 12–16 GB of unified memory the Tab S11 has plenty of headroom. One of the more promising changes here. |
| Resolution scale | `resolution_setup` | **1x** | Immortalis-G925 is strong, but Switch titles at above-native resolution are the fastest way to become GPU- and thermally-bound. Get a stable 1x first; only then try 1.5x. |
| Anti-aliasing | `anti_aliasing` | **FXAA**, or None | Eden has explicit tiler-aware multisample paths, so MSAA is viable on Mali, but FXAA is the cheaper starting point. |
| Asynchronous shaders | `use_asynchronous_shaders` | **On** | See the measured stall below — on this hardware leaving it off can freeze the emulator outright, not merely stutter. |
| Accuracy level | `gpu_accuracy` | **Normal** | `High` enables extra `IsGPULevelHigh()` work. Several of those paths are already skipped on Mali, so High tends to cost more than it returns here. |
| Frame pacing | `frame_pacing_mode` | **Auto**, or pin 60 | The panel is 120 Hz, but almost no Switch title exceeds 60 fps. Pinning 60 can give steadier pacing and lower power. |
| Extended dynamic state | `dyna_state` | **Leave at default (EDS3)** | Drop to EDS2 only if you hit rendering glitches. Eden disables broken EDS3 blending on Samsung Xclipse drivers specifically; Arm's driver is not in that group. |

## Measured on hardware: the synchronous shader stall

The first real-device capture (Galaxy Tab S11, `SM-X730`, Mali-G925-Immortalis
MC12, `MT6991`, Arm driver `19.0.1`) running Animal Crossing: New Horizons on
the `armv9-x925` build showed this:

| elapsed | on-screen counter |
| --- | --- |
| 0-7 s | `FPS: 30.0` then `30.6` — smooth |
| 8 s | `FPS: 21.2 \| Building 1 Shader(s)` |
| 9 s | `FPS: 6.2 \| Building 1 Shader(s)` |
| 10-35 s | `FPS: 0.0 \| Building 1 Shader(s)` — pinned at zero until force-closed |

A **single** shader took over 25 seconds and blocked the render thread the whole
time. The emulator had not crashed; it was waiting.

**Turn Asynchronous shaders on.** With it off, pipeline creation happens on the
thread that presents frames, so one slow compile stops everything. With it on,
the frame keeps advancing and the shader is dropped in when it is ready.

Once a shader has been built successfully, `use_vulkan_driver_pipeline_cache`
(on by default) keeps it, so the same stall should not repeat on later launches
of that scene.

If the stall persists with async shaders on, capture a GPU log — Eden now labels
the Arm driver correctly, so the log identifies the shader that hangs. Enable
`gpu_log_level` plus `gpu_log_driver_debug` under Advanced Graphics.

> Whether this stall is specific to the `armv9-x925` build or is how Eden
> behaves on this Mali driver generally is **not yet established**. The control
> is a `custom`-preset build — identical source and patches, no `-march`/`-mtune`
> flags, which is exactly what upstream Eden ships. Compare the same scene on
> both before blaming either.

## Not GPU settings, but they matter

- **Keep the tablet cool and off the charger while playing.** Charging heat
  throttles the SoC, and on a Dimensity 9400+ the prime core down-clocks well
  before you see a thermal warning. This will affect your frame rate more than
  any single toggle above.
- **Leave CPU/NCE settings alone.** `HAS_NCE=1` is already enabled for arm64
  Android builds, so the native execution fast path is active by default.
- **Use the `armv9-x925` APK.** Its whole purpose is the CPU side of this, and
  Switch emulation is CPU-bound more often than GPU-bound. See
  [`BUILD.md`](BUILD.md).

## Reporting results

If you want the tuning above refined into something evidence-based, the useful
thing to capture is a GPU log — Eden's log now names the Arm driver correctly
(patch 0002), so a log will show driver version and extension support. Enable
*Advanced Graphics → GPU logging* (`gpu_log_level`, plus `gpu_log_driver_debug`
for the driver dump), reproduce a slow scene, and keep the log alongside a note
of the title and the settings you used.
