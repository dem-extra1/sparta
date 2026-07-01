# Design note: per-soldier combat model

Status: **phase 4 of individual-soldier collision — largely implemented** (see
[`individual-collision-design.md`](individual-collision-design.md)). This is the
probabilistic model that resolves combat between individual soldiers; it is now wired
into **engaged melee**, which is soldier-authoritative (`SoldierMelee.resolve`). The
per-slice `> Implemented` notes below track what has landed (the land contest, wound,
knockback, prone, bracing, and stamina) and what is deferred (posture-graded bracing,
the domino cascade, and enemy collision → #201). The player-facing version lives at
[`website/combat.qmd`](../website/combat.qmd) — keep the two in sync.

The guiding principle is **emergence, not modifiers**. We do not bolt a "flanking
bonus" or an "out-of-formation debuff" onto regiment combat. Instead each soldier
carries its own state — health, stamina, footing, facing — and resolves its own
strikes against the individual in front of it. The familiar tactical truths —
flanking kills faster, spears screen, charges shatter loose lines but break on
braced ones, a surrounded man tires and falls — *fall out* of the geometry and the
per-strike rolls below, not from special cases.

## Soldier state and attributes

Each soldier carries **persistent state** that combat reads and writes every tick:

| symbol | name | meaning |
|---|---|---|
| $h \in [0, h_{\max}]$ | health | current health; the soldier dies at $h \le 0$ |
| $\sigma \in [0, \sigma_{\max}]$ | stamina | drained by acting; low stamina degrades everything |
| $\hat{n}$ | facing | unit vector the soldier faces (set by orders/movement) |
| posture | stance | one of *at ease*, *at attention*, *advancing / walking / jogging / sprinting*, *braced*, *prone* (see below); sets bracing, defence stability, the charge it deals, and stamina flow |

and **fixed attributes** from its regiment type:

| symbol | name | meaning |
|---|---|---|
| $s \in [0,1]$ | skill | training/discipline: lands blows, parries, beats shields |
| $a \in [0,1]$ | armour | fraction of a landed blow's damage absorbed (passive) |
| $b \in [0,1]$ | shield | active block strength (folds into the defence contest) |
| $\ell > 0$ | lethality | the weapon's wounding power |
| $r$ | reach | how far the weapon strikes (per-weapon, from #233) |
| $m > 0$ | mass | inertia for knockback, prone threshold, bracing (a horse is heavy) |

A starting table (tunable; maps onto the existing loadout types):

| type | $s$ | $a$ | $b$ | $\ell$ | reach | $m$ | $h_{\max}$ | $\sigma_{\max}$ |
|---|---|---|---|---|---|---|---|---|
| Spearmen | 0.75 | 0.35 | 0.65 | 0.85 | long (2.4 m) | 1.0 | 100 | 100 |
| Infantry | 0.50 | 0.45 | 0.60 | 1.00 | medium (1.3 m) | 1.0 | 110 | 100 |
| Archers  | 0.30 | 0.10 | 0.05 | 0.50 | short (0.6 m) | 0.9 |  80 |  90 |
| Cavalry  | 0.60 | 0.40 | 0.25 | 1.10 | medium (1.5 m) | 2.5 | 140 | 120 |

### Two condition factors

Health and stamina feed back into performance through two increasing factors in
$[0,1]$, used everywhere a soldier acts:

$$q(h) = \underline{q} + (1-\underline{q})\,\frac{h}{h_{\max}}
\qquad\text{(wound factor)},$$
$$g(\sigma) = \underline{g} + (1-\underline{g})\,\frac{\sigma}{\sigma_{\max}}
\qquad\text{(fatigue factor)}.$$

A fresh, unhurt soldier sits at $q = g = 1$; a near-dead or spent one drops toward
the floors $\underline{q}, \underline{g}$. There is **no discrete "injured"
state** — wounds accumulate in $h$ and degrade the soldier continuously through
$q(h)$.

## Posture (stance)

A soldier's **posture** is the single state that ties motion, bracing, defence,
and stamina together. It is set by orders and by what the soldier is doing, and it
is the dial behind both "a charge hits hard" and "a braced line stops it." The
postures, and what each one sets:

| posture | brace $b_{\mathrm{post}}$ | active defence | self-motion (charge it deals) | stamina | role |
|---|---|---|---|---|---|
| at ease | $\approx 0$ | poor | none | regen fast | out of contact, marching/resting |
| at attention | mid | full | none (planted, can pivot) | regen slow | default ready stance in contact |
| advancing / walking | low | reduced | small $c$ | neutral | pressing forward under control |
| jogging | lower | low | moderate $c$ | slow drain | closing the gap |
| sprinting (charge) | $\approx 0$ | minimal | **max $c$** | fast drain | the charge: deadly impact, but defenceless and unbraced |
| braced | **max** | full + stable | none | slow drain to hold | set to receive: best vs. knockback, prone, and a charge |
| prone | $0$ | none (armour only) | none | drain to rise | knocked down (below) |

Two consequences fall straight out of this table and matter everywhere below:

- **Motion *is* the charge.** The closing term $c$ (next section) is just the
  attacker's gait — a sprinting soldier deals a big $c$; a planted one deals none.
  A "charge" is not a special attack, it is the *sprinting* posture meeting a
  target. The faster the gait, the deadlier the blow **and** the weaker the
  sprinter's own defence and bracing — speed is bought with vulnerability.
- **Posture changes take time.** A transition costs $T_{\mathrm{post}}$ ticks (and
  going from a fast gait to *braced* costs the most). You cannot brace the instant
  a charge lands — you must be **set before** it arrives. This is the whole tactical
  game of receiving a charge: a line ordered to brace in time holds; one caught
  *at ease* or still shuffling into position is ridden down before it can plant.

## One strike: attacker $A$ on defender $D$

A strike happens when $A$'s soldier has $D$'s within reach $r_A$ on $A$'s attack
cadence. We resolve it as: a closing term, an **opposed** land contest, a wound to
health, a stamina cost on both sides, and a knockback impulse.

Notation used throughout: a subscript $A$ or $D$ tags the attacker's or defender's
value (so $s_A$ is the attacker's skill, $a_D$ the defender's armour); a hat marks a
unit vector ($\hat{u}$, $\hat{n}$); $(x)_+ = \max(x, 0)$ is the **positive part**;
and $\operatorname{clip}(x, \mathit{lo}, \mathit{hi})$ clamps $x$ to the interval
$[\mathit{lo}, \mathit{hi}]$.

### 0. Closing velocity (the charge term)

Let $\hat{u}_{A\to D}$ be the unit vector from $A$ to $D$ and $\vec{v}_A,\vec{v}_D$
their velocities. The closing speed along the strike axis is

$$v_c = \big((\vec{v}_A - \vec{v}_D)\cdot \hat{u}_{A\to D}\big)_+,
\qquad
c = v_c / v_{\mathrm{ref}},$$

the relative velocity *aimed at the target*, clamped non-negative and normalised by
$v_{\mathrm{ref}}$, a reference gallop speed (so $c \approx 1$ at a full charge).
This is exactly the attacker's **posture** in motion: a
planted (*braced* / *at attention*) fighter has $c = 0$, an *advancing* one a small
$c$, a *sprinting* cavalryman a large $c$. The single quantity $c$ feeds the hit
contest, the damage, **and** the knockback below — closing fast makes you harder to
evade, hit harder, and shove further, all at once (and, per the posture table,
leaves the sprinter's own defence and bracing near zero while it does).

**Closing speed belongs to the *pair*, not the attacker — it is symmetric and
cumulative.** The geometry flips both the axis and the velocity difference, so the
defender sees the *same* $c$ when it strikes back:

$$\big((\vec{v}_D - \vec{v}_A)\cdot \hat{u}_{D\to A}\big)_+
= \big((\vec{v}_A - \vec{v}_D)\cdot \hat{u}_{A\to D}\big)_+ = v_c.$$

So **every blow traded during the closing carries $c$, in either direction**, and
head-on approach speeds **add**. A charge recipient who also strikes — or merely
holds a spear into the rush — lands its own blow with the full closing $c$: the
charger impales itself on the presented point (its own momentum turned against it).
And two bodies closing head-on sum their speeds into one large shared $c$, so a
**mutual charge — cavalry into cavalry — is the deadliest exchange in the game**:
both sides strike, wound, and knock back at maximal force on the same tick.

### 1. The land contest (opposed roll, facing-gated)

The blow does not roll against a fixed number — it is an **opposed roll** of the
attacker's offence against the defender's **active defence** (footwork, parry,
shield, deflection). Active defence only works against blows the defender can see
and meet:

$$\mathcal{A} = s_A\,q(h_A)\,g(\sigma_A) + \mu\,c,$$
$$\mathcal{D} = \phi_D\,\big(s_D + \lambda\,b_D\big)\,q(h_D)\,g(\sigma_D),
\qquad
\phi_D = \big(\hat{n}_D \cdot \hat{u}_{D\to A}\big)_+ .$$

Here $\mu \ge 0$ weights closing speed into the attack (how much a charge helps it
land), and $\lambda \ge 0$ weights the shield into active defence. $\phi_D$ is the
**facing gate**: the dot of the defender's facing with the
direction the blow comes from, clamped to non-negative. A blow from the front
($\phi_D \to 1$) meets full active defence; a blow from the flank meets little; a
blow to the **back** ($\phi_D = 0$) meets *none* — no parry, no shield block, no
deflection, only armour. The blow lands with

$$p_{\mathrm{land}} = \operatorname{clip}\!\Big(L\big(\beta\,(\mathcal{A} - \mathcal{D})\big),\; p_{\min},\; p_{\max}\Big),
\qquad
L(x) = \frac{1}{1 + e^{-x}}.$$

where $L$ is the logistic (so a contest score of $0$ gives an even chance),
$\beta > 0$ sets how sharply the gap $\mathcal{A} - \mathcal{D}$ swings the odds, and
the clip floor and ceiling $p_{\min}, p_{\max}$ bound the result. Evenly-matched,
fresh, front-facing soldiers land near $L(0) = \tfrac12$; a veteran against an
exhausted or back-turned foe lands far more often. The clip keeps a blow from ever
being automatic or impossible. **Shield and skill defend only from the
front and only while you have the stamina to use them; armour does not care.**

### 2. Wound: damage to the health pool

A blow that lands wounds. We do **not** roll kill-or-not; we subtract damage from
the defender's health. Its size is the weapon's lethality, amplified by closing
momentum, blunted by armour, and scaled by the attacker's own condition:

$$\Delta h = D_0\,\ell_A\,(1 + c)\,(1 - a_D)\,q(h_A)\,g(\sigma_A),
\qquad
h_D \leftarrow h_D - \Delta h.$$

$D_0 > 0$ is a base damage scale (the wound a baseline weapon, $\ell = 1$, deals to
an unarmoured, standing target). The soldier **dies** when $h_D \le 0$. Until then it fights on at reduced capacity
through $q(h_D)$ — wounds compound, because a hurt soldier both defends and hits
worse, so the second and third wounds come easier than the first. Armour $a_D$ is
the only thing that protects a back-turned or downed man, since it sits outside the
facing-gated contest.

### 3. Stamina: attacking, defending, and rising all cost

> **Implemented (#310 slice D):** `SoldierCombat.stamina_factor` (g(σ) in
> [COND_STAMINA_FLOOR, 1]) and per-soldier `_sim_soldier_stamina` arrays in `Unit`.
> `SoldierBodies.seed` seeds stamina at `max_stamina`; `SoldierBodies.step` regens all
> soldiers at `RHO_STAMINA`/sec (engaged included; their net change is offset by melee drain)
> and drains `κ_p` the tick a prone soldier rises.
> `SoldierMelee.resolve` multiplies `q(h) * g(σ)` into `cond_a` / `cond_d`, drains
> `κ_a` per strike thrown, and drains `κ_d·φ·(1+c)` per blow met.
> Posture-dependent regen rates deferred to the posture slice.

Every action spends stamina; rest restores it. In one tick:

$$\sigma_A \mathrel{-}= \kappa_a \qquad\text{(each strike thrown)},$$
$$\sigma_D \mathrel{-}= \kappa_d\,\phi_D\,(1 + c) \qquad\text{(meeting a blow you can see; a charge costs more)},$$
$$\sigma \mathrel{-}= \kappa_p \qquad\text{(the tick a soldier rises from prone)},$$
$$\sigma \mathrel{+}= \rho_\sigma(\text{posture})\,\Delta t \qquad\text{(posture baseline: fast } at\ ease,\ \text{slow } at\ attention,\ \text{negative while } sprinting/\text{rising; capped at } \sigma_{\max}).$$

Here $\kappa_a, \kappa_d, \kappa_p \ge 0$ are the stamina costs of a strike, of
meeting one blow, and of rising from prone; $\rho_\sigma(\text{posture})$ is the
posture-set regen rate; and $\Delta t$ is the tick duration. Defending is not free: a soldier under sustained assault spends $\kappa_d$ on
**every** incoming blow it meets, so its stamina falls, $g(\sigma)$ falls, and its
active defence $\mathcal{D}$ collapses — after which blows land freely. This is the
engine behind several tactics: a **surrounded** soldier meets many blows per tick,
exhausts fast, and is then cut down; a man knocked **prone** pays $\kappa_p$ to
stand and defends nothing while down.

### 4. Knockback impulse

Every committed strike imparts an impulse along the strike axis, scaled by the
blow's force, inversely by the defender's mass, and reduced (not erased) when the
blow is actively defended rather than landing clean:

$$J = J_0\,\frac{\ell_A\,(1 + c)}{m_D}\;\eta,
\qquad
\eta = \begin{cases} \eta_{\mathrm{def}} \in (0,1) & \text{defended (turned aside)} \\ 1 & \text{landed.} \end{cases}$$

$J_0 > 0$ is a base impulse scale, and $\eta$ is the fraction of momentum
transmitted — $\eta_{\mathrm{def}}$ for a defended blow, $1$ for a clean landing.
The struck soldier is displaced by $J\,\hat{u}_{A\to D}$; the formation's bounded
arrival dynamics then decelerate and return it over the following ticks. A blocked blow draws no blood but still
shoves — which is how a spear wall pushes a stalled enemy back even when it can't
wound it.

> **Implemented (#201 slice A):** `SoldierCombat.knockback_impulse` and the per-type
> `mass` in `profile_for`, wired into `SoldierMelee` as one mass-scaled impulse per
> in-reach strike (η = 1 landed, `ETA_DEFENDED` otherwise). Velocity-only — the body
> integrates it, never a position snap. (Prone/knockdown in slice B; depth-buttressed
> bracing in slice C; the rearward domino cascade is a follow-up.)

## Going prone and getting up

*Prone* is the involuntary posture: a large enough impulse knocks the defender off
its feet. Bracing (itself posture-driven) and mass raise the threshold; the fall is
probabilistic:

$$p_{\mathrm{prone}} = \operatorname{clip}\!\Big(\frac{J - J_{\mathrm{fall}}\,(1 + \mathrm{br}_D)\,m_D}{J_{\mathrm{scale}}},\; 0,\; p_{\mathrm{prone}}^{\max}\Big).$$

where $J_{\mathrm{fall}} > 0$ is the base knockdown threshold (an impulse below it
never fells a man), $J_{\mathrm{scale}} > 0$ how fast the fall chance climbs with
surplus impulse, and $p_{\mathrm{prone}}^{\max} \le 1$ caps it (no single blow is a
certain knockdown). A **prone** soldier has $\phi_D \to 0$ in every contest (no active defence — only
armour saves it), $b_{\mathrm{post}} = 0$, cannot strike, and must spend
$T_{\mathrm{up}}$ ticks and $\kappa_p$ stamina to return to *at attention*. So a
charge that bowls men over does not just push them — it lays them down defenceless
and tires them out as they scramble up, which is when the follow-up rank kills them.
A **braced**, heavy, set line clears the prone threshold far less often and stays on
its feet.

> **Implemented (#201 slice B, visual in #300):** `SoldierCombat.prone_chance`
> (mass-raised threshold) and a per-soldier `_sim_prone` timer. In `SoldierMelee` a felled
> defender loses active defence (`φ_D → 0`) and a felled attacker can't strike;
> `SoldierBodies` decays the timer so a soldier rises after `PRONE_RISE_TIME`. Prone
> soldiers are rendered as dark horizontal slivers (mark LOD) or lying-on-side silhouettes
> (figure LOD) via per-instance MultiMesh transforms and tinting. The stamina cost of rising
> (`κ_p`) is in slice D. (Bracing `br_D` wired in slice C.)

## Bracing and the knockback chain (domino)

A knocked-back soldier collides with whoever is behind it. Two things resist the
impulse: the struck man's own bracing **and the braced comrades behind him**. In a
tight formation a set man buttresses the one in front — he physically backs him up —
so the front rank's *effective* capacity is its own plus an attenuated sum down the
file behind it:

$$C_i = J_{\mathrm{cap}}\Big(\mathrm{br}_i + \sum_{k\ge1}\zeta^{\,k}\,\mathrm{br}_{i+k}\,T_{i,k}\Big),
\qquad 0 < \zeta \le 1,$$

where $J_{\mathrm{cap}} > 0$ is the impulse a fully-set man ($\mathrm{br} = 1$) can
absorb, $\zeta \in (0, 1]$ is the per-rank support-transmission efficiency, and
$T_{i,k} \in \{0,1\}$ flags whether ranks $i \dots i+k$ form an **unbroken, tight,
braced, front-facing** file — support transmits through set men in contact, and a
gap, a loose or unbraced man, or one not facing the blow sets $T = 0$ from there
back. A lone braced man has $C_i =
J_{\mathrm{cap}}\,\mathrm{br}_i$; a **deep** braced phalanx sums down the column, so
the front rank resists far more than any one man could. That is the historical depth
effect (rear ranks bracing into the front), emergent from support — not a "depth
bonus."

Bracing stays **finite**: only the surplus over $C_i$ passes on. Writing $J_i$ for
the impulse reaching the $i$-th soldier in the chain:

$$J_{i+1} = \tau\,\big(J_i - C_i\big)_+,
\qquad 0 < \tau < 1,$$

where $\tau$ is the per-contact attenuation (the impulse fades as it passes
rearward). A blow **below** the front column's capacity
$C_i$ dies there — the charge breaks on the braced depth. A blow that **exceeds** it
overwhelms the front man (he is shoved, and rolls $p_{\mathrm{prone}}$ on his own
footing — a hard enough $J$ topples him despite bracing), the supporting file has
spent its backing, and the surplus dominoes rearward, re-resisted by whatever set
men remain. So a strong enough charge still punches *through* — but now it must beat
the **whole braced column**, not one man. Each soldier the impulse reaches rolls
$p_{\mathrm{prone}}$ on its own footing, toppling a row of unsupported men like
dominoes. The per-soldier bracing term is itself emergent:

$$\mathrm{br} = \operatorname{clip}\!\big(\mathrm{br}_0
  + b_{\mathrm{post}}
  + w_f\,[\text{formation} = \textsf{TIGHT}]
  + w_d\,(\hat{n}\cdot\hat{u}_{\text{incoming}})_+ ,\; 0,\; 1\big),$$

i.e. starting from a baseline $\mathrm{br}_0$, a soldier is more braced in a **set
posture** ($b_{\mathrm{post}}$ from the posture table — max when *braced*, near zero
when *sprinting*, *at ease*, or *prone*), in **tight formation** (weight $w_f$ on the
indicator $[\,\text{formation} = \textsf{TIGHT}\,]$, which is $1$ when its condition
holds and $0$ otherwise), and **facing into** the blow (weight $w_d$ on the last
term — the facing $\hat{n}$ dotted with the incoming direction, clamped
non-negative — the *same* facing that gates active defence). A loose, flanked, sprinting, or routing
file has $\mathrm{br}\to 0$, dominoes, and goes down; a *braced*, tight,
front-facing shield wall has $\mathrm{br}\to 1$ and holds.

> **Implemented (#201 slice C):** `SoldierCombat.brace_depth` and `brace_capacity` compute
> the depth-buttressed column capacity $C_i$. `Unit.soldier_brace()` returns `BRACE_SET` (1)
> when the regiment is engaged and not a skirmish line, 0 otherwise (binary; graded posture
> is the posture slice). In `SoldierMelee.resolve` the struck soldier's file column is walked
> rearward (front-facing blows only — $\phi = 0$ gives no buttress), and the sub-capacity
> shove is absorbed before applying velocity; `brace_depth` is also passed to `prone_chance`
> to raise the knockdown threshold for a set phalanx. **Deferred:** the rearward domino
> cascade ($J_{i+1} = \tau(J_i - C_i)_+$, surplus toppling rear ranks) is a follow-up. The
> graded `br` formula above (posture weights $b_{\mathrm{post}}$, $w_f$, $w_d$) is also
> deferred to the posture slice; `br` is binary here.

> **Implemented (#201 slice D):** `SoldierCombat.stamina_factor` ($g(\sigma)$) and the
> per-soldier `_sim_soldier_stamina` pool. In `SoldierMelee.resolve`, `cond_a`/`cond_d`
> are now $q(h)\,g(\sigma)$ — the full two-factor condition. Every strike costs the
> attacker $\kappa_a$; every met blow costs the defender $\kappa_d\,\phi\,(1+c)$ (zero
> for prone or flanked defenders). `SoldierBodies.step` regens stamina at $\rho_\sigma$
> per second and charges $\kappa_p$ on the tick a soldier rises from prone. **Deferred:**
> posture-dependent regen ($\rho_\sigma(\text{posture})$ table) to the posture slice;
> stamina HUD to a follow-up.

## Receiving a charge

A charge is the **same** mechanism on the receiving end, with the charger's large
$c$ lighting up every term at once: (i) the closing speed makes the charger's blow
harder to evade ($\mu c$ in $\mathcal{A}$), (ii) deadlier ($1+c$ in $\Delta h$),
and (iii) a heavier shove ($1+c$ in $J$) that is more likely to knock men prone.
Against an **unbraced** line ($\mathrm{br}\to 0$) the impulse ripples several ranks
deep and lays them out — the line is bowled over and butchered on the ground.
Against a **braced** line — one ordered into the *braced* posture **in time**, a set
spear hedge with shields locked, facing the charge ($\mathrm{br}\to 1$), and **deep
enough** that the rear ranks buttress the front (a large column capacity $C$) — the
impulse is absorbed at the front rank, few men fall, and little passes back: the line
holds. A shallow braced line can still be punched through; depth is what makes the
hedge unbreakable. The timing is the crux: because a posture change costs
$T_{\mathrm{post}}$, a line still *at ease* or shuffling into place when the horse
arrives cannot plant in time and is ridden down, while the same line set a moment
earlier holds. And because the spear's reach $r$ exceeds the horseman's, the
spearman strikes *first*, and the impaling closing speed makes $c$ work **against**
the rider. None of this is special-cased — it is the posture timing, the reach, the
opposed rolls, the prone threshold, and the bracing chain acting together.

## Why the tactics emerge

- **Flanking / surround.** A soldier with enemies on two or three sides (a) is in
  reach of more attackers, so it is the target of more strikes per tick, (b) meets
  more blows and burns stamina faster, so its active defence collapses, and (c)
  takes blows it cannot face — flank and rear strikes see $\phi_D \to 0$ and only
  armour answers them. Three emergent effects, one cause: *enemies it cannot face,
  in numbers it cannot out-last*. No "rear bonus" multiplier exists.
- **Don't turn your back.** Facing gates both active defence and bracing. A soldier
  fighting to its front is hard to hit and hard to topple; the instant it turns
  (rout, or caught from behind) its defence and footing evaporate and it is run
  down. Routing is lethal because of this, not because of a morale damage modifier.
- **Screening (spears).** A spearman's reach holds shorter-weapon foes beyond their
  own reach, so they are struck without striking back, and the knockback keeps
  shoving them out. A spear line screens whatever stands behind it.
- **Form deep, form tight.** Braced men in a tight file back up the rank in front,
  so the front line's resisting capacity $C$ is the *column's*, not one man's — a
  deep, set phalanx breaks a charge a shallow one can't. The cost is that depth and
  tightness trade against frontage and mobility, and the support evaporates the
  moment the file loosens, opens a gap, or is hit from a side it isn't facing.
- **Closing speed cuts both ways.** The charge bonus belongs to the pair, so
  meeting a charge with a presented spear (or a counter-charge) turns the enemy's
  own momentum against it — the charger runs onto the point at full $c$. A **mutual
  cavalry charge** is therefore mutually annihilating (both sides hit at combined
  speed); prefer to receive a charge on **set spears**, which strike first at the
  same shared $c$, over meeting it horse-to-horse.
- **Shields and armour** turn would-be wounds into blocked shoves (shield, from the
  front) or glancing hits (armour, from any angle), so a heavy, shielded line
  grinds slowly and survives; light troops caught in the press evaporate.
- **Skill and freshness** compound at both ends — landing more, defending more,
  tiring slower — so rested veterans beat raw or winded levies out of proportion to
  their numbers. Pace the fight: a line that has been holding all battle defends
  worse than one just committed.

## Determinism

Combat is part of the deterministic simulation. Every random draw above — the land
contest, the wound, the prone roll — comes from the single seeded `Replay.rng`
stream, drawn in a fixed order (soldiers resolved in global-id order within the
per-tick soldier pass, exactly like the separation tie-breaks). Per-soldier health,
stamina, facing, and footing are ordinary simulation state, advanced the same way
every run. Same seed + same orders reproduce the same battle, blow for blow, on the
same build. The constants
($v_{\mathrm{ref}}, \mu, \lambda, \beta, p_{\min}, p_{\max}, \underline{q}, \underline{g},
D_0, J_0, \eta_{\mathrm{def}}, J_{\mathrm{fall}}, J_{\mathrm{scale}}, p_{\mathrm{prone}}^{\max},
T_{\mathrm{up}}, T_{\mathrm{post}}, \kappa_a, \kappa_d, \kappa_p, \tau, J_{\mathrm{cap}},
\zeta, \mathrm{br}_0, w_f, w_d$), together with the per-posture tables
$b_{\mathrm{post}}(\cdot)$ and $\rho_\sigma(\cdot)$, are balance knobs tuned against
playtests; this note fixes the *form* of the model, not the final values.
