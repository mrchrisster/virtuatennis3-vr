# Classic mode: a simpler, cheaper 2D path (and Quest 2)

Research only (2026-11-13). No code changed, nothing built or run. Code read at
submodule `bd68848` (lindberghrecomp `vt3-quest`). **[code]** = verified by
reading the code (file / function named); **[docs]** = a measurement recorded in
`ai_docs/` or `docs/`; **[inferred]** = reasoning from the code, not tested;
**[general]** = general knowledge about Quest hardware / OpenXR that must be
checked before relying on it.

## For the owner (plain language)

**What happens today.** In Classic the game draws its normal flat picture, but it
draws it as if it were a VR scene: twice (once per eye, both copies identical),
each at the headset's full eye size (2064 x 2208), with 2x anti-aliasing. Then
our code takes one of the two copies, shrinks it onto a virtual screen and paints
that screen into each eye. On the Medium screen the picture covers only about
1400 x 850 of the eye's pixels, so the game draws roughly **8-9 times more
pixels than end up being seen**, and the second copy is thrown away unused.

**What we would change.** Let the game draw the picture once, at about its own
arcade size (1360 x 768, or 1.5x that for extra sharpness), and hand it to the
headset as a "screen" layer. The headset's own compositor then places the screen
in the room itself, at the full display rate, which is exactly what it is built
for (it already does this for our start-up screen).

**What you would notice.** Steadier, sharper picture on the screen (the picture
is resampled once instead of twice, and the screen no longer shimmers when you
move your head - this may well be most of the texture flicker you reported in
Classic); the screen stays rock-steady even when the game hitches; the headset
runs cooler and the battery lasts longer. Nothing changes in how the game looks
or plays otherwise. VR mode is untouched.

**Effort.** In small steps, each one behind a switch and each leaving the game
working: step 1 (draw at the arcade size) about a day; step 2 (the screen as a
headset layer, the settings panel on top) two to three days; the rest is
optional. No change to the game's own drawing.

**Quest 2.** Classic should run comfortably on a Quest 2 after step 1-2 (its
graphics chip is roughly half a Quest 3's, but Classic would need a quarter of
today's work). The open question for Quest 2 is the processor, not the graphics:
the recompiled game and the graphics translation each need most of a 60 fps
frame on the Quest 3 already; one measurement on the Quest 3 tells us how much
room is left (section 3). VR mode on Quest 2 would need lower settings (smaller
eye picture, 2048 shadows, 72 or 90 Hz) chosen automatically on first launch,
without touching anyone's saved settings.

---

## 1. How Classic is rendered today

### 1.1 Step by step (one game frame)

1. **Multiview is on for the whole run, both modes. [code]** `stereo.c
   eye_targets_multiview()` turns on gl4es multiview (`gl4es_multiview_enable`,
   unless `LINDBERGH_MULTIVIEW=0`) before the game makes any program or render
   target, and makes ONE framebuffer `g_eye_fbo[0]` whose colour/depth are
   rectangle textures that gl4es backs with a **2-layer `GL_TEXTURE_2D_ARRAY`**
   (`quest/gl4es.patch` `multiview.c`: `array_for`, `TexStorage3D(..., w, h,
   2)`). Every shader gl4es emits becomes GLSL ES 3.00 with
   `layout(num_views=2)` and `gl_Position = gl4es_mvR[gl_ViewID_OVR] * ...`
   (patch lines ~815-847). So **every draw is rasterised and shaded into two
   layers**, in Classic too.
2. **The eye array is the headset's eye size. [code]** `host_xr.c xr_init`
   sizes the swapchains from `cfg.width x cfg.resolution` (default
   `LG_XR_NATIVE_WIDTH/HEIGHT` = **2064 x 2208** on Android, `xr_settings.h`) and
   calls `stereo_eye_size(w, h)`; the eye array is made at that size
   (`g_ew x g_eh`).
3. **The game's picture is stretched to fill the eye array. [code]**
   `stereo_eye_size` sets `g_sx = w / 1360`, `g_sy = h / 768` (`stereo.c` ~4662)
   = **1.52 x 2.875**: a 16:9 picture drawn into a near-square texture,
   anisotropically super-sampled. Viewports/scissors are scaled
   (`apply_rect`), and the game's own picture-sized render targets (the
   depth-of-field / glare chain, screen copies) are re-allocated at eye size too
   (`scale_target` -> `lg_stereo_target_scale`, `stereo_projection.c`: a
   1360x768 target becomes 2064x2208; other targets up to 2x / 1024 px, the
   shadow map by `world_mode_shadow_scale`).
4. **Every frame is "flat" in Classic. [code]** `stereo_frame_begin` (~4511):
   `flat_all = world_mode_capable() && !world_mode_immersive()` -> `g_flat = 1`.
   Per draw, `lg_stereo_classify_draw` still runs and returns `LG_STEREO_PASS`
   for `d->flat` (`stereo_projection.c`); `effective_projection` returns the
   game's matrix, so `g_mvR[1]` is identity: **both layers get the same
   picture** (unless the test-only stereoscopic screen `LINDBERGH_STEREO_DEPTH`
   is set, `stereo_screen_3d`).
5. **MSAA is on the eye array. [code]** `world_mode_msaa()` (VT3 default 2,
   `xr_settings_vt3_defaults`) -> `gl4es_multiview_msaa`:
   `glFramebufferTextureMultisampleMultiviewOVR` with implicit resolve. Every
   read of the eyes mid-frame (the game's whole-screen `glCopyTexSubImage2D`s
   for depth of field, `copy_from_eyes` -> `gl4es_multiview_copy`; the frame
   hold; game shots) forces a resolve of both layers. **[code comment in
   `eye_targets_multiview`]**
6. **Screen copies** (`copy_from_eyes`): the game copies the screen into
   textures (ground-shadow mask, DoF chain) - from the eye array, at eye scale,
   layer 0 only (`gl4es_multiview_copy(..., 0, ...)`) into a 2D texture that
   gl4es then also keeps as a 2-layer array (mv_copy / copy-back,
   `mv_framebuffer_left` blits layer 0 back into the 2D texture each time its
   framebuffer is left). **The per-eye mask twin is Immersive-only** (`mask_on()`
   is `world_mode_immersive() && ...`; `mask_copy` returns on `g_flat`) - not a
   Classic cost. **[code]**
7. **Frame end, host (`host_xr.c xr_frame_end`). [code]** For each eye: acquire
   the eye's swapchain image (2064x2208, `sampleCount 1`), and because the frame
   is flat, `xo_draw_screen()` (`xr_overlay.c`): clear the swapchain image to
   black, draw one textured quad = the virtual screen at `(0, 0, -d)` in the
   `local` space with half-size `stereo_screen()` (= `d / 1.732` wide, lens
   `g_screen_lens`), sampling **layer 0 of the eye array for both eyes**
   (`layers && stereo_screen_3d() ? i : 0`) with sampler `smp_screen` =
   `GL_LINEAR`/`GL_LINEAR`, **no mipmaps** (the array has 1 level). Then the
   controller model / laser (`xo_draw`), the stats label, the settings panel
   (`xo_draw_panel`) are drawn into the same eye image. Submitted as one
   `XrCompositionLayerProjection` (2 views), plus the splash quads during
   start-up. No depth layer in flat frames (`depth_capture` skipped).
8. **Frame hold [code]** (`hold_begin/hold_end/hold_blit`): on the match-start
   frame the whole 2-layer eye array is copied aside and put back
   (`glCopyTexSubImage3D` per layer).
9. **Foveation is not applied in this (GLES) host at all. [code]**
   `host_xr.c` has no `XR_FB_foveation` / swapchain foveation and no
   `GL_QCOM_texture_foveated`; the panel's Foveation value (`cfg.foveation`,
   VT3 default High) is consumed only by `vulkan_guest.cpp` (the Vulkan host).
   The game renders into gl4es's own array, not into the swapchain, so even
   swapchain foveation would not reach it. **The Foveation row does nothing for
   VT3 on the Quest today** (both modes).
10. **Display rate. [code]** `refresh 120` (VT3 default) via
    `xrRequestDisplayRefreshRateFB`; the game draws at 60, so each frame is
    shown twice (`host_xr.c` header comment, `display_cadence.c`); the second
    display frame is the compositor's reprojection of the projection layer.

### 1.2 Resolution: drawn vs seen

| | pixels | notes |
|---|---|---|
| game's own picture | 1360 x 768 = 1.04 Mpx | the arcade's |
| drawn per layer today | 2064 x 2208 = 4.56 Mpx | 1.52 x 2.875 stretch |
| drawn per frame today | 9.1 Mpx x 2 MSAA samples | two identical layers |
| eye pixels the Medium screen covers | ~1400-1500 x ~850-900 | **[inferred]**: screen 60 deg x 36 deg (lens 1.732 -> 2 atan(1/1.732) = 60 deg; 36 deg tall at 16:9), Quest 3 ~25 px/deg in the centre **[general]** |

So the picture is drawn at ~2.9x the needed height and then **minified ~2.5x
vertically with a plain bilinear tap and no mipmaps** (step 7) - a classic
recipe for aliasing that crawls as the head moves (section 5.3). Then the
compositor resamples the eye image again for lens distortion (second resample).

### 1.3 Work that exists only because Classic shares VR's path

| item | where | Classic needs it? |
|---|---|---|
| second multiview layer: all fill, all fragment shading, resolves, copy-backs x2 | gl4es `multiview.c`, `g_eye_fbo` | no - layer 1 is never shown **[code]** |
| eye-size eye array + eye-size game targets (DoF chain, copies) | `stereo_eye_size`, `scale_target` | no - ~1.0-2.3 Mpx is enough |
| MSAA on a 2064x2208x2 target, resolved at each screen copy | `eye_targets_multiview` | only on a small target |
| per-draw classification, matrix pair upload (`view_matrices`, `gl4es_multiview_set`), clip distances (`clip_to_screen`) | `stereo.c` | no (CPU cost per draw on the GL worker; small, unmeasured) |
| full-screen clear + screen quad + overlay draws into two 2064x2208 swapchain images | `xr_frame_end`, `xo_draw_screen` | no - the compositor can place a quad |
| frame hold copying both eye layers | `hold_blit` | no - with a quad: just do not update the image |
| mask twin | `mask_copy` | already off in Classic **[code]** |
| foveation interplay | none | none today (not applied) |

### 1.4 Measurements on file (all unattended unless noted: the unworn
headset's session stops, nothing is composited, the game is paced at 60 by the
clock - GPU ms are the game's GPU work only) **[docs]**

- 2026-11-13 R1/R2 (`/tmp/vt3q/T24`, msaa 2, aniso 4, "4096"): match **4.0-4.3
  ms** average (90% 4.1-6.5), split + shots window 5.3 ms, worst 9.9; first
  match frames 2.7 ms (HANDOFF ~212). Mode not stated in the entry; the repro
  script pins Classic unless the caller sets `LINDBERGH_VT3_IMMERSIVE` -
  **probably Classic**, to be confirmed from `vt3.log` `[world] mode`.
- 2026-11-13 S4 split fix: split window **5.4 ms avg, 90% 8.3, worst 9.8**,
  rally 4.0 ms (CONDUCTOR_STATE ~377) - 90% = the whole 120 Hz budget.
- Immersive, msaa 0 era: 2.6-3.8 ms; stands +0.2 ms; sky fix 4.6 -> 3.2 ms
  (README ~520). Before the sky fix: Classic 55.9 fps / 21 late frames per 5 s.
- GPU page faults (UCHE BR_SP ~900/s) in every run, both modes, cause unknown
  (backlog) - not tied to the eye path.
- Start-up: ~1.5 s to session, ~8 s loading to the first game frame, ~20 s of
  the board's own black boot (README ~633, guide ~496).

No Classic-vs-VR GPU pair at the same settings is on file - **measurement
owed** (section 4).

## 2. The simplest correct 2D design

### 2.1 Target design

- The game renders **once, mono**, into **one 2D colour target** at a chosen
  size: native 1360x768 (k = 1) or supersampled (k = 1.5 -> 2040x1152), MSAA
  2x/4x **on that target only** (cheap at ~1-2 Mpx).
- At frame end the host copies it (one blit, or render straight into a
  swapchain image) into a **quad swapchain** of that size and submits an
  `XrCompositionLayerQuad` in `local` at pose `(0, 0, -d)`, size `2hw x 2hh`
  (the same numbers `xo_draw_screen` uses today, `stereo_screen()`), or an
  `XrCompositionLayerCylinderKHR` (`XR_KHR_composition_layer_cylinder`
  **[general]**: supported on Quest) for a curved big screen.
- Background: nothing (the compositor shows black where no layer is) - or a
  tiny dim projection layer / passthrough later (Quest 3: colour passthrough;
  Quest 2: grey only **[general]**).
- Settings panel: its own quad (it is already an RGBA texture,
  `xo_panel_upload`); controller model + laser: a small alpha projection layer
  **only while something is shown** (panel open, gun shown), on top.
- Optional: `XR_FB_composition_layer_settings` with
  `XR_COMPOSITION_LAYER_SETTINGS_NORMAL_SUPER_SAMPLING_BIT_FB` (and/or
  sharpening) on the game quad - Meta's compositor then filters the quad with
  more taps **[general]**; and a mip chain on the quad swapchain (`mipCount >
  1`, `glGenerateMipmap`) if the Small screen size minifies it.

The **splash already does exactly this** (`host_xr.c sp_quad` / `sp_layers`:
static swapchain, quads in `local_base`, alpha flags) **[code]** - the layer
plumbing exists and is proven on the headset.

### 2.2 What it removes

- the second layer's fill and shading (half the GPU fill) - in step 3 only (see
  2.4), or kept but at 1/4 the size in step 1;
- ~75-90% of the pixels (9.1 Mpx -> 1.0-2.3 Mpx per frame, before MSAA);
- MSAA resolves of a 9 Mpx target at every screen copy;
- the per-eye clear + screen draw + panel draw into two 4.5 Mpx swapchain
  images (and their bandwidth);
- the frame-hold copy (hold = do not touch the quad image that frame);
- in step 3 also the multiview matrix uploads and clip distances per draw.

### 2.3 What it gains

- **Display-rate stability independent of the game:** the compositor
  re-composes the quad for every display refresh from the latest head pose;
  today the screen is baked into a 60 fps projection image and the second
  display frame is a reprojection of it. A late game frame then only delays the
  picture's *content*, never the screen's *position* - no judder of the screen
  at 72/90/120 Hz. **[general/inferred]**
- **Sharper, steadier picture:** one resample (game picture -> display) instead
  of two (picture -> eye image with an unmipped 2.5x bilinear minify -> lens
  distortion), with the compositor's own filtering. Text (scores, menus) gains
  most. **[inferred]**
- 120 Hz no longer needs the app to submit 120 frames: it never did (60 into
  120), but now nothing in the screen's placement depends on it, so 90 or 72 Hz
  are also judder-free for head motion (ball motion at 72/90 still has the 60 ->
  72/90 cadence unevenness; 120 keeps it even). **[inferred]**
- Lower power and heat (GPU at a lower level, section 4). **[inferred]**

### 2.4 Costs and risks

- **gl4es multiview is global.** Shaders are converted with `num_views=2`, and a
  framebuffer must have matching views - you cannot draw a multiview shader
  into a plain 2D FBO. So a *truly mono* path means multiview off
  (`LINDBERGH_MULTIVIEW=0`). That path exists (desktop, `stereo.c` "second eye
  replayed", `record()`/`replay(1)`), and `stereo_start_wide()` is a precedent
  for "one image, no second-eye replay, identity eye matrices" (`g_wide`:
  `stereo_frame_end` skips `replay(1)` when `g_wide`) **[code]**; but the Quest
  has not been run without multiview recently (no doc entry) **[docs]**, and it
  changes every shader's text (the ARB translation in `arbprog.c` declares
  `u_reproj` for multiview), so the disk shader caches rebuild and a live
  Classic <-> VR switch would need both shader sets. **Hence the plan keeps
  multiview in step 1-2 (draw two small identical layers, cost ~1 Mpx extra) and
  makes mono a separate, optional step 3.**
- **The game's own screen copies, depth of field, cross-fades, split screen.**
  With the eye array at the picture size every scale factor becomes 1 (`g_sx =
  g_sy = 1`; `lg_stereo_target_scale` keeps 1360x768 targets at 1x): this is
  the arcade's own arithmetic, the same as the macOS mono window that is the
  reference picture. At k = 1.5 the factors are uniform 1.5 instead of today's
  1.52 x 2.875 - less exotic than today. Split screen (pane prelude 6a95ff5)
  uses `g_side` targets and `g_cur_k` scaling, independent of the eye size
  **[code, `apply_rect`, `copy_from_eyes`]**; must be re-checked by shots.
  **[inferred: low risk]**
- **Code that assumes eye array == swapchain size. [code]** In flat frames the
  host never blits 1:1 (it samples the array as a texture in
  `xo_draw_screen`), `hold_blit` uses `stereo_eye_dims`, `GAME_SHOT` reads the
  array at its own size, `splash_sample` / `fl_sample` / `XR_SHOT` read the
  swapchain. The non-flat branch (`gl.BlitFramebuffer(0,0,e->w,e->h,...)`) and
  `depth_capture`/`aim_probe` assume equal sizes but never run in Classic
  (`flat_all`). Menu frames in VR mode are flat too, but VR keeps eye size.
- **Frame pacing.** Unchanged: the game loop still calls `xrWaitFrame` once per
  game frame. The quad only stops the screen from depending on it.
- **World-locked vs head-locked.** Today's screen is world-locked in `local`
  (re-anchored on Recentre, `anchor_head`) **[code]**; the quad in `local` is
  the same. A head-locked option is a one-line space change (VIEW space) but is
  uncomfortable for a big screen - not recommended.
- **Screen size Small / Medium / Big row** (being added by the other worker):
  maps directly to the quad's size (or `d`); with a quad the size can change
  live with no re-render. Choose k so that Big is still ~1:1: Big at ~80 deg
  wide needs ~2000 px across -> k = 1.5. **[inferred]**
- **Curved option:** cylinder layer, radius = d, `centralAngle = 2 atan(hw/d)`,
  `aspectRatio = 1360/768` - a new row, optional.
- **Pointer/panel:** `menu_hit` is pure maths in `host_xr.c` and stays; only
  where the panel/laser are *drawn* changes (quad + small overlay projection
  layer). Layer order: game quad, then panel quad, then the alpha overlay
  projection layer (laser over the panel), as `xr_frame_end` today draws the
  laser after the panel. The stats label: into the overlay layer or a quad.
- **Switching Classic <-> VR:** today a restart (`XW_RESTART`); live-switch
  groundwork exists (`world_mode_live`, `world_mode_on_switch`, HANDOFF 4.4
  "one program set, no relink") **[code/docs]**. Steps 1-2 keep that intact
  (multiview stays; switching = re-size the eye array + choose layers).
  Step 3 (mono) conflicts with Option A of the live switch - another reason to
  make it optional.
- **XR_SHOT** (eye image without the compositor) would no longer show the
  screen in Classic; the quad image itself is what to shoot (`GAME_SHOT`
  already is).

## 3. Quest 2 feasibility

### 3.1 Hardware **[general - verify against Meta's spec pages]**

| | Quest 2 | Quest 3 | Quest 3S | Quest Pro |
|---|---|---|---|---|
| SoC | XR2 Gen 1 (Adreno 650, Kryo 585) | XR2 Gen 2 (Adreno 740) | XR2 Gen 2 | XR2+ Gen 1 |
| GPU vs Quest 3 | ~0.4-0.5x (Meta: Q3 "2x+") | 1 | 1 | ~0.5x (better cooling) |
| CPU per core vs Quest 3 | ~0.7-0.75x (Meta: Q3 ~+33%) | 1 | 1 | ~0.75x |
| panel per eye | 1832 x 1920 | 2064 x 2208 | 1832 x 1920 | 1800 x 1920 |
| refresh | 60?/72/80/90/120 | 72/80/90/120 | 72/80/90/120 | 72/90 |
| RAM | 6 GB | 8 GB | 8 GB | 12 GB |
| passthrough / depth | grey, no depth sensor | colour + depth | colour, no depth | colour |

Exact lists of rates: read them at run time - `enumerate_rates`
(`xrEnumerateDisplayRefreshRatesFB`) is already fetched in `xr_init` **[code]**.

### 3.2 Frame budget for Classic

- Today on Quest 2 (no per-device defaults): the swapchain would be 2064x2208
  (the Android constant, clamped by `maxImageRect`), i.e. more pixels than the
  Q2 panel, on half the GPU: today's ~4-5 ms (Q3) becomes **~8-11 ms (Q2)**,
  split screen p90 ~17 ms - over every budget at 90/120 Hz, near it at 60
  content. **[inferred from 1.4 and 3.1]**
- With step 1 (array 1360x768 or 2040x1152, still two layers): pixel work
  /4-/9 -> roughly **1-1.5 ms Q3, 2-3 ms Q2** (vertex work, shadow map and
  fixed costs do not shrink; to be measured). With the quad, no per-eye screen
  draw. **Classic GPU becomes a non-issue on Quest 2.** **[inferred]**
- **CPU is the Quest 2 question.** The game thread and the GL worker
  (`gl_thread.c`: frame cost = the larger of the two) both must fit 16.7 ms.
  The only CPU figures on file are from another game (HOTD4: ~13 ms game + 12 ms
  GL, `gl_thread.c` header). **Measure on the Quest 3 first:** `[perf]`
  (`host_sdl.c`: "ms per frame: game X, second eye, submit, headset wait") and
  `glq_report` (GL worker busy) from one `scripts/vt3-repro.sh prize quest 170`
  in Classic; if game or GL worker > ~11-12 ms on Q3, Q2 (~0.72x per core) will
  miss 60 in busy frames. Step 3 (no multiview: no matrix pairs, simpler
  shaders) and GL-call trimming then matter more than the GPU.

### 3.3 VR mode on Quest 2 (unmeasured; starting points)

Eye size ~1440x1536 (0.8 of the panel), MSAA 0 (2x if measured affordable),
shadow 2048, aniso 2-4, sky Stadium (cheaper than Painted's shader), 72 or 90
Hz, foveation **once implemented** (`GL_QCOM_texture_foveated` on the eye array
`gl4es_multiview_array(g_eye_tex[0])` - **[general]**: Quest drivers expose it;
it is the only way to foveate a texture that is not a swapchain image), later
dynamic resolution (an eye-array size step on GPU-time pressure).

### 3.4 Recommended per-device defaults (first launch only)

| setting | Quest 3 | Quest 3S | Quest 2 | Quest Pro |
|---|---|---|---|---|
| eye size (VR) | 2064x2208 (today) | 1832x1920 | 1440x1536 | 1440x1536 |
| Classic picture k | 1.5 | 1.5 | 1.0-1.5 | 1.0-1.5 |
| msaa (VR) | 2 | 2 | 0 | 0 |
| msaa (Classic, small target) | 4 | 4 | 2 | 2 |
| VR shadow | 4096 | 4096 | 2048 | 2048 |
| aniso | 4 | 4 | 2 | 2 |
| refresh | 120 | 120 | 90 (Classic 120 if measured) / VR 72 | 90 |
| foveation (VR, once it works) | High | High | High | High |

How to pick them: at `xr_init`, `xrGetSystemProperties(instance, sys, ...)`
gives `systemName` (strings such as "Oculus Quest2", "Meta Quest 3" -
**[general]**, log it first) and the recommended/max image rects; on Android
also `__system_property_get("ro.product.model")` / `ro.product.device`
("Quest 2", "eureka" for Quest 3 - **[general]**, verify on devices). Apply them
inside `xr_settings_defaults` *before* `xr_settings_load` reads vr.cfg
(`xr_settings_set_game_defaults` already layers VT3's defaults this way
**[code]**): any key present in vr.cfg wins, and since `xr_settings_save`
writes every key, **an existing user's file keeps every value**. Two details:
(1) the special case in `xr_settings_load` that maps `2064x2280` to "native"
should map to the *device's* native size; (2) "Restore VR/Classic defaults"
should restore the device's defaults. Log `[xr] device <name>: defaults <set>`.

## 4. Other optimisations, ranked (gain vs effort)

| # | item | gain | effort | measure first? |
|---|---|---|---|---|
| 1 | Classic at picture size + quad layer (sections 2, 5) | very high (GPU /4-/9, sharper, steadier) | 1-3 days | baseline pair (below) |
| 2 | Foveation actually applied in VR (`GL_QCOM_texture_foveated` on the eye array) | high in VR (10-25% fragment **[general]**), needed for Q2 VR | 1-2 days | GPU_TIME pair VR, worn look at the edges |
| 3 | GPU performance level: `xrPerfSettingsSetPerformanceLevelEXT(GPU, SUSTAINED_LOW)` in Classic once cheap; keep CPU SUSTAINED_HIGH (`host_xr.c` sets only the CPU domain today **[code]**); listen for `XrEventDataPerfSettingsEXT` thermal warnings | battery/heat | hours | battery %/hour, `dumpsys thermalservice` |
| 4 | Render VR straight into a 2-layer **array swapchain** (`arraySize = 2`) instead of copying the eye array into two swapchains each frame (`xr_frame_end` blit) | ~0.3-0.6 ms + bandwidth in VR **[inferred]** | 1-2 days, gl4es array ownership | GPU_TIME |
| 5 | Per-device defaults (3.4) | Quest 2/3S/Pro usable | 0.5 day | none (log) |
| 6 | Start-up: the ~20 s is the board's own black boot, not shaders (guide ~496) - find the loop with `LINDBERGH_VT3_FLOWLOG=1` timestamps and fast-forward its timers/waits (HLE), or run boot frames unthrottled without presenting | up to ~15-20 s | 1-2 days | flow log + `[shaders]` lines with times |
| 7 | Shader/program caching: already done (`arbprog.c` program binaries in `../shadercache`; gl4es fpe/app caches, `[shaders]` stats) **[code]** - only check that a warm start shows 0 "built" | small | none | `[shaders]` on a 2nd start |
| 8 | Depth of field in Classic at picture size (falls out of #1); in VR keep `LINDBERGH_XR_TARGET_K` cap (exists, `scale_target`) | medium in VR | hours | GPU_TIME with K=1 / unset |
| 9 | Dynamic resolution in VR (step the eye-array size when GPU ms > budget) | high on Q2 VR | 3-5 days (re-allocation, live) | GPU_TIME distribution |
| 10 | CPU: per-draw stereo work in Classic (`lg_stereo_classify_draw`, `view_matrices`, clip set) skipped when `flat_all` | small-medium on GL worker | hours | `LINDBERGH_GLPROF=1`, `glq_report` |
| 11 | Crowd / shadow passes: crowd is cheap (stands +0.2 ms **[docs]**); shadow 4096 vs 2048 delta never measured | ? | - | GPU_TIME pair `immersive.shadow 4096/2048` |
| 12 | GPU page faults: still unexplained; on Quest 2 could become visible | ? | research | `LINDBERGH_GL_ROBUST=1` run (owed) |

Measurements to take (all unattended, existing switches, one run each):
`LINDBERGH_GPU_TIME=1` gives GPU ms per 300 frames; `[perf]` every 5 s gives
CPU split and fps; `LINDBERGH_XR_PROF=1` (only when the session runs, i.e. worn)
splits game GPU / eye copies / xrEndFrame; `ovrgpuprofiler -m` (worn or not)
gives GPU % busy, bin/fragment counts and the real clock level - use it to see
whether Classic is fill-bound (expected) and what level the GPU is held at.
Baseline pair before any change: `LINDBERGH_GPU_TIME=1
LINDBERGH_XR_FIXED_HEAD=1 scripts/vt3-repro.sh prize quest 170` with
`LINDBERGH_VT3_IMMERSIVE=0` and `=1`, same vr.cfg.

## 5. Step plan

Each step behind a switch, default off until proven, game working after each.

### Step 0 - baseline (no code)
The pair above (Classic / VR GPU ms, `[perf]`, `glq_report`). Plus the flicker
discriminator below (5.3). macOS: nothing.

### Step 1 - Classic eye array at picture size (`LINDBERGH_CLASSIC_PIC=<k>`, e.g. 1, 1.5)
In Classic only (`flat_all`), `host_xr.c xr_init` calls
`stereo_eye_size(1360k, 768k)` instead of the swapchain size; everything else
unchanged (multiview stays, two small layers; the projection layer and
`xo_draw_screen` stay - it samples the smaller texture; MSAA applies to it).
- macOS proves: nothing XR, but `LINDBERGH_STEREO=1` + the same eye size on
  the desktop exercises the stereo.c scaling at k = 1 / 1.5 (game shots of
  menus, match, DoF, split `splitreplay`, cross-fades vs the mono reference).
- Headset unattended: `GAME_SHOT` frames 2300-2310 + split + replay vs the
  baseline (picture identical apart from resolution), GPU_TIME, no new
  `[stereo]` warnings, `[stereo] on: ... x1.00, x1.00`.
- Owner worn: picture sharpness at Medium/Big, text, flicker.
- Optional 1b: mipmaps for the array (`TexStorage3D` levels > 1 +
  `glGenerateMipmap` on frame end, `GL_LINEAR_MIPMAP_LINEAR` in `smp_screen`)
  if k makes the screen minify.

### Step 2 - the quad layer (`LINDBERGH_CLASSIC_QUAD=1`, needs step 1)
A quad swapchain `1360k x 768k` (`mipCount 1`, sRGB as the eyes), per frame:
blit layer 0 of the eye array into it (one small blit), release, submit
`XrCompositionLayerQuad` (space `local`, pose `(0,0,-d)`, size `2hw x 2hh`,
no alpha) as layer 0. The projection layer is submitted only when the panel /
gun / laser / stats are shown, cleared to transparent with
`XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT`; the panel as its own quad
(2b). Frame hold = skip the blit. Splash quads unchanged (they go on top).
- macOS: nothing (no XR); unit-test the pose/size maths if wanted.
- Headset unattended: the session does not run unworn, so **layers cannot be
  verified unattended**; check logs (`[xr] classic quad 2040x1152 ...`,
  `xrEndFrame` result 0 when it does run), `GAME_SHOT` unchanged.
- Owner worn (one short run): screen position/size same as before; steady when
  turning the head; panel and laser usable; Recentre; Screen size row; text.

### Step 2c - GPU level and per-device defaults
GPU `SUSTAINED_LOW` in Classic with the quad (`LINDBERGH_GPU_LEVEL=` to
override); device defaults (3.4) with the device log line. Unattended: log
lines; `ovrgpuprofiler` clock.

### Step 3 (optional) - mono, no multiview, in Classic
`LINDBERGH_MULTIVIEW=0` + the `g_wide`-style "no second eye" in Classic,
rendering into the quad image directly. Only if step 0/2 measurements show the
second small layer or the per-draw multiview work still costs (CPU on Quest 2).
Conflicts with live-switch Option A; needs the shader cache rebuilt. macOS can
prove the non-multiview stereo path at k=1 with `LINDBERGH_STEREO=1`.

### Step 4 - VR-side items (foveation, array swapchain, dynamic resolution)
Independent of Classic; GPU_TIME pairs + owner worn.

### 5.3 The texture flicker in Classic: will the quad fix it?

**Likely partly or mostly, if the flicker is head-motion shimmer; not at all if
it is in the game's frames.** Today's screen is a 2064x2208 texture minified
~1.5x horizontally and ~2.5x vertically into the eye with one bilinear tap and
no mipmaps (`xo_draw_screen`, `smp_screen` GL_LINEAR, 1-level array) **[code]**;
the eye's sampling grid moves across the picture with every tiny head movement,
so fine detail (court lines, net, board text, crowd - made extra crisp by the
2.875x vertical super-sampling, aniso 4 and LOD bias -1 choosing finer mips)
aliases differently each frame = sparkle/crawl. That happens only worn (a
fixed head samples identically every frame). With step 1 the picture is ~1:1
with the eye pixels (little minification), and with step 2 the compositor
samples it once with its own (optionally super-sampled) filter: this kind of
flicker should go.

Flicker that **is in the game's picture itself** - MSAA implicit-resolve
ordering around the depth-of-field copies, decal z-fighting without the VR
decal offset, LOD-bias shimmer in the game's own sampling, the pane prelude -
would show the same on the quad. To tell them apart without duplicating the
other worker: `LINDBERGH_XR_FIXED_HEAD=1 LINDBERGH_GAME_SHOT=2400,1,1,2460`
(the game's picture, before the host's screen draw) and difference consecutive
frames in a still camera moment: changes there = game-side (the other worker's
suspects; quad does not help); no change there but flicker worn = host
sampling (quad / step 1 fixes it; a quick worn test is step 1 alone, or 1b
mipmaps). The current flicker work is therefore not wasted: its game-side
fixes stay needed with the quad; its host-side part (if any) is what step 1-2
replaces.
