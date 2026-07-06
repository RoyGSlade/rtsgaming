# Mixamo rigging checklist (the one manual step)

The pipeline pauses here for units. Everything before and after is automated.

1. Go to <https://www.mixamo.com> (free Adobe account) → **Upload Character**.
2. Upload `staging/for_mixamo/<asset>.fbx`.
3. Place the auto-rig markers: **chin, wrists, elbows, knees, groin**.
   - Symmetry on; standard skeleton (with fingers is fine — they just won't
     be animated by Kimodo clips).
4. Wait for auto-rig, sanity-check the preview animation.
5. **Download: format FBX Binary, pose = T-pose, no animation.**
6. Save as `staging/rigged/<asset>.fbx` (exact asset name).
7. `python pipeline.py resume <asset>`

## Troubleshooting

- Mesh explodes in preview → cleanup left non-manifold geometry; rerun
  `pipeline.py redo <asset> cleanup`, consider a higher tri budget.
- Character imports sideways/tiny later → transforms weren't applied; the
  cleanup script does this, so re-export rather than hand-fixing.

## Future: removing this step

Candidates for local auto-rigging in v2: **UniRig**, **Auto-Rig Pro** (paid),
or a saved Rigify metarig fitted per archetype. Not built in v1 on purpose.
