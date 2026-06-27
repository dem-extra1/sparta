# Design note: per-soldier combat model

Status: **design spec for phase 4** of individual-soldier collision (see
[`individual-collision-design.md`](individual-collision-design.md)). This is the
probabilistic model that resolves combat between individual soldiers once the
soldier layer is authoritative. The player-facing version lives at
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
| prone | footing | knocked down: no active defence, must spend time and stamina to rise |

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

## One strike: attacker $A$ on defender $D$

A strike happens when $A$'s soldier has $D$'s within reach $r_A$ on $A$'s attack
cadence. We resolve it as: a closing term, an **opposed** land contest, a wound to
health, a stamina cost on both sides, and a knockback impulse.

### 0. Closing velocity (the charge term)

Let $\hat{u}_{A\to D}$ be the unit vector from $A$ to $D$ and $\vec{v}_A,\vec{v}_D$
their velocities. The closing speed along the strike axis is

$$v_c = \big((\vec{v}_A - \vec{v}_D)\cdot \hat{u}_{A\to D}\big)_+,
\qquad
c = v_c / v_{\mathrm{ref}},$$

the relative velocity *aimed at the target*, normalised to a reference gallop and
clamped non-negative. A standing fighter has $c = 0$; a cavalryman at full charge
into a stationary line has $c$ large. The single quantity $c$ feeds the hit
contest, the damage, **and** the knockback below — closing fast makes you harder to
evade, hit harder, and shove further, all at once.

### 1. The land contest (opposed roll, facing-gated)

The blow does not roll against a fixed number — it is an **opposed roll** of the
attacker's offence against the defender's **active defence** (footwork, parry,
shield, deflection). Active defence only works against blows the defender can see
and meet:

$$\mathcal{A} = s_A\,q(h_A)\,g(\sigma_A) + \mu\,c,$$
$$\mathcal{D} = \phi_D\,\big(s_D + \lambda\,b_D\big)\,q(h_D)\,g(\sigma_D),
\qquad
\phi_D = \big(\hat{n}_D \cdot \hat{u}_{D\to A}\big)_+ .$$

$\phi_D$ is the **facing gate**: the dot of the defender's facing with the
direction the blow comes from, clamped to non-negative. A blow from the front
($\phi_D \to 1$) meets full active defence; a blow from the flank meets little; a
blow to the **back** ($\phi_D = 0$) meets *none* — no parry, no shield block, no
deflection, only armour. The blow lands with

$$p_{\mathrm{land}} = \operatorname{clip}\!\Big(L\big(\beta\,(\mathcal{A} - \mathcal{D})\big),\; p_{\min},\; p_{\max}\Big),
\qquad
L(x) = \frac{1}{1 + e^{-x}}.$$

Evenly-matched, fresh, front-facing soldiers land near $L(0) = \tfrac12$; a veteran
against an exhausted or back-turned foe lands far more often. The clip keeps a blow
from ever being automatic or impossible. **Shield and skill defend only from the
front and only while you have the stamina to use them; armour does not care.**

### 2. Wound: damage to the health pool

A blow that lands wounds. We do **not** roll kill-or-not; we subtract damage from
the defender's health. Its size is the weapon's lethality, amplified by closing
momentum, blunted by armour, and scaled by the attacker's own condition:

$$\Delta h = D_0\,\ell_A\,(1 + c)\,(1 - a_D)\,q(h_A),
\qquad
h_D \leftarrow h_D - \Delta h.$$

The soldier **dies** when $h_D \le 0$. Until then it fights on at reduced capacity
through $q(h_D)$ — wounds compound, because a hurt soldier both defends and hits
worse, so the second and third wounds come easier than the first. Armour $a_D$ is
the only thing that protects a back-turned or downed man, since it sits outside the
facing-gated contest.

### 3. Stamina: attacking, defending, and rising all cost

Every action spends stamina; rest restores it. In one tick:

$$\sigma_A \mathrel{-}= \kappa_a \qquad\text{(each strike thrown)},$$
$$\sigma_D \mathrel{-}= \kappa_d\,\phi_D\,(1 + c) \qquad\text{(meeting a blow you can see; a charge costs more)},$$
$$\sigma \mathrel{-}= \kappa_p \qquad\text{(the tick a soldier rises from prone)},$$
$$\sigma \mathrel{+}= \rho_\sigma\,\Delta t \qquad\text{(regen when not acting, capped at } \sigma_{\max}).$$

Defending is not free: a soldier under sustained assault spends $\kappa_d$ on
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

The struck soldier is displaced by $J\,\hat{u}_{A\to D}$; the formation spring then
reels it back over the following ticks. A blocked blow draws no blood but still
shoves — which is how a spear wall pushes a stalled enemy back even when it can't
wound it.

## Footing: going prone and getting up

A large enough impulse knocks the defender off its feet. Bracing and mass raise the
threshold; the fall is probabilistic:

$$p_{\mathrm{prone}} = \operatorname{clip}\!\Big(\frac{J - J_{\mathrm{fall}}\,(1 + \mathrm{br}_D)\,m_D}{J_{\mathrm{scale}}},\; 0,\; p_{\mathrm{prone}}^{\max}\Big).$$

A **prone** soldier has $\phi_D \to 0$ in every contest (no active defence — only
armour saves it), cannot strike, and must spend $T_{\mathrm{up}}$ ticks and
$\kappa_p$ stamina to rise. So a charge that bowls men over does not just push
them — it lays them down defenceless and tires them out as they scramble up, which
is when the follow-up rank kills them. A **braced**, heavy, set line clears the
prone threshold far less often and stays on its feet.

## Bracing and the knockback chain (domino)

A knocked-back soldier collides with whoever is behind it. The impulse propagates
rearward through the file, attenuating at each contact and being absorbed by braced
men. Writing $J_i$ for the impulse reaching the $i$-th soldier in the chain:

$$J_{i+1} = \tau\,\big(1 - \mathrm{br}_i\big)\,J_i,
\qquad 0 < \tau < 1,$$

so the impulse passed back $n$ ranks is at most $\tau^{\,n} J_0$ — and a single
braced man ($\mathrm{br}\to 1$) snaps the chain. Each soldier the impulse reaches
also rolls $p_{\mathrm{prone}}$ against its *own* footing, so a hard enough hit
topples a row of unbraced men like dominoes. The bracing term is itself emergent:

$$\mathrm{br} = \operatorname{clip}\!\big(\mathrm{br}_0
  + w_s\,[\text{stance} = \textsf{HOLD}]
  + w_f\,[\text{formation} = \textsf{TIGHT}]
  + w_d\,(\hat{n}\cdot\hat{u}_{\text{incoming}})_+ ,\; 0,\; 1\big),$$

i.e. a soldier is more braced when it is holding, in tight formation, and **facing
into** the blow (the last term is the facing $\hat{n}$ dotted with the incoming
direction, clamped non-negative — the *same* facing that gates active defence). A
loose, flanked, or routing file has $\mathrm{br}\to 0$, dominoes, and goes down; a
set, front-facing shield wall has $\mathrm{br}\to 1$ and holds.

## Receiving a charge

A charge is the **same** mechanism on the receiving end, with the charger's large
$c$ lighting up every term at once: (i) the closing speed makes the charger's blow
harder to evade ($\mu c$ in $\mathcal{A}$), (ii) deadlier ($1+c$ in $\Delta h$),
and (iii) a heavier shove ($1+c$ in $J$) that is more likely to knock men prone.
Against an **unbraced** line ($\mathrm{br}\to 0$) the impulse ripples several ranks
deep and lays them out — the line is bowled over and butchered on the ground.
Against a **braced** line — a set spear hedge, shields locked, facing the charge
($\mathrm{br}\to 1$, high effective $m$) — the impulse is absorbed at the front
rank, few men fall, and little passes back: the line holds. And because the spear's
reach $r$ exceeds the horseman's, the spearman strikes *first*, and the impaling
closing speed makes $c$ work **against** the rider. None of this is special-cased —
it is the reach, the opposed rolls, the prone threshold, and the bracing chain
acting together.

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
T_{\mathrm{up}}, \kappa_a, \kappa_d, \kappa_p, \rho_\sigma, \tau, \mathrm{br}_0, w_s, w_f, w_d$)
are balance knobs, tuned against playtests; this note fixes the *form* of the
model, not the final values.
