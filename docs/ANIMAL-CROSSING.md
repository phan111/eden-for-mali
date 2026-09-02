# Animal Crossing: New Horizons on a Galaxy Tab S11

Source references are to the pinned Eden revision in `../eden-source.pin`
(`c0a85d0e`). Anything not verifiable from that source or from a capture is
marked as such.

## The important thing first: this game does not need more FPS

Animal Crossing: New Horizons is **capped at 30 fps on real Switch hardware**,
at 1080p docked and 720p handheld. The Tab S11 capture showed `FPS: 30.0`
climbing to `30.6` before the stall.

**That is the game running at full speed.** There is no frame rate left to win.
Every setting below is aimed at *removing stalls*, not at raising a number —
tuning this title like a demanding 60 fps game will cost battery and heat for
nothing.

## Why it froze at "Building 1 Shader(s)"

This is not a Mali problem, an Armv9 problem, or a Tab S11 problem. It is a
default setting, and the mechanism is explicit in the source.

`PipelineCache::BuiltPipeline()` in
`src/video_core/renderer_vulkan/vk_pipeline_cache.cpp:736-750`:

```cpp
GraphicsPipeline* PipelineCache::BuiltPipeline(GraphicsPipeline* pipeline) const noexcept {
    if (pipeline->IsBuilt()) {
        return pipeline;
    }
    if (!use_asynchronous_shaders) {
        return pipeline;        // <-- hand back an UNBUILT pipeline: the draw waits
    }
    ...
    return nullptr;             // <-- async: skip this draw, keep the frame moving
}
```

With asynchronous shaders **off**, a draw that needs an unbuilt pipeline gets
that pipeline anyway and blocks until compilation finishes. With it **on**, the
draw returns `nullptr` and is simply skipped for that frame — the object pops in
a moment later and the frame rate never drops to zero.

`use_asynchronous_shaders` defaults to **`false`** (`src/common/settings.h:645`).

That single default explains the capture exactly: 30 fps → 21.2 → 6.2 → 0.0,
pinned at zero on one shader for 25+ seconds.

## The settings that actually matter here

### 1. Asynchronous shaders → ON

*Settings → Advanced Graphics → Asynchronous Shaders.* The fix for the stall
above. Cost: objects briefly missing while their shader builds.

### 2. Pipeline worker count → raise it

This is the one most people miss. `GetTotalPipelineWorkers()`
(`vk_pipeline_cache.cpp:303-317`):

```cpp
const size_t max_core_threads =
    std::max<size_t>(std::thread::hardware_concurrency(), 2ULL) - 1ULL;
const int clamped = std::clamp(configured, 2, 8);
return std::min(max_core_threads, desired);
```

and the Android default (`src/android/app/src/main/jni/android_settings.h:150`):

```cpp
Settings::SwitchableSetting<s32> pipeline_worker_count{linkage, 2, "pipeline_worker_count", ...}
```

**The default is 2.** The Tab S11's MT6991 has 8 CPU cores, so `max_core_threads`
is 7. Setting `pipeline_worker_count` to its maximum of 8 yields **7 compile
threads instead of 2** — roughly 3.5x the shader-compilation throughput, which
is precisely the resource this game is starved of on first run.

Trade-off: more cores compiling means more heat. On a title that is already at
its 30 fps ceiling, spending that thermal headroom on shorter stalls is a good
trade; on a demanding 60 fps title it may not be.

### 3. Vulkan driver pipeline cache → leave ON

Default is already `true` (`settings.h:565`). Once a shader compiles
successfully it is kept, so a scene only stalls the first time. Much of the pain
here is one-time — do not clear this cache casually.

### 4. Resolution → 1x, and no higher

The game renders 1080p docked / 720p handheld. At 1x you are already at or above
native. Raising it buys sharper edges on a title with a hard frame cap while
adding GPU load and heat.

## Not worth changing for this game

| Setting | Why not |
| --- | --- |
| Force maximum clocks | A no-op on Mali — it is implemented purely through `adrenotools_set_turbo()`, which is Qualcomm-only. See [`FINDINGS.md`](FINDINGS.md). |
| ASTC recompression | Immortalis-G925 samples ASTC natively; recompressing throws that away, and Arm GPUs have no BCn target. |
| Accuracy level → High | Extra work for no visible gain here; several `IsGPULevelHigh()` paths are already skipped on Mali. |
| Anything chasing >30 fps | The game is capped at 30. |

## A note on how shader threads are scheduled

The pipeline builder pool is created with `Common::ThreadPlacement::Background`
(`vk_pipeline_cache.cpp:353-354`). On Android that means the compile threads run
at `ThreadPriority::Low` and are registered with ADPF as a background session
(`src/common/thread.cpp:562-567`), though they are left on `CoreGroup::Unrestricted`
so the big cores remain available to them.

Worth knowing: `has_broken_parallel_compiling` is **declared but never assigned
anywhere in the tree** (`vulkan_device.h:1208` is its only definition), so it is
always false and parallel compilation is never disabled on Mali. The worker count
is the only real limiter.

## Eden has no per-game profile for this title

`Core::GameSettings::LoadOverrides()` (`src/core/game_settings.cpp:122-140`) is
the per-title override hook, and its `TitleID` enum currently contains exactly
one game (Ninja Gaiden: Ragebound). There is no Animal Crossing entry, so nothing
is tuned for it automatically — every recommendation above has to be set by hand.

## Still unverified

- Whether the 25-second compile is normal for this shader on Arm driver 19.0.1,
  or is specific to the `armv9-x925` build. The `custom`-preset control build
  settles that; until it is compared, neither is ruled out.
- Whether raising `pipeline_worker_count` measurably shortens the stall on this
  device. It follows from the code, but it has not been measured here.
- Reported elsewhere, not verified in this repository: ACNH is rated playable
  start-to-finish on Switch emulators with minor glitches, with no multiplayer
  or dream-address support in any form.

## Sources

- [Animal Crossing: New Horizons — Digital Foundry verdict (Nintendo Life)](https://www.nintendolife.com/news/2020/03/video_digital_foundry_delivers_its_verdict_on_animal_crossing_new_horizons)
- [Animal Crossing: New Horizons compatibility (yuzu)](https://yuzu-mirror.github.io/game/animal-crossing-new-horizons/)
- [yuzu Progress Report, January 2021](https://yuzu-mirror.github.io/entry/yuzu-progress-report-jan-2021/)
- [Shader caches — Emulation General Wiki](https://emulation.gametechwiki.com/index.php/Shader_caches)
