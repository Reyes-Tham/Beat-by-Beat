# Beat By Beat — Features

A spatial rhythm game for Apple Vision Pro, built for upper-limb rehabilitation
after a stroke. Targets appear inside the patient's **own measured reach** and
have to be met in time with the music. One chart therefore fits very different
abilities: the same song asks a patient with 20 cm of reach and a patient with
60 cm for the same movement, scaled to what each of them has.

This document describes every feature, then maps them onto three problems in
home-based rehabilitation.

---

## Contents

- [The session, end to end](#the-session-end-to-end)
- [Setting up the workspace](#setting-up-the-workspace)
- [Choosing what to practise](#choosing-what-to-practise)
- [During a song](#during-a-song)
- [What gets measured](#what-gets-measured)
- [Access and testing](#access-and-testing)
- [Applying it to the three problems](#applying-it-to-the-three-problems)
- [What the app does not do](#what-the-app-does-not-do)

---

## The session, end to end

1. **Launch** → if a reach has been measured before, the *Welcome back* screen;
   otherwise, calibration.
2. **Sit and settle** → the workspace moves onto where the patient is sitting.
3. **Choose a song, arm, mobility level and movements.**
4. **3 · 2 · 1** countdown.
5. **Play** — targets appear in reach, in time with the beat.
6. **Results** — score and reach count, which fades itself after five seconds.
7. **Statistics** — the session is filed and can be reviewed against previous
   ones at any time.

---

## Setting up the workspace

### Reach calibration

Six directed reaches per arm — **forward, back, left, right, up, down** — in
that order, running from easy to hard and ending on a restful one.

Nothing is chased. The patient is told a direction only, and whatever they
reach in it *is* the measurement. An earlier design put probes at fixed corners
and asked patients to touch them, which measures the probe: somebody who cannot
get to the upper corner produces a reading about that corner, not about
themselves.

- **Each direction ends itself.** When the arm stops moving, the direction is
  accepted — nothing to press mid-reach.
- **A stick-figure guide** shows the direction being asked for, with the correct
  arm on the correct side.
- **Eight preview dots** show the box growing as the reaches are captured, so
  patient and therapist can both see the range being built.
- **The arm is locked in with a head glance** at a confirmation circle placed
  just below eye line — or with the *Lock this arm* button.
- **Redo arm** restarts the six directions for the arm in progress. Arms already
  locked are kept.
- **Tracking limits are recorded separately.** If the headset lost the hand
  before the patient stopped moving, that direction is flagged as limited by
  tracking, not by reach — so a short reading is not mistaken for a short reach.
- **Each arm is measured on its own.** Hemiparesis is asymmetric by definition;
  averaging the two arms would put targets out of reach on one side and make
  them trivial on the other.
- **Safety margin.** Gameplay uses 85% of the reached box. Targets at the very
  edge of comfortable reach invite trunk compensation and overbalancing.

### Recentring — "Welcome back"

Six reaches per arm is a lot to ask of a weak arm, and asking it at every
session spends the patient's freshest minutes on setup.

With a reach already on file, the launch screen instead asks only for the thing
that genuinely changes between sessions: **where they are sitting**. The head
pose is read, and the whole workspace is moved onto it. It locks in on its own
once the head has been still for 1.5 s — nothing to press, nothing to reach for
— and a *Start* button takes the position immediately.

**A different chair, a different height and a different direction are all the
same operation.** Each box keeps its position *and its orientation relative to
the patient*, so a patient who has turned ninety degrees to face the window gets
the same reaches, turned with them. Nothing is refitted, so the measured extents
survive a turn exactly.

That works because the reach box is fitted in the patient's own axes rather than
the room's, and carries its own facing. "Forward" has to mean forward *for
them*. A box squared to the room around the same points comes out both larger
and wrong — wide where the patient is shallow, deep where they are narrow — and
would grow further every time it was turned.

Everything measured relative to the patient turns with them, including the grip
orientations: *cup* asks for a palm toward their midline, which is a direction
on the body, not in the room.

The screen shows the saved reach in centimetres, when it was measured and when
it was last played, so a stale or wrong capture gets noticed rather than reused
silently.

### The workspace sliders

Per-arm centre and size (height, distance, sideways / width, height, depth),
adjustable in Settings.

**These sliders are the single source of truth** — they are what gameplay reads.
A finished calibration writes its measurements into them, and the next
calibration overwrites them again. So a therapist can nudge a boundary after a
capture without redoing it, and what they read in Settings is always where
targets are going.

They are also read in the patient's own axes: *distance* is how far in front of
them the box sits and *sideways* is how far to one side, whichever way their
chair is turned. Height stays measured from the floor, which is a number that
can be checked against a chair.

---

## Choosing what to practise

### Songs

Five tracks, each with a note about the movement it suits:

| Song | Tempo | Suits |
| --- | --- | --- |
| Demo Track | 143.9 BPM | Alternating reaches, steady tempo |
| Afro Vibes | 117.4 BPM | Slower pulse, long recovery between reaches |
| Tung Tung Sahur | 130.9 BPM | Brisk and even, steady alternating reaches |
| Tralalero Tralala | 138.1 BPM | Quick pulse, short bursts of movement |
| Slow Steady | 60 BPM, silent | Long single reaches, maximum rest |

Real songs carry a **beat map** — a list of absolute beat timestamps extracted
from the audio, not a constant-tempo grid — so targets land on the beats the
patient can actually hear, including where the tempo drifts.

### Mobility — five levels

Ordered by what is genuinely hard after a stroke rather than by how large the
movement looks. Post-stroke reaching is dominated by synergy coupling, so the
progression follows that:

| Level | Space | Movement asked for |
| --- | --- | --- |
| 1★ | Centre, chest height, close in — long rests | Short reaches straight ahead |
| 2★ | Adds forward distance | Straightening the elbow |
| 3★ | Adds height | Lifting the arm against gravity |
| 4★ | Adds width | Reaching away from the body |
| 5★ | Same space, faster | Moving to time |

**Reach demand and speed demand are kept separate.** Levels 1–4 differ in space
only; every one of them gives 8 beats to travel. Only level 5 shortens that, to
4. Nobody is asked to move further *and* faster at once.

**Rest shortens as levels rise** — 8 beats at level 1, 6 at level 2, 4 above
that, and never zero. Tolerance for sustained work is itself part of what
recovers, so it is trained rather than assumed.

A level is also *suggested* after calibration, from the fastest comfortable
speed observed during the capture. It is a suggestion for the therapist, not a
decision.

### Which arm

Left, right, or both. With both, targets alternate and each arm uses its own
measured box. **Only the training arm can score** — which is what stops a
patient quietly compensating with their stronger side.

### Movement types

Any combination of three, chosen per session:

- **Reach** — move the hand to a target.
- **Pour** — guide the hand along a curved path through waypoints, as in tipping
  a jug. The target only retires when the whole path has been followed, so the
  trajectory is the exercise, not the endpoint.
- **Grip** — close the hand on the target. Grip is treated as a *movement*, not
  a pose: the open hand has to be seen at the target first, and only then does
  closing score. A fist arriving already closed does not count.

Grip additionally asks for a hand orientation:

- **Cup** — palm inward, closing around a mug.
- **Overhand** — palm down, lifting something off a table.

Pour and grip are given more time than a plain reach (1.5× and 1.25×), because
they are longer movements.

---

## During a song

- **Targets** appear as coloured spheres with a shrinking outer shell. The shell
  reaching the sphere is the beat — the movement is timed to arrive with it,
  giving several seconds of visible warning rather than a sudden cue.
- **The next-target bar** counts down to when the *next sphere will appear*, and
  says which arm it is for. Deliberately not a beat metronome: beats run several
  times a second while targets arrive every few seconds, so a beat indicator
  says nothing useful to somebody whose reach takes three seconds. "Get ready"
  is the only thing worth telling them.
- **Timing feedback** — contact is judged against the target's beat as a
  fraction of the travel time: within 10% is **Excellent!**, within 25% is
  **Good!**, anything else that was reached is **Okay!**. Floating praise rises
  out of the target and dissolves.
- **Reaching a target** plays a ding, shatters the sphere into fine dust, and
  scores. Both sounds are spatial, so they come from where the hand is.
- **A spawn cue** sounds as a new target appears.
- **Missing** one is quiet. There is no failure sound, no penalty noise, and no
  streak to break.
- **Scoring** is in points, not a fraction: 100 for on-time, 70 for close, 50
  for reached at all. Every reach earns something. A "22/25" would tell a
  patient who reached every target but was late that they had failed at the
  thing they had actually done.
- **A back button** is the only control on screen during play.

---

## What gets measured

Every session is recorded automatically — nothing to start, stop, or write
down. The recorder stores **raw outcomes**, not pre-computed numbers, so
metrics can be re-derived later without needing the patient to repeat anything.

### Per-session summary

| Metric | What it says |
| --- | --- |
| Reach success rate | Share of targets actually reached |
| Reachable workspace | How much of the calibrated box the hand visited, as a volume ratio |
| Average reach time | Spawn to contact |
| Movement consistency | Spread of reach times (± seconds) |
| Missed targets | Count out of those presented |
| Active time | Time actually spent moving, excluding pauses |
| Rest / pauses | Stretches where tracking was lost for 1.5 s or more |

### Reach by direction

Success rate broken down by **upper, lower, left, right, forward and
cross-body**, plus per-hand rates when both arms were trained. A target belongs
to several regions at once and is counted in each, because the useful question
is "how do they do with overhead targets", not "which single bucket does this
one fall in". Cross-body depends on which hand was asked — reaching past the
midline is a different task from reaching to your own side.

### Reach heatmap

Two flat 5×5 grids — **facing them** (left/right × up/down) and **from above**
(left/right × far/near). Colour is success rate, red through green; square size
is how often that spot was asked for; empty outlines mean the patient was never
asked to go there, which is distinguishable from having gone and missed.

Both grids read in the patient's own left and right, so a red patch on the right
of the map and a low "Right reach" percentage are visibly the same fact.

### Trend and observation

Each session is compared against the one before it — success rate, reachable
workspace, average reach time — with arrows, and a small threshold below which
nothing is arrowed, since tiny movements between two sessions are noise.

An **observation** in plain language appears only when there is something worth
saying: the weakest direction if it falls below 70%, a drop in success rate
across the run (which can mean the session ran long), or three or more pauses.
An observation on every session would train people to ignore it.

### History

Sessions are browsable one at a time with ← →. The last 60 sessions and 20
calibrations are kept on the device. Old calibrations are retained so a
workspace can be compared against what it was, not only read on its own.

---

## Access and testing

- **Voice control** — saying **"Calibrate"** opens the reach capture, and
  **"Recenter"** moves the workspace onto where the patient is sitting. Both are
  the setup steps that come *before* the app knows anything about their reach,
  which is exactly when pointing at a control is hardest. Listening happens in
  the menus only — never during a song, and never during a capture, where acting
  on the word "calibrate" in conversation would discard the reaches already
  measured. Recognition is required to be **on-device**; where that is
  unavailable the feature reports itself unavailable rather than sending audio
  anywhere. On by default, switchable in Settings.
- **Minimum-size UI.** Every screen declares the size its content actually
  needs, so nothing is compressed into overlapping rows.
- **Simulated hand.** A drag pad stands in for a hand so the whole app —
  including calibration — can be exercised without a headset. On by default in
  the Simulator, which reports no hand anchors at all.
- **Developer mode** — disco lights, 6× chart speed and dancing cats, for
  showing the app off. Off by default and persisted, so a patient cannot
  stumble into it.

---

## Applying it to the three problems

### 1. Reduced supervision at home → lower engagement and inconsistent practice

The cycle described is real: unsupervised repetition is dull, dullness reduces
practice, less practice slows progress, and slower progress costs motivation.

**What addresses it directly**

- **The exercise is a song, not a set.** The repetition is unchanged — reach,
  return, reach — but the unit of attention is a track with an end, not a count
  of twenty. A session finishes when the music does.
- **Music supplies the pacing a therapist otherwise supplies.** Targets land on
  detected beats, and the travel window is a whole number of musical bars, so
  the reach *is* the phrase. The patient is being cued continuously by something
  that is not a person watching them.
- **Five songs and five levels** give a session variety without changing the
  exercise, which is what keeps daily practice from becoming identical.
- **Every reach scores something.** 100/70/50 rather than hit-or-miss means a
  slow patient who reaches every target still sees a rising number. A percentage
  score would tell them they had failed at a thing they in fact did.
- **Misses are silent.** No failure sound, no penalty, no streak to break —
  there is nothing in the loop that punishes a bad day.
- **Difficulty is chosen in space and speed independently**, so progression is
  available in small steps that are genuinely achievable rather than one
  all-at-once jump.
- **Setup is not a barrier to starting.** The returning patient sits down, holds
  still for a second and a half, and plays. Or says "recenter". They can sit
  somewhere different, at a different height, facing a different way, and it is
  still one button. The cost of beginning a session is close to zero, which
  matters more for daily adherence than anything inside the session.
- **A per-session score and a visible trend** give the feedback that supervision
  otherwise provides — someone noticing that today went better than last time.

**Honest limits.** There is no reminder, no streak, no scheduling, and no
remote encouragement from a therapist. Adherence support beyond making the
session pleasant and cheap to start is not implemented.

### 2. Inadequate tracking and assessment of prescribed movements done at home

**What addresses it directly**

- **Recording is automatic and complete.** Every target presented, whether it
  was reached, where it was in the workspace, which hand was asked, and how long
  the reach took. Nothing depends on the patient remembering to log anything —
  which is where home exercise diaries fail.
- **Raw outcomes are stored, not summaries.** The metrics a therapist wants have
  changed twice during development already; re-deriving them costs nothing,
  whereas re-recording a session is impossible.
- **The metrics are movement quality, not just count.** Average reach time and
  its spread say something a repetition count cannot: *consistency* falling is
  usually a better sign of improvement than a faster average, which one lucky
  reach can move.
- **Directional breakdown** shows *which* movements are failing — upper, lower,
  cross-body — so a prescription can be adjusted to the direction that needs it
  rather than uniformly.
- **The heatmap localises it spatially.** A red patch high and to the right is a
  specific instruction: that is where to work.
- **Reachable workspace as a volume ratio** is the number that moves when a
  workspace genuinely opens up, and it is comparable across sessions because it
  is measured against that patient's own calibrated box.
- **Pauses and active time separate "did the work" from "was in the room"**, and
  fatigue is measured directly by comparing the first quarter of a run to the
  last — which flags a prescription that is running longer than the patient has
  in them.
- **Calibration history** means the workspace itself is a tracked outcome, not
  just the scores inside it.
- **Tracking limits are recorded as such**, so a therapist reading a short reach
  can tell whether the patient or the headset was the limit.

**Honest limits.** Everything stays on the device: there is no export, no report
to send, no clinician portal, and no sync. A therapist has to look at the
headset. The 60-session cap is roughly two months of daily use. This is the
clearest gap between what is measured and what a clinician could act on
remotely, and closing it is a matter of adding an export path rather than of
collecting anything new.

### 3. Fear of dropping, spilling or damaging objects discourages simple tasks at home

This is the problem the medium is best suited to, and the movement types were
designed for it.

**What addresses it directly**

- **Nothing can be dropped, spilled or broken.** The targets are virtual. The
  entire class of consequence that makes a patient avoid picking up a mug does
  not exist, so the movement can be rehearsed at full effort without the risk
  that suppresses it.
- **Grip rehearses the actual grasp pattern**, not a proxy. The hand must be
  seen open at the target and then close on it — the open-to-closed sequence
  that picking something up requires. A hand that arrives already closed does
  not score.
- **Grip orientations are the household ones.** *Cup* is palm-inward, closing
  around a mug. *Overhand* is palm-down, lifting something off a table. These
  are the two orientations that everyday object handling is made of.
- **Pour is a trajectory, not a touch.** The hand is guided along a curved path
  through waypoints and the target only completes when the whole path has been
  followed — which is the controlled tipping movement that spilling a drink
  actually consists of, practised where spilling is impossible.
- **The shell gives seconds of warning**, so the movement is approached
  deliberately rather than snatched. Rushing is what causes the fumble the
  patient is afraid of.
- **Success is visible and immediate** — a ding, a shatter, floating praise from
  where the hand is. Repeated successful grasp-and-release with unambiguous
  feedback is what rebuilds the confidence that fear has eroded.
- **The workspace is the patient's own.** A target is never placed where they
  cannot get to it, so the rehearsal never produces the failure it is meant to
  reduce the fear of.
- **Difficulty can hold grip while lowering everything else.** Movements and
  mobility level are chosen independently, so grip practice can be run at 1★ —
  close, chest height, long rests — for someone who finds it daunting.

**Honest limits.** Virtual grasp has no weight, no slip and no tactile
feedback, and there is no evidence here about how far confidence built in the
headset transfers to a real mug. Treat it as graded rehearsal of the movement
pattern and a step *towards* the real task — the intended progression is
headset → real object with a therapist → real object alone.

---

## What the app does not do

Stated plainly, because the gaps matter as much as the features:

- **It is not a clinical assessment.** It records where a hand went and where
  the headset could still see it — not joint angles, not range of motion in
  degrees, and not a stage of motor recovery.
- **It does not track eye gaze.** visionOS never exposes gaze to apps; every
  "looking at" in the app is head direction.
- **It does not detect compensation.** A patient leaning their trunk to extend
  their reach registers as a longer reach. The 85% safety margin discourages
  this but does not measure it.
- **It has no export, sync or clinician portal.** All data is on the device.
- **It has no reminders or scheduling.**
- **It cannot tell a chair apart from a wheelchair, or standing from sitting.**
  It only knows where the head is; a patient who recentres while leaning gets a
  workspace built around the lean.
