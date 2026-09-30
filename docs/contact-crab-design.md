# Contact-force crab: design

A rewrite of the original crab (`crab/crab.gd`, since removed) as
`crab/crab2.gd`. The goal is the same behaviour, and more, from a few physical
rules instead of case-by-case fixes.

## Why

In `crab.gd` the body is moved by forces with no physical source: a walking
push at the centre of mass, a keep-level torque, and legs that only push
straight up. Wherever real contact physics would have produced a behaviour,
a rule was added instead: wall bracing, wall support, climb factor, far-leg
easing, fading the drive and keep-level torque when tipped, a climb speed cap,
"foot above hip" checks, two reach thresholds, and a side-on test. The rules
interact, and each new one partly exists to undo side effects of an earlier one.

## The three rules

### 1. Every planted leg uses the same contact-force law

Each planted foot sits at a point on a surface with normal `n`. The planted
ground feet say where the body centre should be in its *target pose* (each
foot's rest spot, placed in the target pose, puts the centre somewhere; take
the average), and that says where every hip should be:

    center_goal = mean over ground feet of (foot - target_basis * rest_local)
    hip_goal    = center_goal + target_basis * hip_local

(An earlier version turned each leg about its own foot,
`hip_goal = foot + target_basis * (hip_local - rest_local)`. With the feet
outside the hips, that turns and rolls the body the *wrong way*: facing the
target was unstable, so the crab slowly swung round to face the camera, and
walls rolled it into them.)

The leg is a spring-damper pulling the hip toward `hip_goal`: stiff along the
target up axis (support), softer sideways (anchoring). It also carries its share
of the body's weight (gravity feed-forward, `m g / planted_count`) and damps
the hip's velocity toward the wished walking velocity. The resulting force then
goes through the **friction cone** before it is applied at the hip:

- the foot can push against its surface but never pull (`F·n ≥ 0`);
- sideways force is at most `foot_friction * F·n` (Coulomb friction).

The reaction is applied to whatever the foot stands on, if it's a rigid body.

What this gives, with no special cases:

| Behaviour | How it falls out |
|---|---|
| Standing, bobbing, terrain lean | Vertical springs at hips on uneven feet |
| Walking and turning | The velocity and target-pose terms, pushed through friction |
| No drive in the air or upside down | No contacts, no force |
| Wall bracing | A foot on a wall can only push along the wall's normal |
| Wall support | Vertical force on a wall foot is only what friction allows |
| Slipping on steep or slick surfaces | Friction cone (per-surface friction is a small extension) |
| Pushing objects, riding platforms | Equal and opposite reaction on the collider |

### 2. The body only moves through its legs

There's no central drive and no keep-level torque. The *target pose* (a yaw
that turns toward the camera's facing at a limited rate, and an up axis blended
between world up and the planted ground feet's normals, plus the wall roll
below) only enters through each leg's `hip_goal`. Keeping level, turning and
driving all come from the leg forces. The two exceptions are self-righting and
holding the wall lean (see "Still hand-written").

### 3. Everything unplanted is a point on a tether

One building block: a point with mass pulled toward a target by a spring,
stepped with **implicit Euler** (stable at any stiffness). It is kept between
a minimum and maximum distance from an anchor, and ray-collided against the
level.

| Use | Target | Spring | Tether |
|---|---|---|---|
| Swinging foot | Foothold, lifted by up to `step_height` while far from it | Stiff, critically damped | Hip, 0.3 to 0.98 of leg reach |
| Limp foot | Relaxed pose under the body, with gravity, damped against the body's motion there | Stiff, lightly damped (bouncy) | Same |

A free foot plants when it reaches its foothold, or when it touches any
surface within reach. This is how landing, and grabbing a wall mid-fall,
both happen.

When no leg has pushed for `AIRBORNE_DELAY` (thrown, falling, on its back),
the crab is airborne: planted feet that can't push and are stretched past
their rest length let go, and free feet ignore their footholds and hold the
limp pose, so the legs stay rigid instead of reaching back to where they
were. The first foot to touch something ends it.

## Footholds

One query, in the body's own frame, so it works the same on the floor, on a
wall, rolled over, or upside down. Cast from inside the body at hip height
toward the foot's home spot (rest position plus velocity lead). If that misses,
cast down (body-down) from the end of it. If it hits rising ground (normal
within 60° of world up, such as a hump), carry on along that surface toward
home and look back onto it, so the foot stays splayed instead of landing
against the body. If it hits a wall, do the same while walking into the wall;
otherwise put the foot on the floor at the wall's base. Nothing reachable means
the foot goes limp.

## Walls: lean away, then flip

Walking into a wall rolls the target pose's up axis away from the wall (wall
side up, belly toward it) at `wall_roll_rate`. Only walls the legs are on, or
the foothold search is reaching into, count. The roll only grows while the
body keeps up with it. The wall-side feet step up the wall as the body leans,
and the far feet stay on the floor as the pivot. Keep pushing and the body
passes on its side and goes over onto its back, away from the wall; then
self-righting takes over. Let go and the roll unwinds at twice the rate, and
the crab settles back down.

A planted foot lets go when the hip moves out of reach of it. That covers
ledges and falling without any "above the hip" rule.

## Lessons from implementing it

Refinements that turned out to be needed. Each is a general rule, not a case
for one situation.

- **Fixed weight share.** Each planted foot carries `m g / 8`, not
  `m g / planted_count`. A foot can't know where the weight is. With a
  per-planted share, the few feet left on a ledge carried all of it at one
  edge and levered the body into a flip.
- **Leg workspace.** One reach check is used everywhere (foothold search,
  planting on touch, letting go): between folded and stretched, no more than
  30° above the hip's plane, because a leg can only push from the body's
  underside, and out on its own side of the hip. Without the "not above the
  hip" part, a crab on its back planted on the floor above it and pulled
  itself back over while trying to self-right. It is an angle, not a height,
  so the far feet keep hold while the crab leans away from a wall. Without the
  "own side" part, at full sideways speed the body overran its leading feet
  faster than they could step, and dragged them along folded under it.
- **Footholds are picked at lift-off and kept.** Re-aiming every tick at a
  foothold that moves with the body means a swinging foot never catches up.
- **Swings strike.** The swing target sits a little into the surface, and the
  spring damps toward rest (the foothold is fixed in the world). A critically
  damped approach creeps forever. Damping toward the body's velocity left feet
  hovering a few centimetres short.
- **Planted feet rest a hair off the surface.** A ray starting exactly on a
  surface doesn't see it, so a foot lifting off a wall slipped inside it.
- **Target pose changes at limited rates.** Facing already did (`turn_rate`);
  tilt needs it too (`tilt_rate`). Wall feet are left out of the tilt, since
  walls go through the wall roll instead. That lets `tilt_rate` be fast enough
  (4 rad/s) to follow humps. At 0.8 the pose lagged so far behind on a slope
  that the body caught on it.
- **Pitch is limited, roll isn't.** Crabs walk sideways and roll readily, but
  their bodies pitch little. The target follows surfaces fully in roll, but at
  most 25° nose-up or nose-down.
- **Drive is surface-relative.** The wished velocity is rotated from world
  level to the ground tilt, as on a slope (not by the wall roll). A foot can't
  pull the body toward the surface it stands on, so each foot drops the part
  of the drive that heads into its own surface.
- **Ground feet place the body; wall feet brace.** The body centre is fitted
  to the ground feet only. When wall feet counted too, they dragged the centre
  up the wall as they climbed, stretched the far floor feet until they let go,
  and dropped the body over early.
- **Leg forces act level with the centre of mass.** The hips sit a hair below
  it, and driving through them there pitched the body nose-up by up to 30°
  while walking.
- **Self-righting is judged by support.** "Stuck" means the legs aren't
  holding the body up along its own up axis, not "no feet down". Upside down,
  feet on the floor push along the body's down axis. Climbing, wall feet push
  along its up axis. The righting torque is damped so it settles instead of
  tumbling through upright.
- **Teleport guard.** A foot more than twice its leg length from its hip
  snaps back instead of being dragged through geometry.

## Still hand-written

- **Gait:** a planted foot steps when it drifts too far from its foothold.
  Alternate-leg groups lock each other out unless a foot is badly overstretched.
  Footholds get a small random scatter.
- **Self-righting:** with the body tipped over and the legs not holding it up,
  a torque rolls it back while the legs flail. Past on its side, leg support
  doesn't count, so a crab that went over against a wall doesn't stay propped
  on it.
- **Wall lean:** while the wall roll is active, a damped torque
  (`wall_roll_torque`) turns the body toward the target's up. From the legs
  alone, the lean wobbled and dropped over at random points between 35° and
  45°, depending on which feet happened to be stepping.
- **Known:** walking off the platform edge at full speed tips the crab over
  mid-fall. The trailing feet still on top carry their weight share at one
  edge. This predates the fixes above. It usually lands upright.

## Settings (about 20, mostly physical)

- Movement: `move_speed`, `turn_rate`, `tilt_rate`, `wall_roll_rate`
- Legs: `ride_height`, `leg_stiffness`, `leg_lateral_stiffness`,
  `leg_damping`, `leg_max_force`, `foot_friction`, `terrain_follow`
- Gait: `step_threshold`, `settle_threshold`, `swing_stiffness`,
  `step_height`, `velocity_lead`, `foot_placement_jitter`
- Limp: `limp_stiffness`, `limp_damping`
- Recovery: `self_right_torque`, `wall_roll_torque`
- Shape and visuals (unchanged from `crab.gd`)

## Risks

- Emergent behaviour is harder to steer. "Flips after about 2.5 s of pushing"
  becomes a result of friction, leg strength and drive, not one setting.
- Friction caps acceleration at about `foot_friction * g`, which may feel
  sluggish next to the current scripted drive.
- Stiff springs at this scale (0.1 m legs) need to stay stable at 120 physics
  ticks per second. The implicit-Euler points are safe; the body springs are
  explicit and need checking.

## Validation

Headless scenario scripts (`tests/scenarios.gd`): a
2 m drop, climbing the ramp onto the platform, walking off the platform edge,
walking along and into the platform wall (count feet inside geometry), strafing
into the wall (tilt over time, flip, recovery). Also: facing after walking each way (drift), and crossing the
hump and dome head-on and sideways (stalls, feet folded under the body).
