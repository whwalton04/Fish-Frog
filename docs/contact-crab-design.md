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
- sideways force is at most `grip * F·n` (Coulomb friction).

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
| Swinging foot | Foothold, lifted by up to `STEP_HEIGHT` while far from it | Stiff, critically damped | Hip, 0.3 to 0.98 of leg reach |
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

## Stacking

Walking crabs ignore each other's footholds: they bump, push and climb over
shells like any other geometry. Riding is a separate, explicit mode.

### Mounting

While steering one crab on its own, the player marks the crab it's looking at
(nearest the middle of the view, within the crab's `mount_range`) with a
billboard arrow. The mount action (space) calls `mount_onto()`, which
teleports the crab on top: upright, facing the same way, each foot glued to
the `Foothold` marker (`world/foothold.gd`) nearest its hip. The body goes
where those feet hold it at rest, straddling the shell under its hips and
raised by the markers' `lift`.

Mounting a crab that already has one on top puts the newcomer in between: the
crabs above move up onto it, so any number can be stacked. A crab that mounts
brings its own riders along. Mounted crabs aren't steered, so a stack walks
with the crab at the bottom. To get off, the player looks at the floor: with
no crab to mount in view, the arrow marks where the view meets the floor,
brought within 0.6–2 m (× size) of the rider, and space calls `jump_to()`. That
lets go (`dismount()`) and launches the crab on a ballistic arc peaking
`jump_height` above the higher of its start and landing, so it comes down with
its feet on the marked spot; its riders come with it. Its feet go limp in the
air and plant on landing like anywhere else. The stack tipping past about 70°
also lets go. Space with another crab in view still mounts that one directly.

A `Flag` (`world/flag.tscn`) turns orange when a crab comes within its reach,
and becomes the one active flag; the previous one goes back to white. The
rally action (U) calls `leave_stack()` on every crab in the group, freeing the
mount joints at once rather than at the end of the frame, then drops them one
by one, a quarter of a second apart, above the active flag, spiralling out
round the pole. `drop_at()` resets the crab's legs, climbing and righting state before
it falls, so it lands like a fresh crab. The group isn't steered or sorted
into clusters until the last one has dropped. `tests/flag_test.gd` checks the
activation and the rally out of a stack.

### Glue

A mounted crab's feet are pinned to their markers and don't step. Their pull
on the body is a Jolt `Generic6DOFJoint3D` at the feet's centre, not the leg
springs. An explicit spring chain five crabs tall bounced, chattered and blew
apart however it was tuned; the joint is solved implicitly. The joint:

- holds the feet in place sideways and in turn;
- lets the body lean up to `max_sway_deg`, pivoting on its feet;
- springs up and down at `stack_hz`, critically damped, with the spring
  preloaded by the weight it carries. The stack keeps its height however
  many are on it, and only an outside push (a ledge, a crab landing on top)
  presses it down, up to `MAX_SQUASH`. It springs back after.

### Holding a stack up

- **Load.** A crab carries its own mass plus `carry_load` × the crabs above.
  Its legs hold that weight up without sagging (feed-forward), their force
  limit grows with it, and their damping grows with its square root, so the
  loaded crab stays critically damped. That damping is capped at half the
  crab's mass per physics step: above that the legs chatter under a load, and
  as feet only push, the chatter lifts the body. The legs' stiffness stays
  set by the crab's own mass, so an outside push still compresses them.
- **Speed.** A loaded crab walks at `sqrt(mass / carried)` of its speed, so
  it isn't pulled out from under the ones on top.
- **Balance.** Every crab in a stack is held at its target tilt by a damped
  torque, as a pendulum on its feet rocking at `stack_hz`, sized to the
  weight it carries. Mounted crabs aim for upright, not the tilt of what's
  under them. The legs alone stand too close in (hips 0.13 m from the centre)
  to hold the tilt of a few crabs' weight, and the tower folded over. Upright,
  a stack can only lean and shear at the feet, which is the sway when the
  bottom crab moves. The torque's stiffness and damping are capped at what one
  physics step can integrate for the body's inertia; uncapped, inserting a
  crab into a stack spun the bottom one and the stack shot off.

`tests/stack_test.gd` builds a stack of five, mounting on top and into the
middle, walks the bottom crab forward and then sideways, jumps the top crab
off, and pushes down on the stack from outside. It prints the gaps
(0.152 m each, the same at every height), the top's sway (about 0.16 m) and
the compression. `tests/mount_test.gd` checks the player's arrow, the mount
action, that moving no longer gets off, and that space jumps down to the
marked spot on the floor.

## Walls: lean away, then flip

Walking into a wall rolls the target pose's up axis away from the wall (wall
side up, belly toward it) at `climb_rate`. Only walls the legs are on, or
the foothold search is reaching into, count. The roll only grows while the
body keeps up with it. The wall-side feet step up the wall as the body leans,
and the far feet stay on the floor as the pivot. Keep pushing and the body
passes on its side and goes over onto its back, away from the wall; then
self-righting takes over. Let go and the roll unwinds at twice the rate, and
the crab settles back down.

A planted foot lets go when the hip moves out of reach of it. That covers
ledges and falling without any "above the hip" rule.

## Special crabs

`SpecialCrab` (`crab/special_crab.gd`) extends `ContactCrab` with an ability,
`use_ability()`, which Player calls on the controlled crab for the ability
action (shift). Each kind extends it in its own script and scene, the
scene inheriting `crab2.tscn`. Two hooks on `ContactCrab` serve them:
`can_walk()`, false holds the crab still (no walking, no turning), and
`leg_extension`, how many times their length the lower legs (carpus, propodus,
dactyl) are, raising the ride height by `EXTENSION_RISE` of what they add.

- `StiltCrab` (blue shell): the ability stretches its lower legs to 3× over a
  second, lifting the body about 0.43 m, and folds them back. It can't walk,
  turn, mount or jump until they're folded. Stretched, the lower legs are
  posed straight from the knee to the foot, the knee out to the side, or the long carpus would fold the
  knee up over the hip. Mounted, the mount joint's limits rise with the ride
  height, so it stands up on the crab underneath. `tests/stilt_test.gd`.

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
- **Holds are picked at lift-off and kept.** Re-aiming every tick at a
  foothold that moves with the body means a swinging foot never catches up.
- **Swings strike.** The swing target sits a little into the surface, and the
  spring damps toward rest (the foothold is fixed in the world). A critically
  damped approach creeps forever. Damping toward the body's velocity left feet
  hovering a few centimetres short.
- **Planted feet rest a hair off the surface.** A ray starting exactly on a
  surface doesn't see it, so a foot lifting off a wall slipped inside it.
- **Target pose changes at limited rates.** Facing already did (`turn_rate`);
  tilt needs it too (half of `turn_rate`). Wall feet are left out of the tilt, since
  walls go through the wall roll instead. That lets the tilt rate be fast enough
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
  (`WALL_ROLL_TORQUE`) turns the body toward the target's up. From the legs
  alone, the lean wobbled and dropped over at random points between 35° and
  45°, depending on which feet happened to be stepping.
- **Known:** walking off the platform edge at full speed tips the crab over
  mid-fall. The trailing feet still on top carry their weight share at one
  edge. This predates the fixes above. It usually lands upright.

## Settings

Nine exports. Each is relative to the crab's mass, size or stride, so tuning
one doesn't upset the others. The rest are constants derived from them.

| Export | Default | Derives |
|---|---|---|
| `size` | 1.0 | All geometry: body, collision shape, meshes, legs, ride and step height. Applied on ready. Mass is the body's own `mass`. |
| `move_speed` | 3.2 m/s | |
| `turn_rate` | 8 rad/s | Tilt rate (half of it) |
| `stance_hz` | 3.7 | Leg stiffness `m·(2πf)²/8`, lateral stiffness (0.27×), damping (ratio 1.04), which is also the drive gain |
| `strength` | 10 | Most force per leg, in multiples of its weight share `m·g/8` |
| `grip` | 0.8 | Foot friction; caps acceleration at about `grip * g` |
| `stride` | 0.4 | Step threshold as a fraction of leg reach; settle threshold and foothold jitter are 0.2× that, and the lead ahead is capped at half of it |
| `climb_rate` | 0.5 rad/s | Wall roll rate; 0 never climbs (feet stand at a wall's base) |
| `can_self_right` | true | |

Stacking has four more (see Stacking): `mount_range` (0.8 m), `carry_load`
(1.0), `max_sway_deg` (20°) and `stack_hz` (2.0).

Recovery torques scale with `m·g·size`, and their damping with
`m·size·√(g·size)`, so they behave the same at any mass and size. Swing and
limp foot springs are fixed (in 1/s², independent of size). Everything but
`size` can be changed while running.

## Risks

- Emergent behaviour is harder to steer. "Flips after about 2.5 s of pushing"
  becomes a result of friction, leg strength and drive, not one setting.
- Friction caps acceleration at about `grip * g`, which may feel
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
