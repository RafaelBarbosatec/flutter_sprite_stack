# Authoring rules

Split by origin so you know what is a hard requirement of this package and what
is craft advice inherited from the reference pipeline
([danielwh2/sprite-stacking](https://github.com/danielwh2/sprite-stacking), MIT).

## Hard requirements (the loader/renderer enforces these)

1. `imageWidth % sliceCount == 0` and `imageHeight % frameCount == 0`.
2. One shared cell width for all slices in a frame — the renderer centres each
   cell, it never re-centres content.
3. All frames in an atlas share the exact same `(width, height)`.
4. Transparent background.
5. Slice 0 is the ground contact of the prop.

## Craft rules (from the reference pipeline)

### Views

- Four orthographic views: **TOP, SIDE, FRONT, BACK**, same scale, flat
  background, no perspective.
- The TOP view is what gives the prop its plan silhouette; the SIDE/FRONT define
  the height profile. A wrong TOP view is the most common reason a carved prop
  looks like a different object from above.
- `--round` is for bodies of revolution (towers, pots, balloons, tree canopies).
  Using it on a boxy prop shaves the corners.

### Slice budget

| Tier | Slices | Reads as |
| --- | --- | --- |
| chunky | 15–20 | stylised, cheap, strong silhouette |
| detailed | 26–44 | the default for props and characters |
| showcase | 36–56 | promo art, hero props |

More slices means smoother vertical curvature and a taller lift; it does not add
horizontal detail.

### Multi-frame (animation)

- Load/build every frame with identical `(w, h, count)` — the reference notes
  call this out explicitly for flapping, wing-beating and tail-swishing props.
- Keep a **shared symmetric pivot**. The pivot is the cell centre; if frame 3 is
  drawn 2 px to the left, the animation jitters instead of moving.
- Leave **empty slices of headroom** above the rest pose for parts that travel
  upward. Without headroom the wing/flame/hair clips at the top of the cell.
- Prefer selecting the frame from the creature's **physical phase** (walk cycle
  position, wing angle) over a free-running timer, so animation speed follows
  movement speed. In this package that means: drive `SpriteStackAnimation` from
  your own phase when the character speed varies, instead of a constant
  `frameDuration`.

### Per-slice deformation (no extra frames)

The reference engine notes describe two cheap deformations that this package
implements as `StackMotion`:

- **Sway** — `sin(t · speed − z · wave + phase) · amplitude · (z / (n−1))²`.
  The square is the important part: slice 0 stays pinned and the tip moves by
  exactly `amplitude`. Use it for flags, kelp, grass, capes, antennae, torches.
- **Tilt/bend** — a constant offset proportional to height. Use it for wind
  direction, a leaning plant, a banner hanging to one side.

Both are authored at runtime, not in the PNG: authoring extra frames for them
multiplies memory for something the renderer does in one multiply.

### Smooth motion

Keep positions as floats and round once, at the final blit. Rounding every
intermediate value makes a slowly moving prop stutter. `pixelSnap` does exactly
this (anchor and per-slice lift rounded once), which is why it wants an integer
`scale`.

### Slice bloom (entrances)

To make a prop appear from the ground up, animate how many slices are visible
(`SliceCut(top: progress * sliceCount)`) instead of fading the whole sprite in.
It keeps the pixel grid crisp and reads as the object growing. When the top
slice lands, avoid a one-frame "snap" by letting the frontier overshoot the last
slice rather than clamping exactly to `sliceCount`.

## Anti-patterns

| Anti-pattern | Why it breaks |
| --- | --- |
| re-centring each slice to its own content | the prop wobbles while rotating |
| padding smaller frames to match | shifts the pivot, animation jumps |
| authoring frames for sway/breathing | 4–8× memory for something `StackMotion` does free |
| baked-in drop shadow | double shadow with `shadow: true`, and it rotates with the prop |
| anti-aliased edges | halo that fights the pixel grid |
| using the strip as a sprite sheet for a 2D character | stacks have no limbs; a normal 2D walk cycle reads better for articulated characters |

## Honest limits

- A stack cannot articulate: no separate arms, legs or head rotation. If the
  character needs a walk cycle with limb movement, use a conventional 2D sheet
  and treat the stack as scenery props.
- A hollow interior is only visible through a `SliceCut`; the strip alone is a
  solid silhouette.
- Very thin features (wires, blades, smoke) disappear at low slice counts
  because the carver samples them per slice height.
