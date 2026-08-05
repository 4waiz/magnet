# Game Design — Magnet Rush

**ATTRACT. CHARGE. BLAST.**

One control. Hold to attract, release to repel. Everything else is consequence.

## The fantasy

A magnetic crystal — the **Kanban Core** — is ripping metal out of a floating
research facility and turning it into a violent orbiting storm. The player
should read that in three seconds: a bright faceted crystal with a white-hot
energy seam, caged in spinning rings, surrounded by torn-off machinery.

## The loop

| Input | Result |
|---|---|
| **Touch down** | The magnetic field opens. Nearby metal moves on the *same frame*. |
| **Hold** | Charge rises. Orbit widens, rings speed up, the shell seam opens, audio pitch and haptic cadence climb. |
| **Release** | The swarm launches forward. Walls break, sparks fly, the camera kicks. |

### Why attraction feels immediate

A pure force model integrates from zero velocity, so a piece sits still for
several frames after touch-down. That reads as input lag no matter how fast the
input was handled. `MagnetField` therefore applies two terms:

* a one-shot **seat impulse** the first frame a piece enters range, scaled by
  proximity — something visibly moves at once;
* a continuous **pull** that ramps in over `engageTime` — distant pieces
  accelerate rather than jerk.

Both divide by mass, which is what makes light scrap snap in and heavy stock
resist for a beat. Tested in `test/gameplay_test.dart`.

### Why release feels powerful

An even radial burst throws a third of the swarm backwards where it cannot hit
anything. Launch direction is biased strongly forward (and toward a live target
when one is in range), while keeping enough lateral spread to still read as an
explosion. Over 90% of launched pieces travel forward — asserted in tests.

Heavier pieces launch slower and hit harder (`MassClass.impactDamage`).

## The perfect release

The perfect window is a **band, not a floor**, so "hold forever" is not a
winning strategy:

1. Charge rises to full over roughly 1.6 s.
2. At full charge the window is open — the Core goes white-hot, a distinct tone
   plays, the haptic cadence becomes rhythmic.
3. After `overchargeGrace` (0.85 s) the Core **vents**: charge drops to 0.30,
   the window closes, and the HUD says `OVERLOAD — VENTED`.

The window stays open for at least a third of a second (asserted in tests),
which is a fair target on a phone. A perfect release grants a stronger launch,
a white-cyan flash, a unique sound, a heavier haptic, a score bonus and a
stronger camera impulse.

## Swarm structure

Three deliberate layers rather than a cloud:

| Layer | Radius | Speed | Carries |
|---|---|---|---|
| inner | 1.02 | +2.55 | small scrap, and the magnetic key in its own slot |
| middle | 1.46 | −1.70 | armour plates |
| outer | 1.96 | +1.15 | heavy loose scrap |

Radius expands with swarm size, which is the primary read for "the swarm grew".
Captured pieces fly a **curved** magnetic trajectory to their assigned slot and
then ease into orbit — a straight line reads as a snap.

Nothing orbiting is a rigid body. Orbit position is closed-form from
`(layer, slot, phase)`, so it is deterministic, resettable and costs a few trig
ops per piece.

## Progression within a level

Swarm stages (12 / 28 / 48 objects in Level 1) each trigger a ring wave, a
sound, a haptic tick, a camera impulse and a HUD banner. The Core also visibly
slows as the swarm grows, so mass is felt rather than only counted.

## Scoring

| Source | Value |
|---|---|
| Metal collected | 10 each |
| Destruction | 60 per wall block, 150 for a bridge, scaled by the combo multiplier |
| Perfect release | 250 |
| Best chain | 40 each |

Combo builds on any collect or destruction and expires after 2.6 s. Stars: one
for finishing, one for hitting the metal target, one for two perfect releases
with no damage taken.

## Accessibility

* **Reduced motion** scales shake, FOV swing and impulse magnitude toward zero.
  It does not change framing, forces, timing or scoring.
* **Camera shake** can be disabled independently.
* **Effect intensity** scales particle counts and glow.
* **Haptics** disable gracefully — the service probes once at boot and reports
  `supported = false` rather than throwing into the frame loop.
* Quality presets scale presentation only. Attraction range, repulsion force,
  hazard timing and scoring are identical at every preset; only `maxSwarm`
  differs, because the swarm is the dominant per-frame cost.

## Audio

Every cue is synthesized as PCM in Dart at boot (`lib/core/audio/synth.dart`)
and played from memory. No sample licensing, nothing shipped in the APK.

Collection is deliberately **not** one-shot-per-pickup: collecting a hundred
pieces in two seconds would fire a hundred voices. Pickups are grouped into a
rate-limited voice whose pitch tier rises with swarm progress, so a fast pickup
run reads as one rising arpeggio.

## What is not designed yet

Worlds 2–5, levels 2–50, enemies, all five bosses, upgrades, shop, skins,
missions, daily challenge, endless mode and monetization. See
`docs/known_limitations.md`.
