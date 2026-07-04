# World Forge Crafting Plan — Implementation Reporting

Tracks execution of [docs/WORLD_FORGE_CRAFTING_PLAN.md](docs/WORLD_FORGE_CRAFTING_PLAN.md)
against its merged 12-phase roadmap (plan section 8). This file is the
running log for the self-review loop: pick one step, implement it, test it,
review it, log it here, then take the next step. Newest entry at the top.

## Roadmap status

- [ ] Phase 1 — Professional editing controls
- [~] Phase 2 — Data-driven shape/component library *(in progress: material/part foundation landed; SHAPES/COMPONENTS array conversion still open)*
- [ ] Phase 3 — Part scale + Workshop documents
- [ ] Phase 4 — Prefab & nested-blueprint workflow
- [ ] Phase 5 — Kinetics
- [ ] Phase 6 — Thermal + casting
- [ ] Phase 7 — Assembly & construction stages
- [ ] Phase 8 — Worker & logistics layout
- [ ] Phase 9 — Flexibles + power network
- [ ] Phase 10 — Cutaway & visibility editor; validation
- [ ] Phase 11 — Runtime/export pipeline
- [ ] Phase 12 — Automation-light + polish

## Sequencing note

The plan's own section 11 lists Phase 1 (editing controls) as the first
immediate step, with the data-model refactor running "while that lands."
Editing controls are polish on the *existing* structure editor and don't
unlock any of the newly-requested crafting/kinetics/thermal features, so
this loop starts with the Phase 2 foundation instead (`MaterialProperties` +
`PartProfile`) — the plan itself calls this refactor "what everything else
stands on." Phase 1 stays queued and will be picked up once the crafting
foundation has enough surface area to make editing-control gaps (gizmos,
drag-select) actually felt.

## Change log (newest first)

<!-- Newest entries go directly below this line. -->

### Xbox controller support for World Forge — 2026-07-04

**Not a crafting-plan phase step** — a direct user request to build maps
with an Xbox controller. Scoped after asking which of three architectures
they actually wanted (controller-only paired to the PC; phone-as-wireless-
bridge; or full remote control from the phone screen). They chose the
simplest: pair the controller straight to the PC, no phone involved.

**Design:** Godot's `Input` singleton already sees a Bluetooth/USB-paired
Xbox controller as a normal joypad — no new networking, drivers, or a
"Godot mobile app" needed. World Forge gained a `_process()` loop that
polls it every frame while the editor tab is open.

- **Camera:** left stick pans the focus point (camera-relative, matching
  mouse-drag pan's math), right stick orbits (yaw/pitch), triggers zoom -
  mirroring the existing mouse-drag/wheel camera controls exactly, just on
  a different input source.
- **Tools:** A = place/select (whichever tool is active) at a reticle
  aimed at the viewport center; B = erase at the reticle; X = rotate brush/
  selection; Y = cycle which palette tab is active (Block → Component →
  Marker → Part → back to Block); LB/RB = step the selection within the
  current tab; D-pad up/down = structure layer, left/right = fine layer
  (Step 8's sub-cell height, previously only reachable via a spinbox);
  Start = undo, Back = redo.
- **Reticle:** there's no mouse cursor to hover with when playing entirely
  by controller, so a small "+" `Label` is centered over the viewport
  (visible only while a joypad is connected) and A/B aim from there instead
  of a hover position.
- **Hardware state kept out of the testable logic:** `_read_joypad_state()`
  is the only place that touches the `Input` singleton; everything else
  (`_apply_gamepad_camera`, `_apply_gamepad_actions`, button-cycling) takes
  a plain Dictionary and is fully testable with a hand-built one — the same
  "thin hardware shell around a pure function" split Step 8 used for
  `_mouse_to_fine_cell`/`_fine_cell_for_point`.

**Files changed:**
- `addons/world_forge/world_forge_main.gd` — `_process()`,
  `_active_joypad_device()`, `_read_joypad_state()`,
  `_apply_gamepad_frame/_camera/_actions()`, `_gamepad_button_just_pressed()`
  (manual "just pressed" edge-detection against a per-frame previous-state
  snapshot, since discrete actions must fire once per press, not once per
  frame held), `_gamepad_place_or_select()`/`_gamepad_erase()` (reticle-
  aimed equivalents of a mouse click), `_cycle_place_kind()`/
  `_cycle_palette_selection()`/`_cycle_list_selection()`. `_build_viewport_panel()`
  restructured to wrap the viewport in a plain `Control` "stack" so the
  reticle can overlay it as a sibling (a `VBoxContainer` would have stacked
  it below instead).
- `tests/test_world_forge.gd` — 8 new tests covering camera math (orbit/
  pan/zoom-with-clamp/deadzone), edge-triggered vs. held-button behavior,
  D-pad layer stepping, Y cycling through every palette tab, LB/RB stepping
  the selection, and a full A-places/B-erases round trip.

**Tests:** `test_run(suite="world_forge")` → 57/57 passed. Full
`test_run()` (all 4 suites) → 71/71 passed, confirmed stable across two
consecutive clean runs (this session's established practice after Step 8's
transient mid-save failures). Also launched the actual game via
`project_run` to confirm no runtime errors outside the test harness - clean
(the only errors in that response were explicitly flagged
`recent_errors_may_predate_run: true`, retained echoes from this session's
own earlier debug-test runs, not live).

**Review notes — three real bugs found, two of them revealing a genuine
engine-behavior gap in how this project's tests work, not just typos:**

1. **`assert_lt()` doesn't exist** in this project's `McpTestSuite` (only
   `assert_eq/ne/true/false/gt/contains/has_key/is_error` - already noted
   in project memory, re-confirmed here). Fixed by using
   `assert_true(a < b, ...)`.

2. **Camera raycasts silently fail when a node isn't inside a live,
   processing `SceneTree`.** Every test in this file up to this point that
   exercised placement did so by calling `_place_at`/`_place_part_at_fine_cell`
   with a pre-resolved cell, or tested the post-raycast math
   (`_fine_cell_for_point`) directly - **none had ever actually called
   `_mouse_to_cell`/`_mouse_to_fine_cell` with a real screen coordinate**.
   The gamepad A/B test is the first to do so (aiming from the reticle),
   and it silently returned `null` every time. Probed directly: confirmed
   `Camera3D.project_ray_origin`/`project_ray_normal` return zeroed/invalid
   results outside a live tree ("Camera is not inside scene" once actually
   surfaced as a real engine error during a later live run). Fixed by
   parenting the test's editor instance under
   `EditorInterface.get_edited_scene_root()` for the duration of that one
   test - the same pattern this test suite's own `_add_control()` helper
   already uses elsewhere, just not yet for a raycast. This is a real,
   reusable finding for any future test that needs a working camera
   raycast, not specific to gamepads.

3. **Setting `SpinBox.value` doesn't reliably fire `value_changed`
   synchronously outside a live tree either** - the D-pad layer-stepping
   code originally set `_layer_spin.value = _active_layer + 1` and relied
   on the existing `value_changed` callback to update `_active_layer`.
   Probed directly: the SpinBox's own `.value` updated correctly, but
   `_active_layer` never did. Rather than route the gamepad path through
   the SceneTree-insertion workaround from #2, treated this as a design
   smell worth fixing at the source: `_active_layer`/`_fine_layer` are the
   actual state, the SpinBox is a *display* of it, so the gamepad code now
   updates them directly and pushes the display via `set_value_no_signal`
   instead of routing through a signal round-trip to get back to state it
   already had. Simpler and more correct regardless of the test
   environment quirk that surfaced it.

Also caught a bug in one of my *own tests*, not the feature: the LB/RB
cycling test set `_place_kind`/`_selected_part_id` by direct property
assignment (bypassing the palette UI), so the `ItemList`'s own selection
was never actually synced - `_cycle_list_selection` correctly reads the
*ItemList's* selection to compute its next index, and with nothing
selected there it started from a phantom index 0 instead of wherever the
test's chosen part actually lived in the sorted list. Fixed by explicitly
selecting the starting item in the list before testing the cycle, matching
how a real click would have left it.

**Known gaps / deliberately deferred:**
- Paste/move/staged-blueprint-placement are mouse-only; A only covers
  place/select/connected-select.
- No visual/haptic feedback for *which* palette item LB/RB just landed on
  beyond the existing status-bar text - a controller-only player can't see
  the palette list highlight change without glancing away from the 3D view.
- Single controller only by design (first connected device); multiple
  connected gamepads don't get separate camera/tool state.
- No rumble feedback on invalid actions (e.g., trying to erase where
  nothing exists).

**Status:** done.

### Step 9 — `PartKineticsCompiler`: the start of Phase 5 (plan section 9) — 2026-07-04

**Scope:** the first real kinetics slice — compiling placed parts and their
recorded connections into rigid-body groups and physics joints, following
the plan's core rule: "weld-merge is the golden rule; joints only where
something actually moves."

**A prerequisite gap closed first:** `_place_part_at_fine_cell` recorded
`"joints": []` unconditionally since Step 3 introduced the field — nothing
had ever actually populated it, even after Step 7 wired real socket
snapping into placement. Fixed: when `PartSnapResolver.find_snap` finds a
match, the connection (`target_key`, `target_socket`, `own_socket`) is now
recorded on the placed part. The snap that happens at placement time IS
the joint; the compiler shouldn't have to re-derive it from proximity
after the fact.

**Files added:**
- `addons/world_forge/model/part_kinetics_compiler.gd` — `PartKineticsCompiler.
  compile(document, part_lookup, material_lookup)`. Three passes: (1) walk
  every placed part's recorded joints, resolve both sockets to world space
  via `PartSnapResolver.world_sockets`, find their `matching_kinds`, and
  **union-find** any pair sharing "weld" into one group while collecting
  every other shared kind as a pending cross-group connection; (2)
  finalize groups (member keys + summed mass via
  `PartProfile.resolved_mass_kg`) now that every weld union has settled;
  (3) express each pending connection in terms of final group ids,
  dropping any that landed inside the same welded group, deduplicating,
  and splitting into `joints` (hinge/bearing/slider — real Godot physics
  joints) vs. `logical_connections` (power_shaft/item_port/heat_contact/
  rope_anchor — later phases' concern: power network, thermal graph, rope).
  Output is plain data, not yet actual `RigidBody3D`/`Joint3D` nodes, so
  the part worth getting right (grouping/classification) is testable
  without a live physics server.
- `addons/world_forge/model/part_snap_resolver.gd` — renamed `_matching_kinds`
  to public `matching_kinds` so the compiler can reuse the exact same
  kind-compatibility logic rather than re-implementing (and risking
  drifting from) it — the coaxial-vs-opposing distinction from Step 6 only
  needs to be correct in one place.
- `tests/test_world_forge.gd` — 5 new tests. Two place parts through the
  *real* editor pipeline (`_place_at`/`_place_part_at_fine_cell`, not
  hand-built joint dictionaries) to prove the whole chain end-to-end: two
  rods welded end-to-end compile to one group with mass = both rods summed
  and zero physics joints; a wheel mounted on an axle (bearing-only match)
  stays as two groups joined by exactly one "bearing" joint. Plus an
  isolated-part sanity check and a dedup test for a connection recorded
  symmetrically on both sides.

**Tests:** `test_run(suite="world_forge")` → 49/49 passed, all on the
first try (no bugs found this round — the union-find/classification design
held up against real registry data). Full `test_run()` (all 4 suites) →
63/63 passed. Given Step 8's transient mid-save failures, ran the full
suite twice in a row after this step to confirm stability before trusting
the green result — both runs matched.

**Review notes — a real, worth-flagging modeling gap, not a bug:**
- A part connection's physics behavior (weld vs. hinge vs. bearing vs.
  slider) is currently *entirely* determined by whichever kinds the two
  sockets happen to share — there's no way for a user to say "connect
  these two rod ends with a hinge instead of a weld" when both kinds are
  available on both sockets. Rod-to-rod always welds today (their ends
  share weld+hinge+power_shaft, and "weld" wins unconditionally whenever
  it's present in the matching set). This is fine for the parts modeled so
  far — nothing currently needs a hinge between two straight rod ends —
  but it will need addressing (most likely: let a placement's `joints`
  entry record *which* kind was chosen, not just which sockets connected,
  with weld as the default when unspecified) before a hinge-based
  mechanism between two multi-kind sockets is buildable.

**Known gaps / deliberately deferred:**
- No `build_scene()` layer yet — compiled output is data
  (groups/joints/logical_connections), not actual `RigidBody3D`/
  `HingeJoint3D`/etc. nodes. That's the natural next slice: turning this
  data into a real, physically-simulated scene.
- `logical_connections` are recorded but nothing consumes them yet
  (power network is Phase 9, thermal graph is Phase 6 — both later).
- No joint break-strength (material `strength` field exists on
  `MaterialProperties` since Step 1 but isn't read here yet) — a real
  catapult firing hard enough to snap a joint needs it.
- No overlap/footprint validation for parts (flagged since Step 5) — the
  compiler will happily group parts that visually overlap.

**Status:** done.

**Next step:** `build_scene()` — turn a compiled result into actual
`RigidBody3D` groups (one `CollisionShape3D` + mesh per member part,
positioned relative to the group's own origin) and `HingeJoint3D`/
`SliderJoint3D` nodes wired to the two connected bodies at the recorded
world position/axis. That's the point where a welded, wheel-mounted
assembly becomes something that can actually be dropped into a running
scene and roll.

### Step 8 — fine-grid Workshop viewport/picking — 2026-07-04

**Scope:** the placement-precision gap flagged consistently since Step 5 —
mouse clicks resolved only to whole 1m structure cells, so parts (which
live on a 0.125m fine grid) could only ever land on coarse 8x-multiples of
that grid. This step gives part placement its own fine-grid raycast.

**Files changed:**
- `addons/world_forge/world_forge_main.gd` — added `_mouse_to_fine_cell()`
  (mirrors `_mouse_to_cell` but raycasts against a plane at
  `_active_layer + _fine_layer * FINE_CELL_SIZE` and quantizes X/Z to
  `FINE_CELL_SIZE` instead of whole units), with the actual quantization
  math split into a pure `_fine_cell_for_point(point: Vector3)` helper so
  it's directly testable without a real camera/viewport raycast. Added a
  `_fine_layer` state var (0..7, the sub-cell height within the current
  structure layer) and a paired "Fine" `SpinBox` in the header next to the
  existing structure-layer control. `_on_viewport_input` now routes
  part-mode clicks through the fine-grid raycast instead of the coarse one
  used for blocks/components/markers; the hover preview does the same, so
  the ghost part shown before clicking already reflects the true fine
  position (including any socket snap). Added a small local fine-grid
  visual overlay (a fixed-size patch centered on the cursor, not a
  world-sized grid — at fine spacing that would be 8x8 as many lines per
  axis as the existing coarse grid) so the sub-cell resolution is visible,
  not just active.
- `tests/test_world_forge.gd` — a test for `_fine_cell_for_point` in
  isolation (layer/fine-layer → Y, floor-quantized X/Z, matching
  `_mouse_to_cell`'s existing floor convention), and — the one that
  actually proves the point of this step — a test placing a part at fine
  cell `(4, 0, 0)` (world x=0.5, a position with **no whole-structure-cell
  equivalent at all**) and confirming it lands there exactly. Every prior
  test could only ever prove coarse, 8-aligned placement.

**A deliberate compatibility decision:** `_place_at`'s "part" branch still
accepts a coarse structure cell and converts internally, unchanged from
Steps 5–7 — so every existing test, macro, or future scripted command that
calls `_place_at` directly keeps working without modification. Genuine
fine-grid placement (real mouse clicks, and anything that wants sub-cell
precision) goes through the new `_place_part_at_fine_cell()` directly,
which `_place_at` now also delegates to internally. This is the same
"don't break the existing contract, add a new path for the new capability"
pattern as `set_placed_part` vs. `set_placed_part_at` from Step 7.

**Tests:** `test_run(suite="world_forge")` → all passing. Full
`test_run()` (all 4 suites) → 59/59 passed, no regressions.

**Review notes:** mid-implementation, an editor test run reported the
whole suite failing to compile (`cannot instantiate — abstract or
broken`), then a batch of specific assertion failures, then fully green on
a clean re-run with no code changes in between — consistent with catching
the project mid-save rather than a real defect (this codebase sees
frequent saves while the plugin is open in the live editor). Treated
`test_run` results as suspect until they were reproducible twice in a row
rather than accepting a red result - or a green one - from a single
sample; re-ran after rescanning until results stabilized before trusting
them either way.

**Known gaps / deliberately deferred:**
- The fine-grid overlay is a fixed local patch, not (yet) rendered with
  socket/joint indicators the way a real Workshop viewport eventually
  wants (highlighting which nearby socket a candidate would connect to,
  not just where it would sit).
- No keyboard shortcut or scroll-wheel control for `_fine_layer` yet —
  only the header SpinBox.

**Status:** done.

**Next step:** with placement precision, snapping, and now genuine
fine-grid picking all in place, the data/interaction foundation for the
Workshop is functionally complete for a single part at a time. The next
substantial slice is either (a) multi-part selection/movement at the fine
scale (mirroring the structure-scale copy/move/duplicate tools), or (b)
starting Phase 5 (kinetics) now that parts can be reliably placed and
joined — compiling a welded group of placed parts into rigid bodies with
physics joints at the snapped socket connections.

### Step 7 — wire `PartSnapResolver` into real placement — 2026-07-04

**Scope:** resolve the storage-model tension Step 6 deliberately left open
(continuous socket-aligned positions vs. `placed_parts`' quantized
fine-grid-cell keys) and actually call the resolver from `_place_at`, so
placing a part near a compatible socket snaps for real, not just in a unit
test calling the resolver directly.

**The storage decision:** `placed_parts` stays keyed by a fine-grid cell
(now explicitly a spatial *bucket*, computed by rounding rather than
truncating), but a part's dictionary gains an optional `pos_exact: [x,y,z]`
float field that is authoritative when present. This was chosen over
snapping the position onto the fine grid after alignment (rounding a
socket-aligned position back onto a 0.125m grid) because not every
authored socket offset is grid-aligned (`axle`'s ends sit at ±0.3, and
0.3/0.125 isn't an integer) — rounding would silently reintroduce the exact
misalignment socket-snapping exists to remove, undermining the plan's
stated goal of authentic-looking joints over convenience.

**Files changed:**
- `addons/world_forge/model/forge_document.gd` — added
  `cell_for_position()` (static, rounds a continuous position to its
  nearest fine-grid bucket cell), `set_placed_part_at()` (places at a
  continuous position, storing both the bucket cell and `pos_exact`,
  returns the bucket cell used), and `placed_part_world_position()`
  (static — resolves a placed part's dictionary to its actual render/query
  position: `pos_exact` when present, else the Step 5 quantized-cell
  behavior unchanged). The original `set_placed_part(cell, ...)` is
  untouched, so Step 5's tests and any programmatic caller that doesn't
  need snapping keep working exactly as before.
- `addons/world_forge/model/part_snap_resolver.gd` — `find_snap` now reads
  a placed part's position via `ForgeDocument.placed_part_world_position()`
  instead of reconstructing it from the dictionary key alone. Without this
  fix, a part that was itself precisely snapped into place would report
  its *bucket* position (off by up to ~0.06m) to anything trying to snap
  against it next, silently degrading precision one link into any chain of
  more than two connected parts.
- `addons/world_forge/world_forge_main.gd` — `_place_at`'s `"part"` branch
  now calls `PartSnapResolver.find_snap` with the raw quantized click
  position as the candidate position; if a compatible socket is found
  within tolerance, the part is stored at the snapped position via
  `set_placed_part_at` instead of the raw one, and the status bar reports
  which sockets connected (`"Part snapped: end_a -> end_b"`) instead of
  the generic placement message. The hover preview (`_update_hover`) does
  the same lookup so the ghost part shown before clicking already reflects
  where it would actually land. `_add_placed_part_visual` now renders via
  `placed_part_world_position()` instead of only ever reading `pos`.

**Tests:** `test_run(suite="world_forge")` → 38/38 passed (5 new: document
storage round-trip for `pos_exact`, the fallback path when it's absent, the
real `_place_at` UI path reporting a snap, and undo/redo correctly carrying
`pos_exact` through the existing snapshot mechanism rather than assuming it
does because the plumbing looks right). Full `test_run()` (all 4 suites) →
52/52 passed, no regressions.

**Review notes — an honest limitation found while designing the placement
test, not a bug exactly, but worth being direct about:**
- The click path this step wires into still only quantizes to *whole
  structure cells* (Step 5's known limitation, unresolved by this step).
  Structure cells are 1.0m apart, but the snap tolerance is 0.3m (tuned
  "generous for the fine grid's 0.125m cell" per Step 6's own comment).
  Working through concrete numbers: a `steel_rod` is exactly 1.0m long, so
  clicking one structure cell further along an axis happens to align its
  socket exactly — a happy coincidence, not a general solution. Trying the
  same thing with the 0.6m `axle` (ends at ±0.3) shows the gap: a
  same-length click offset misses by 0.4m, outside tolerance. In practice,
  **snapping through today's UI reliably helps only for parts whose length
  happens to divide evenly into whole structure-cell steps** (rods,
  wood_beam/wood_plank at exactly 1.0m); anything else needs either an
  exact-by-luck click or won't snap at all yet. This isn't papered over:
  the test added for this step deliberately uses the rod case (which
  works) and documents in its own comment why it can't yet demonstrate a
  nontrivial position correction through the real UI path — that proof
  already exists at the unit level in Step 6's tests, which use genuinely
  off-grid candidate positions. The real fix is fine-grid (0.125m) click
  picking, already flagged as the outstanding follow-up in Steps 5 and 6.

**Known gaps / deliberately deferred:**
- Fine-grid click picking (see above) — the actual blocker to snapping
  being broadly useful, not just correct.
- No visual indication in the hover preview of *which* socket pair would
  connect, or a rejection reason when nothing's in range (components get
  a red/green tint; parts don't yet).
- No overlap/collision validation for parts (a component's `can_place`
  equivalent doesn't exist for parts) — two parts can currently be placed
  fully overlapping with no warning.

**Status:** done.

**Next step:** fine-grid Workshop viewport/picking is the natural next
large slice — it's what the last three steps (placement, snapping,
precise-position storage) have all been building toward and is the one
remaining piece standing between "the data model and pipeline are correct"
and "you can actually build a chair by clicking around." Alternatively,
part overlap validation (mirroring `ComponentSnapResolver.can_place`) is a
smaller, faster win in the same area.

### Step 6 — `PartSnapResolver`: part-to-part socket matching (plan section 5) — 2026-07-04

**Scope:** the thing that actually makes the Workshop useful — parts can be
placed (Step 5), but couldn't yet be *joined* into an assembly. This is the
part-scale generalization of `ComponentSnapResolver`.

**Files added:**
- `addons/world_forge/model/part_snap_resolver.gd` — `PartSnapResolver`.
  `world_sockets(part, position, rotation_steps)` computes every socket's
  world-space position/axis under a yaw rotation. `find_snap(document,
  placed_lookup, candidate, candidate_position, candidate_rotation_steps,
  tolerance)` searches every already-placed part's sockets for the nearest
  compatible one within tolerance and returns the position that aligns
  them. `placed_lookup` is a plain `Callable` (not a `PartRegistry` type
  dependency) so the resolver stays decoupled from the registry, the same
  way `ComponentSnapResolver` takes plain `Array`/`Dictionary` rather than
  editor types.
  - **Deliberately does not solve full 3D auto-orientation** — only
    proposes a position; the candidate keeps its current yaw. Aligning two
    arbitrary socket axes needs a real orientation solve, which is
    meaningfully harder and needs a Workshop viewport with live feedback to
    make legible — explicitly deferred, not attempted halfway.
- `tests/test_world_forge.gd` — 9 new tests, several built specifically to
  probe the axis logic against *real* Step 1 socket data rather than only
  synthetic fixtures (synthetic-only tests would have missed both bugs
  below, since neither existing hand-authored part combination had been
  traced through by hand before this step).

**Tests:** `test_run(suite="world_forge")` → 34/34 passed. Full
`test_run()` (all 4 suites) → 48/48 passed, no regressions.

**Review notes — two real design bugs found by tracing concrete scenarios
through the code before trusting it, plus one bug in my own test:**

1. **Coaxial vs. opposing axes.** The first version required all matching
   sockets' axes to point *away* from each other (correct for a weld: two
   rods extend in a line, tips facing apart). Tracing a wheel-mounting-on-
   an-axle scenario by hand before writing the test revealed this axis
   rule *rejects every valid bearing connection*: a wheel's bore and the
   axle end it slides onto point the *same* way (the wheel caps the shaft,
   it doesn't extend it). Fixed by adding a `COAXIAL_KINDS` list that flips
   the rule to "parallel, either direction" for rotation-mount kinds.

2. **The coaxial list needed to be checked per matched kind, not per whole
   socket.** My first fix put both `"bearing"` and `"power_shaft"` in
   `COAXIAL_KINDS`, reasoning "both are rotation concepts." But a
   steel_rod's end carries `weld + hinge + power_shaft` together, and
   checking "does this socket have *any* coaxial kind" would let two rod
   ends match same-direction (overlapping) placements too, via the shared
   `power_shaft` kind — wrong, because a driveshaft made of coupled rod
   segments still extends in a straight line tip-to-tip, exactly like a
   weld; it doesn't stack two rods facing the same way. Fixed by rewriting
   the kind-match step (`_matching_kinds`) to return the *specific* shared
   kinds between two sockets (offered by both, accepted by both) and
   deciding coaxial-vs-opposing per matched kind rather than per whole
   socket, then removing `power_shaft` from `COAXIAL_KINDS` (only
   `"bearing"` genuinely means "mounts around a shared shaft"; the
   dedicated `test_part_snap_resolver_rejects_same_direction_rod_ends`
   test exists specifically to keep this fixed).

3. **My own test had a geometry bug, similar in spirit to Step 5's
   splicing mistake but a design error rather than an editing mechanics
   error.** The first version of the same-direction-rejection test placed
   a candidate rod exactly one rod-length away from the placed rod,
   intending to test the two `end_b` sockets facing the same way. But a
   rod is symmetric and 1m long — offsetting by exactly that length also
   puts the candidate's *other* end (`end_a`) in exact opposing alignment
   with the placed rod's `end_b`, so `find_snap` correctly found that
   *better, valid* match instead of failing the way the test expected,
   and the test failed with `test_run` reporting 33/34 (a real, specific
   assertion failure this time, not a compile error — a much easier signal
   to read than Step 5's "whole file broken"). Fixed by overlapping the
   candidate exactly on top of the placed rod instead (position 0,0,0),
   which puts both ends' same-direction pairs in range while keeping any
   opposing pair a full rod-length away and safely outside tolerance.

**Known gaps / deliberately deferred:**
- No orientation solve (position-only snapping) - noted above and in the
  file's own module doc comment.
- Not yet wired into `world_forge_main.gd`'s placement UI. Doing so needs
  deciding how a continuous, socket-aligned position coexists with
  `placed_parts`' current *quantized fine-grid-cell* storage key (Step 5's
  `set_placed_part`/`get_placed_part` key on integer `Vector3i` cells, but
  a real socket snap will essentially never land exactly on a fine-grid
  cell). Storing a sub-cell offset alongside the cell, or moving to a
  continuous position field with the cell used only for spatial-hash
  bucketing, are both reasonable directions - not resolved here since it's
  a real storage-model decision, not something to bolt on quickly at the
  end of a step.
- `COAXIAL_KINDS` currently has exactly one entry (`"bearing"`). Future
  socket kinds should be evaluated the same way `power_shaft` was here —
  by tracing one concrete real placement by hand — before assuming they
  belong on either list.

**Status:** done.

**Next step:** resolve the `placed_parts` continuous-position-vs-quantized-
cell storage question above, then wire `PartSnapResolver` into
`_place_at`'s `"part"` branch so placement actually uses it (falling back
to the current whole-cell quantization when nothing is in range to snap
to) — that's what turns "parts can be placed near each other" into "parts
can be assembled into a chair."

### Step 5 — Parts palette, placement tool, and rendering wired into the editor — 2026-07-04

**Scope:** close the loop Step 3 left open ("no palette, no placement tool,
no rendering wired up yet") — parts are now genuinely placeable and visible
in World Forge, not just loadable data.

**Files changed:**
- `addons/world_forge/model/forge_document.gd` — added `const FINE_CELL_SIZE
  := 0.125` as the canonical world-unit size of one Workshop fine-grid cell
  (referenced from `world_forge_main.gd`'s rendering/placement code so the
  grid size isn't duplicated as an untraceable magic number across files).
- `addons/world_forge/model/part_profile.gd` — added a `color` field
  (mirrors `FunctionalComponentDefinition.color` from Step 2 — same reason:
  placeholder render tint until real per-material textures exist).
- `data/world_forge/parts/*.tres` — every part now has a `color` matching
  its material's real-world look (steel gray, oak brown, rope tan, firebrick
  reddish-brown).
- `addons/world_forge/world_forge_main.gd` — added a persistent
  `_part_registry`/`_material_registry` (unlike the Step 2 registries,
  these stay alive rather than being freed after startup, since rendering
  needs them on every `_refresh_world()` call, not just once); a `_parts`
  palette catalog and a "Parts" tab in the palette panel
  (`_on_part_selected`); a `"part"` branch in both `_place_at` (real
  placement) and `_update_hover` (ghost preview); and
  `_add_placed_part_visual()`, called from `_refresh_world()` for every
  entry in `_document.placed_parts`, using `PartGeometryFactory`.
  **Placement is quantized to whole structure-cell multiples of the fine
  grid for now** (`cell * FINE_CELLS_PER_UNIT`, i.e. 8) — reusing the
  existing whole-cell raycast (`_mouse_to_cell`) exactly as-is rather than
  building a new fine-grid picking system. This is a deliberate, explicitly
  time-boxed simplification: it makes the full pipeline (click → place →
  save → reload → render) real and testable today, at the cost of not yet
  supporting sub-cell precision placement — that needs a dedicated
  Workshop-viewport camera/picking setup, which is bigger, separate work.
- `tests/test_world_forge.gd` — 2 new tests: the Parts palette lists all 8
  starter parts (both in the `_parts` data array and the real `ItemList`
  control), and placing a part via the real `_place_at()` call (not a
  synthetic document mutation) lands at the *fine* cell (verifying it is
  **not** at the raw click cell — the easy way to get this silently wrong
  is to store the un-multiplied cell), then confirms the render pipeline
  fired automatically via the existing `changed` signal wiring (content
  root gains a child with no explicit `_refresh_world()` call needed,
  exactly like blocks/components/markers already do).

**Tests:** `test_run(suite="world_forge")` → 27/27 passed. Full
`test_run()` (all 4 suites) → 41/41 passed, no regressions.

**Review notes (a self-inflicted bug this time, not a Godot-format trap):**
- My own `Edit` tool call for the two new tests matched an anchor string
  that existed in the *middle* of the pre-existing
  `test_part_geometry_factory_builds_distinct_geometry_kinds` (the anchor
  text — the end of Step 4's vessel-orientation check — wasn't actually the
  end of that function; the function continued afterward with sphere/custom
  checks). The edit landed correctly in isolation but **split one test
  function into three broken pieces**, leaving two bare `var sphere_part
  = ...` / `var custom_part = ...` blocks referencing `material`, a
  variable declared at the top of the now-orphaned original function.
  Caught immediately: `test_run` returned `"load_errors": ["test_world_forge.gd
  (cannot instantiate — abstract or broken)"]` with 0 tests run at all
  (a compile failure fails the whole suite, not just one test — a much
  louder signal than a single red test). Read the *live* error via
  `logs_read` (not the stale buffer noise mixed in with it — by now a
  familiar pattern, see Steps 1-2) to find the exact two line numbers,
  then re-read the surrounding ~70 lines to see the real structure before
  fixing it: moved the sphere/custom-part checks back to the end of the
  original test function, then placed both new Step 5 tests cleanly after
  it. Re-ran and confirmed all 27 tests pass with no function split.
  Lesson for future edits in this file: when appending a new test after an
  existing one, verify the anchor text is actually at the *end* of a
  function (e.g. immediately followed by a blank line before the next
  `func`), not just text that happens to be unique.
- Also forgot to create a tracking task for this step before starting it
  (tasks #17-20 exist for Steps 1-4; this step ran to completion before I
  noticed #21 was missing). Added it retroactively rather than leaving the
  task list inaccurate.

**Known gaps / deliberately deferred:**
- Placement precision is whole-cell-quantized (see above) — a real
  Workshop viewport with fine-grid picking is the natural follow-up once
  socket-snap placement (mirroring `ComponentSnapResolver` but for metric
  part sockets instead of cell-aligned component ports) is designed.
- No undo-visible feedback for parts beyond the generic `_transact` label
  ("Place part") — no per-part status like components get
  ("needs a compatible port" / "footprint occupied"), because there's no
  socket-snap or overlap validation for parts yet.
- Rotation is yaw-only (`rotation_steps`, matching components), not the
  arbitrary orientation joints will eventually need (Phase 5 kinetics).

**Status:** done.

**Next step:** part-to-part socket snapping (the part-scale equivalent of
`ComponentSnapResolver`) — without it, parts can be placed but not
meaningfully joined into an assembly, which is the actual point of the
Workshop ("build a chair from beams"). This is the natural next slice
before investing in fine-grid picking precision, since snapping is what
placement precision would be *for*.

### Step 4 — per-part `long_axis` resolves the vessel-orientation gap — 2026-07-04

**Scope:** close out the design gap Step 3 flagged rather than let it sit —
the crucible (a vessel with a real "stands upright" orientation) didn't
match the generic cylinder helper's Z-axis assumption (which is correct for
rod/axle/wheel-like parts).

**Files changed:**
- `addons/world_forge/model/part_profile.gd` — added `long_axis := Vector3(0,
  0, 1)` (default preserves every existing part's behavior unchanged).
  `occupancy_for_cylinder` now takes a `long_axis` param and puts `height`
  on whichever of X/Y/Z has the largest component magnitude, diameter on
  the other two — parts are axis-aligned in this system, so picking the
  dominant component instead of requiring exact axis alignment is enough
  and avoids a stricter (and unnecessary) validation requirement.
- `addons/world_forge/model/part_geometry_factory.gd` — `_add_cylinder` no
  longer hardcodes "+90° about X"; it now computes
  `Quaternion(Vector3.UP, long_axis.normalized())`, the shortest-arc
  rotation from the mesh's native +Y onto whatever axis the part specifies.
  This is a strict generalization: with the default `long_axis = (0,0,1)`
  it produces the exact same rotation as before.
- `data/world_forge/parts/crucible.tres` — added `long_axis = Vector3(0, 1,
  0)` (a vessel stands upright; its `heat_base`/`rim_weld` sockets were
  already authored at ±Y, so this was always the intended orientation, just
  not expressed as data before now).
- `data/world_forge/parts/{steel_rod,axle,rope_segment,wheel}.tres` — added
  explicit `long_axis = Vector3(0, 0, 1)` for self-documentation (equal to
  the default, so behaviorally inert, but now every cylindrical part states
  its orientation instead of three of them relying on an implicit default).
- `tests/test_world_forge.gd` — 2 new tests. One loads the *real* crucible
  part from the registry and checks that `occupancy_for_cylinder` with its
  `long_axis` reproduces its hand-authored occupancy as an **exact cell
  set** (not just a matching count — the whole point, since Step 3's
  no-fix state had matching counts with different cells, which a
  count-only check would have missed). The other checks
  `PartGeometryFactory` orients a default (Z) and a vessel (Y) cylinder
  correctly by applying the resulting quaternion to `Vector3.UP` and
  checking where it lands.

**Tests:** `test_run(suite="world_forge")` → 25/25 passed (21 assertions
alone on the vessel-orientation test, all against real registry data, not
synthetic fixtures). Full `test_run()` (all 4 suites) → 39/39 passed, no
regressions.

**Review notes:** this step existed specifically to fix something review
had already found rather than let it accumulate as debt; the test written
to prove it (`test_part_profile_long_axis_resolves_the_vessel_orientation_gap`)
deliberately checks cell-set equality instead of count equality, because
count equality is exactly the weaker check that let the original gap hide
in Step 3's data. No new issues found while implementing this step.

**Status:** done.

**Next step:** either continue Phase 3 toward an actual Workshop
viewport/palette (so parts can be placed and joined, not just loaded and
previewed), or shift to Phase 1's editing controls now that the data
foundation (materials, parts, shapes, components, markers) is uniformly
`.tres`-backed. Given the user's explicit interest is the crafting/kinetics
system rather than editor polish, the next session should default to
continuing Phase 3 unless redirected.

### Step 3 — `PartGeometryFactory` + Workshop document lane (plan section 2-3 architecture) — 2026-07-04

**Scope:** the first slice of Phase 3 — prove a `PartProfile` can actually
be *rendered* as a preview mesh, and that `ForgeDocument` can hold
part-scale placements (the "Workshop" purpose from the plan's two-scale
architecture), before investing in a full Workshop viewport UI.

**Files added:**
- `addons/world_forge/model/part_geometry_factory.gd` — `PartGeometryFactory`,
  the part-scale sibling of `ShapeGeometryFactory`. `create_part(part,
  material) -> Node3D` builds a `BoxMesh`/`CylinderMesh`/`SphereMesh` from
  `geometry_kind`/`geometry_params`, or uses `custom_mesh` for `CUSTOM`.
  Cylinders are rotated +90° about X so their height runs along local Z
  (matching how every rod-like part's end sockets are authored — see below).

**Files changed:**
- `addons/world_forge/model/part_profile.gd` — added
  `occupancy_for_cylinder(radius, height, cell_size)`, a bounding-box
  approximation consistent with the box helper from Step 1.
- `addons/world_forge/model/forge_document.gd` — added a `placed_parts`
  lane (`"x,y,z"` fine-grid key -> `{pos, part_id, rotation_steps, joints}`,
  same shape/convention as the existing `blocks` lane) plus
  `has_placed_part`/`get_placed_part`/`set_placed_part`/`erase_placed_part`,
  wired into `to_dictionary()`/`_load_dictionary()`/`clear()`. Bumped
  `FORMAT_VERSION` 2 → 3 for the new lane; old documents without
  `placed_parts` still load fine (defaults to empty — verified by test).
- `tests/test_world_forge.gd` — 5 new tests: geometry factory builds the
  right mesh type per `geometry_kind` (and correctly builds *nothing* for
  `CUSTOM` with no mesh assigned, rather than guessing a fallback shape),
  cylinder occupancy matches rod/axle/rope/wheel exactly, placed-part
  save/load round-trip, and pre-Workshop documents still load with an
  empty `placed_parts` lane.

**Tests:** `test_run(suite="world_forge")` → 24/24 passed. Full
`test_run()` (all 4 suites) → 38/38 passed, no regressions.

**Review notes (a real design inconsistency found, not just syntax bugs
this time):**
- Verified `occupancy_for_cylinder`'s cell counts against every
  hand-authored Step 1 cylinder part before trusting it. `steel_rod`,
  `axle`, `rope_segment`, and `wheel` all match exactly (1,1,8 / 1,1,5 /
  1,1,4 / 4,4,1) — these were all authored with their functional axis along
  local Z, matching the new helper. **`crucible` does not match**: its
  hand-authored occupancy (3,2,3) put the height axis on Y (a vessel
  naturally stands upright — its `heat_base`/`rim_weld` sockets are
  authored at ±Y), while the new helper always assumes height-along-Z (the
  rod/axle/wheel convention). Both total 18 cells, so a size-only check
  would have silently passed while hiding a real axis mismatch — the test
  above deliberately checks rod/axle/rope/wheel only and does **not**
  claim crucible matches, and this paragraph is the explicit flag: vessels
  need either their own orientation convention or a fixed placement-time
  rotation before `PartGeometryFactory`/`occupancy_for_cylinder` can be
  trusted for them. Not fixed in this step — doing so requires deciding a
  general per-part orientation model, which is Workshop-viewport-scale
  work (real placement/rotation), not a geometry-preview concern. Flagged
  here so Phase 3's next slice doesn't quietly inherit a wrong assumption.

**Known gaps / deliberately deferred:**
- No actual Workshop viewport/editor UI - `placed_parts` is a persisted
  data lane with no palette, no placement tool, and no rendering wired up
  yet. That's the substantial remaining Phase 3 work (viewport, part
  palette, socket-snap placement mirroring `ComponentSnapResolver`).
- No joint/socket-snap logic yet for parts (the `joints` field on a placed
  part is currently free-form, unvalidated data — `ComponentSnapResolver`'s
  logic doesn't generalize to parts without changes, since part sockets are
  metric `Vector3`-positioned, not cell-aligned like component ports).
- The crucible/vessel orientation issue above is unresolved by design (not
  urgent — nothing places or renders a crucible yet).

**Status:** done.

**Next step:** either (a) the crucible/vessel orientation question — add a
per-part orientation convention (e.g. a `long_axis: Vector3` field, or a
`Category`-based default: STRUCTURAL/MECHANICAL default to Z, VESSEL
defaults to Y) so `PartGeometryFactory` renders every category correctly
before more parts are added, or (b) proceed to Phase 1's editing controls
now that the Phase 2/3 data foundation has enough surface to make gizmos
and drag-select actually useful. Recommend (a) first since it's small,
directly unblocks trusting the part system for vessels, and was found via
this session's own review rather than deferred arbitrarily.

### Step 2 — Shapes/components/markers converted from hardcoded arrays to `.tres` (plan section 2) — 2026-07-04

**Scope:** the other half of Phase 2 — `world_forge_main.gd`'s hardcoded
`SHAPES`/`COMPONENTS`/`MARKERS` literal arrays become loadable `.tres`
resources, following the exact registry convention Step 1 established
(and the block palette's pre-existing convention before that).

**Files added:**
- `addons/world_forge/model/marker_definition.gd` — new `MarkerDefinition`
  resource (id/display_name/color/sort_order); markers only ever needed
  those fields.
- `addons/world_forge/model/shape_registry.gd`,
  `component_registry.gd`, `marker_registry.gd` — three more
  folder-scanning registries, identical shape to `MaterialRegistry`/
  `PartRegistry` from Step 1 (and `BlockRegistry` before that). `list_ids()`
  sorts by a new `sort_order` field (ties broken by id) instead of
  alphabetically, so the palette keeps its original, deliberate ordering
  (cube→slab→...→plate) rather than being silently re-sorted A–Z.
- `data/world_forge/shapes/*.tres` — 7 `BlockShapeProfile` resources (cube,
  slab, slab_top, stair, fence, pane, plate). `geometry_kind`/
  `connection_kind`/`supports_rotation`/collision boxes are populated with
  reasonable values even though nothing reads them yet (confirmed via grep —
  `ShapeGeometryFactory` dispatches on the shape id string, not this
  profile); real per-shape collision geometry is explicitly future work
  (the architecture doc already calls out "custom-scene shape profiles and
  matching collision generation" as the next milestone).
- `data/world_forge/components/*.tres` — the 9 existing components
  (forge_firebox/furnace/chimney, anvil, workbench, bellows, storage_crate,
  water_source, fire_source), values copied exactly from the hardcoded dicts
  (color, footprint, ports, capabilities, snap_required, rules).
- `data/world_forge/markers/*.tres` — the 7 existing markers, same colors.

**Files changed:**
- `addons/world_forge/model/functional_component_definition.gd` — added
  `color`, `snap_required`, `rules` (plus `sort_order`) so this resource can
  fully replace the hardcoded component dicts; `SimulationRuleDefinition`
  remains the separate, heavier concept for capability-driven rules between
  placed pieces (this `rules` field is a component's own lightweight
  emission hints, e.g. `{"channel": "thermal", "effect": "emit",
  "temperature": 900.0}`).
- `addons/world_forge/model/block_shape_profile.gd` — added `sort_order`.
- `addons/world_forge/world_forge_main.gd` — removed the three hardcoded
  `const` arrays; added `_shapes`/`_components`/`_markers` instance vars,
  `_load_catalogs()` (called at the top of `setup()`, before `_build_ui()`
  builds the palette from them), and `_component_to_dict()`. Every other
  reference (`_find_definition`, `SnapResolver.find_snapped_origin`,
  placement, rendering) still consumes plain `Array[Dictionary]` in exactly
  the shape it always did — **zero behavior change was intended or made**,
  only where the data lives.
- `tests/test_world_forge.gd` — 5 new tests: shape registry loads in the
  original palette order (not alphabetical), component registry round-trips
  color/ports/capabilities/snap_required/rules exactly, marker registry
  round-trips colors, and an end-to-end test that calls the real
  `editor.setup(null)` and asserts `_shapes`/`_components`/`_markers` (and
  `_find_definition` results against them) match the original hardcoded
  values field-for-field.

**Tests:** `test_run(suite="world_forge")` → 20/20 passed (16 existing + 4
new... plus one more from Step 1 review, 20 total). Full `test_run()` (all 4
suites) → 34/34 passed, no regressions.

**Review notes (bugs found and fixed during self-review):**
- Two more instances of the same trap Step 1 already hit once
  (nested-constructor calls aren't valid in the `.tres` text format, only
  flat numeric/string args): `Color("d65a31")` — the convenient hex-string
  constructor is GDScript-only; `.tres` wants `Color(r, g, b, a)` as 4 flat
  floats — and `PackedStringArray(["a", "b"])` — Packed*Array types want
  flat comma-separated args (`PackedStringArray("a", "b")`), not a bracketed
  list literal (unlike typed `Array[T]`/`Array[Dictionary]`, which *do*
  accept the bracketed form — confirmed working in Step 1's `occupancy`/
  `sockets` fields, so the rule is specifically about the Packed*Array
  family, not typed arrays in general).
- These two bugs were **not** caught by the first test run (16/16 green) —
  none of the then-existing tests directly loaded a component/marker
  resource, so `load()` silently returning `null` for the broken files just
  meant `_load_catalogs()` skipped them without erroring. This is exactly
  the failure mode the Step 1 registry tests were designed to catch, and
  Step 2 initially skipped writing the equivalent direct-load tests before
  running once — caught by re-reading `logs_read(source="editor")` on
  principle even though the test run was green, which surfaced the real
  "Parse Error: Expected string" / "Expected float in constructor" entries
  mixed in with stale ones from Step 1. Added the 5 tests above *after*
  finding this so the next regression of this kind fails the test suite
  directly instead of requiring a manual log read. Lesson banked in
  [[reference_blender_asset_pipeline]]-style project memory would be a good
  candidate if this class of bug recurs a third time.
- Distinguishing stale vs. live log entries: the buffer mixed old Step-1
  AABB errors with new Step-2 Color/PackedStringArray errors in the same
  read. Confirmed which were live by cross-referencing line numbers named in
  each error against the current file content (line 12 = `capabilities` in
  components, line 10 = `color` in markers) rather than trusting the buffer
  order.

**Known gaps / deliberately deferred:**
- Shape/component/marker palettes are still flat lists — "favorites,
  recents, custom categories" (explicitly a later Phase 2 item in the
  original roadmap) is not part of this step.
- No live visual check of the World Forge main-screen tab was performed
  (only automated construction + exact-value assertions via
  `editor.setup(null)`). Given this step is a data-location refactor with
  no intended visual change, the exact-equality tests are a stronger check
  than eyeballing a screenshot, but worth a manual look next time World
  Forge is open in-editor.
- Shape collision geometry is still a full-cell/approximate box per shape,
  not derived from the actual rendered mesh — flagged in the architecture
  doc as later work, unaffected by this step either way.

**Status:** done.

**Next step:** Phase 3's first slice — a `PartGeometryFactory` (mirroring
the existing `ShapeGeometryFactory`) that builds a preview mesh from a
`PartProfile`'s `geometry_kind`/`geometry_params`, plus a minimal Workshop
document type so a part can actually be seen and placed, proving the
two-scale nesting the plan's architecture section depends on before
sinking more effort into palette polish.

### Step 1 — Material/part foundation (`MaterialProperties`, `PartProfile`, registries, starter data) — 2026-07-04

**Scope (plan sections 3-4):** the data-model foundation everything else in
the crafting plan stands on — one material property table plus a stock-part
resource type, loadable the same way blocks already load.

**Files added:**
- `addons/world_forge/model/material_properties.gd` — `MaterialProperties`
  resource: density, specific heat, conductivity, ignition/melting/working
  temps, strength, `molten_material_id`. Helpers: `is_flammable()`,
  `can_melt()`, `can_forge()`, `mass_for_volume()`.
- `addons/world_forge/model/part_profile.gd` — `PartProfile` resource: the
  part-scale sibling of the existing `BlockShapeProfile`. Parametric
  geometry (`geometry_kind` + `geometry_params`, so no modeled meshes are
  required yet), collision boxes, `material_id`, fine-grid `occupancy`,
  typed `sockets` (weld/hinge/bearing/slider/rope_anchor/power_shaft/
  item_port/heat_contact per plan section 5), `mass_kg` (0 = derive from
  material density × volume), `stock_recipe_id`. Helpers:
  `bounds_volume_m3()`, `resolved_mass_kg()`, `sockets_of_kind()`, and a
  static `occupancy_for_box()` for deriving fine-grid footprints from a
  metric size (used by tests now, will back Phase 3's geometry factory).
- `addons/world_forge/model/material_registry.gd`,
  `addons/world_forge/model/part_registry.gd` — folder-scanning registries
  mirroring `scripts/world/metadata/block_registry.gd`'s existing
  convention (`load_*()`, `get_*()`, `has_*()`, `list_ids()`), so the block,
  material, and part catalogs all follow one lookup pattern.
- `data/world_forge/materials/*.tres` — 14 starter materials: oak, stone,
  firebrick, iron_ore, bloom_iron, steel, bronze, charcoal, leather,
  rope_fiber, water, and the three molten phases (molten_iron/steel/bronze)
  that steel/bloom_iron/bronze melt into. Values are order-of-magnitude
  plausible (real density/specific-heat where it costs nothing, e.g. water's
  4186 J/(kg*K); melting points ordered the way real metallurgy orders them —
  bronze melts and works far below iron/steel). `iron_ore` deliberately has
  no `melting_temp_c`/`molten_material_id`: ore is chemically reduced by a
  smelting recipe, not simply melted — that distinction matters once Phase 6
  implements casting.
- `data/world_forge/parts/*.tres` — 8 starter parts covering all 4 part
  categories and the exact items named in the request: `steel_rod`,
  `steel_sheet`, `wood_beam`, `wood_plank` (structural), `wheel`, `axle`
  (mechanical, with `bearing`/`power_shaft` sockets), `rope_segment`
  (flexible, `rope_anchor` sockets), `crucible` (vessel, firebrick,
  `heat_contact` + `item_port` sockets for the pour-spout).

**Files changed:**
- `tests/test_world_forge.gd` — 7 new tests: material helper behavior,
  material registry loading the starter set, a cross-check that every
  `molten_material_id` resolves to a real registered material (catches
  dangling references before Phase 6 needs them), part mass derivation
  (explicit `mass_kg` overrides; 0 derives from material), the
  `occupancy_for_box` grid math, and part registry loading with a
  consistency check that every part's `material_id` and every socket
  actually resolve.

**Tests:** `test_run(suite="world_forge")` → 16/16 passed. Full
`test_run()` (all 4 suites) → 30/30 passed, no regressions.

**Review notes (bugs found and fixed during self-review, not just written
once and left):**
- First pass wrote `AABB(Vector3(px,py,pz), Vector3(sx,sy,sz))` in the
  hand-authored `.tres` files — valid GDScript, but the **`.tres` resource
  text format doesn't accept nested constructor calls**; it wants `AABB`
  as 6 flat floats (`AABB(px, py, pz, sx, sy, sz)`), the same way
  `Transform3D`/`Rect2` flatten in resource files. This broke all 8 part
  files (`Parse Error: Expected float in constructor`) — caught immediately
  by the registry-loading test failing with "Missing starter part:
  steel_rod", not by a human eyeballing the file. Fixed by regenerating
  with flat floats; reran and confirmed 0 parse errors and 16/16 passing.
  Noting this because any future hand-authored `.tres` with AABB/Transform3D
  fields will hit the same trap.
- godot-ai's `logs_read(source="editor")` kept surfacing the pre-fix parse
  errors after the fix landed and tests were green — this matches the known
  "stale recent_errors" gotcha (see project memory); trusted the test
  results (0 failures, 34 assertions on the part test) over the stale log
  buffer.

**Known gaps / deliberately deferred:**
- Not yet wired into the World Forge UI — `world_forge_main.gd` still uses
  its own hardcoded `SHAPES`/`COMPONENTS`/`MARKERS` arrays. That conversion,
  plus the palette UI to browse materials/parts, is Phase 2/3 work, not this
  step.
- No `PartGeometryFactory` yet (parts have no visual representation in a
  viewport yet) — parts are pure data until the Workshop viewport exists
  (Phase 3).
- Hand-authored `occupancy` arrays approximate round parts (wheel, axle,
  crucible) as bounding boxes rather than true discs/cylinders — acceptable
  for now since nothing consumes `occupancy` for overlap-checking yet;
  Phase 3's geometry factory should generate it from `geometry_kind`
  instead of it being hand-authored.
- `crucible`'s `mass_kg = 0` will derive from a *solid* box volume via
  `resolved_mass_kg()`, overestimating a hollow vessel's real mass. Fine for
  a data-model smoke test; worth a real per-shape volume calc once vessels
  matter for kinetics (Phase 5).

**Status:** done.

**Next step:** Phase 2's remaining piece — convert `world_forge_main.gd`'s
hardcoded `SHAPES`/`COMPONENTS` dictionaries into `BlockShapeProfile`/
`FunctionalComponentDefinition` `.tres` resources loaded the same way, so
the existing structure editor and the new material/part system share one
data-driven convention before Phase 3 (Workshop documents) builds on top of
both.
