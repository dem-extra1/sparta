# Dev notes: related open-source games

A **running review** of open-source (and a few proprietary) strategy games next
to Sparta, so we don't re-research the landscape every time we want to borrow an
idea, some code, or art. Append to it as new projects surface — this is a living
document, the design-and-code sibling of the art catalogue in
[`docs/asset-sources.md`](asset-sources.md).

Two questions for each game:

1. **Can we learn anything from its design?**
2. **Does its licence let us borrow its code or art when that helps?**

## The one rule that decides everything: can we reuse it?

Sparta's **code is MIT-licensed** (see [`LICENSE`](../LICENSE)) — permissive. That
cuts both ways:

- **Copyleft code (GPL / AGPL) is reference-only for us.** Copying GPL source into
  Sparta would force the *combined* work — Sparta's code included — to be
  relicensed GPL. We are not doing that for a prototype. So for any GPL project we
  can **read it, learn from it, and reimplement clean-room**, but we cannot lift
  its code. Most of the open-source strategy world is GPL, so this is the common
  case, not the exception.
- **Permissive / public-domain code (MIT, BSD, Apache, PD) we *can* vendor**, keeping
  the upstream notice. This is rare in this genre.
- **Proprietary projects and commercial-game mods give us design lessons only** — no
  code, no art.

**Art is licensed separately from code**, and the rules for bundling an art file
are the ones already written down in [`docs/asset-sources.md`](asset-sources.md):
CC0 and CC-BY / CC-BY-SA are bundle-safe (CC-BY/SA need attribution; `-SA`
derivatives stay `-SA`); `NC`, `ND`, freeware-no-redistribution, and
commercial-game assets are reference-only. Note that
[`PLAN.md`](../PLAN.md)'s *Locked decisions* currently say **CC0-only** for shipped
art, which is stricter than the asset catalogue — so adopting a CC-BY-SA art set
(e.g. 0 A.D.'s, below) would be a deliberate policy change to agree on first, not
an automatic yes.

**Legend (code reuse into Sparta's MIT codebase)**
- ✅ **vendorable** — MIT / BSD / Apache / public domain; copy with the upstream notice.
- ⛔ **reference-only (copyleft)** — GPL / AGPL; read and reimplement, never copy in.
- 🚫 **design-only** — proprietary or a commercial-game mod; no code or art to take.

(For the **art** column, the ✅ / 🅰 / ⛔ tags mean the same as in
[`asset-sources.md`](asset-sources.md): ✅ CC0, 🅰 CC-BY/CC-BY-SA with attribution,
⛔ not redistributable.)

---

## The shortlist

| Game | Type | Code licence | Art / data licence | Code | Art | Relevance to Sparta |
| --- | --- | --- | --- | :---: | :---: | --- |
| [0 A.D.](https://play0ad.com/) | Real-time strategy, ancient warfare | GPL v2 (or later) | CC-BY-SA 3.0 | ⛔ | 🅰 | **Very high** — real-time ancient battles, formations, unit movement, economy |
| [Freeciv](https://github.com/freeciv/freeciv) | Turn-based 4X | GPL v2 (or later) | mixed (GPL / CC-BY-SA per file) | ⛔ | 🅰 (verify each) | Medium-high — campaign/saga 4X; data-driven *rulesets* architecture |
| [OpenCiv](https://github.com/RyanGrieb/OpenCiv) | Browser turn-based 4X | **MIT** | per-repo (verify) | ✅ | verify | Medium — MIT so code is vendorable, but TypeScript/web, turn-based |
| [C-evo](https://en.wikipedia.org/wiki/C-evo) (original) | Turn-based 4X | source **public domain** | graphics freeware | ✅ | ⛔ | Medium — pluggable-AI module API; PD source, but Pascal/Delphi |
| [C-evo: vn971 port](https://github.com/vn971/cevo) | Turn-based 4X | GPL-3.0 | — | ⛔ | — | Same design lessons; this port is GPL + archived (Nov 2024) |
| [Divide et Impera](https://divideetimperamod.com/) | Total-overhaul **mod** for Total War: Rome II | proprietary (built on CA/Sega's game) | proprietary | 🚫 | 🚫 | **High for design only** — historical realism, supply/population/reform systems, 2000+ unit rosters |
| [awesome-paradox](https://github.com/js00070/awesome-paradox) | Curated list of Paradox-related projects | n/a (link list) | n/a | — | — | Pointers to grand-strategy / **dynasty** design and OSS reimplementations |

---

## Per-game notes

### 0 A.D. (Wildfire Games)

The closest open-source relative to Sparta's battle layer: a real-time strategy
game set in **ancient warfare** (the same 500 BC – 1 AD world Sparta draws on),
with land battles of hundreds of units, formations, ranged-vs-melee interplay,
territory, and an economy. Released July 2009; version 28 "Boiorix" (Feb 2026) is
the first non-alpha build.

- **Design to learn from:** formation handling and how a unit's slot in a
  formation interacts with steering; large-scale pathfinding and unit movement
  (directly relevant to our [collision design pillar](../PLAN.md) and issues
  [#164](https://github.com/Lacaedemon/sparta/issues/164) /
  [#192](https://github.com/Lacaedemon/sparta/issues/192)); how an economy and tech
  tree sit under a battle layer (relevant to the campaign/saga arc).
- **Licence:** code **GPL v2 or later** → ⛔ reference-only; we read the engine
  (Pyrogenesis) for ideas but cannot copy it into Sparta. **Art and data are
  CC-BY-SA 3.0** → 🅰 bundle-safe *with attribution and share-alike*, exactly like
  the LPC sets already noted in [`asset-sources.md`](asset-sources.md). This is the
  single biggest art opportunity in the list: a large, directly-relevant
  ancient-warfare library — gated only by PLAN.md's current CC0-only stance.

### Freeciv

A mature turn-based 4X in the Civilization lineage. The standout lesson is
architectural: gameplay rules live in **data-driven *rulesets*** (units,
buildings, techs, governments as editable data files), so the same engine can run
"civ2civ3", a classic ruleset, or a custom one without code changes.

- **Design to learn from:** the ruleset pattern is a strong model for Sparta's own
  data-driven content — we already load campaigns from JSON
  ([`data/campaigns/`](../data/campaigns)); the same idea generalises to unit and
  faction definitions for the campaign/saga layer
  ([#126](https://github.com/Lacaedemon/sparta/issues/126),
  [#147](https://github.com/Lacaedemon/sparta/issues/147)). Also a reference for
  long-running 4X turn structure and AI.
- **Licence:** code **GPL v2 or later** → ⛔ reference-only. Bundled art and data
  are a mix of GPL and CC-BY-SA per file → verify each before treating any single
  asset as 🅰.

### OpenCiv (RyanGrieb)

A modern, **MIT-licensed** browser 4X (TypeScript/Node) inspired by Civ V. The MIT
licence is what sets it apart here: its code is the one project on this list we
could legitimately **vendor** into Sparta.

- **Design to learn from:** clean modern take on tile interaction, camera/zoom
  controls, and turn progression.
- **Caveat:** it is TypeScript targeting the browser and is turn-based, while
  Sparta is GDScript/Godot and real-time tactical — so the practical reuse is
  *patterns and structure*, not literal code transplants. Its design value
  outweighs its (technically permitted) code-reuse value.

### C-evo

A turn-based 4X notable for its **AI architecture**: AI players are separate,
swappable modules talking to the engine through a defined API. The original by
Steffen Gerlach puts its **source code in the public domain** (graphics are
freeware), so the original source is, uniquely, freely reusable.

- **Design to learn from:** the pluggable-AI-module boundary is a clean model for
  [#135](https://github.com/Lacaedemon/sparta/issues/135) (recruitable AI
  subcommanders given higher-level orders) — define a narrow command API and let an
  AI "commander" drive units through it.
- **Licence nuance:** the **original** source is public domain → ✅ vendorable in
  principle, but it's Pascal/Delphi, so porting to GDScript is a rewrite, not a
  copy. The maintained [`vn971/cevo`](https://github.com/vn971/cevo) port is
  **GPL-3.0** (and archived since Nov 2024) → ⛔; if we ever wanted the code, go to
  the PD original, not the GPL fork. Graphics are freeware → ⛔, never bundle.

### Divide et Impera

Not a standalone game: a **total-overhaul mod for Total War: Rome II** (a
commercial Creative Assembly / Sega title). It rebuilds the ancient-warfare
experience around historical authenticity — a custom population system, a supply
system, a reforms system, 2000+ hand-built unit rosters, and reworked battle AI
and unit behaviour.

- **Design to learn from:** a rich source of *what realistic ancient warfare feels
  like* — supply lines, population, and believable unit behaviour. Directly informs
  [#201](https://github.com/Lacaedemon/sparta/issues/201) (physics-based battles)
  and the broader realism goals.
- **Licence:** it is built on a proprietary game and its assets → 🚫 **design
  inspiration only**. We take none of its code or art; this matches PLAN.md's
  explicit "**not** commercial-game mod assets" warning.

### awesome-paradox

A curated list of open-source projects around **Paradox Interactive** grand-strategy
games (Crusader Kings, Europa Universalis, Victoria, Hearts of Iron) — mods, save
converters, parsers, and reimplementations.

- **Design to learn from:** Paradox's **dynasty/character** systems (Crusader Kings)
  are the clearest commercial model for Sparta's "**dynastic** grand-strategy" pitch
  and the saga layer ([#126](https://github.com/Lacaedemon/sparta/issues/126)). Two
  list entries are open-source reimplementations of Victoria II — **OpenVic** and
  **Project Alice** — worth studying for how a deep grand-strategy simulation is
  structured in open code (check each project's own licence before reusing code).
- **Licence:** the list itself is just links; the games it orbits are proprietary,
  so most mods build on closed engines. Treat as a reading list, not a code source.

---

## Others worth a look

The same pattern repeats across the open-source strategy ecosystem — **GPL code,
often CC-BY-SA art** — so all of these are ⛔ for code reuse and 🅰 (verify) for
art:

- **The Battle for Wesnoth** (GPL v2; art CC-BY-SA) — turn-based tactics with a
  strong data-driven scenario/campaign system (WML). Good reference for
  externalised content.
- **Warzone 2100** (GPL v2; assets CC0 / CC-BY-SA) — real-time strategy; one of the
  more permissively-arted GPL projects.
- **OpenRA** (GPL v3) — a modernised RTS engine with a well-regarded multiplayer and
  **replay** architecture, relevant to Sparta's deterministic replay system
  ([`scripts/Replay.gd`](../scripts/Replay.gd), [`REPLAY.md`](../REPLAY.md)).
- **Beyond All Reason / Recoil (Spring)** (GPL) — very large-scale RTS; a reference
  for unit counts and movement/physics at scale
  ([#201](https://github.com/Lacaedemon/sparta/issues/201)).

---

## Bottom line

- **Code:** the genre is overwhelmingly GPL, and Sparta is MIT, so treat 0 A.D.,
  Freeciv, Wesnoth, OpenRA, Spring, and the `vn971/cevo` port as **design and
  architecture references — read, learn, reimplement clean-room; never copy code
  in.** The only code we could legitimately vendor is **OpenCiv (MIT)** and the
  **original C-evo (public-domain source)**, and both are different
  engines/languages and turn-based, so their design value beats their code value.
- **Art:** the best opportunity is **0 A.D.'s CC-BY-SA 3.0 ancient-warfare
  library** — bundle-safe with attribution under the [`asset-sources.md`](asset-sources.md)
  rules, but blocked for now by PLAN.md's CC0-only locked decision. If we ever
  relax that to allow CC-BY-SA (as the LPC note already contemplates), 0 A.D. is
  the first place to look.
- **Highest design value for Sparta specifically:** **0 A.D.** (real-time ancient
  tactics, formations, collision/pathing — our core pillar) and **Divide et Impera**
  (historical realism: supply, population, rosters, believable unit behaviour).

## Adding a game to this list

1. Find the project's **code licence** and, separately, its **art/data licence**.
2. Tag code reuse ✅ / ⛔ / 🚫 and art reuse ✅ / 🅰 / ⛔ (same meanings as
   [`asset-sources.md`](asset-sources.md)), and add a row above with links.
3. Write a sentence or two on **what we can learn from its design** and, if its art
   is reusable, note it so [`asset-sources.md`](asset-sources.md) can pick it up.
4. When in doubt on a licence, treat code as ⛔ and art as ⛔ until verified.
