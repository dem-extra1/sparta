# Dev notes: asset-sourcing catalog

A **running list** of candidate sources for Sparta's audio (and graphics), so we
don't re-research the landscape every time a cue needs a new sound. Append to it
as new sources surface — this is a living document.

For what we **actually ship**, see the per-file credits:
[`assets/sfx/CREDITS.md`](../assets/sfx/CREDITS.md) (audio) and
[`ASSETS.md`](../ASSETS.md) (graphics). This file is the *menu*; those are the
*receipt*.

## The one rule that decides everything: can we bundle it?

Anything committed under `assets/` is **redistributed to everyone who clones — or
forks — the repo**. So a source is only usable *as a bundled file* if its licence
permits **standalone redistribution of the (possibly modified) file**. Two families
clear that bar:

- **CC0 / public domain** — zero obligations.
- **CC-BY / CC-BY-SA / OGA-BY** — fine to bundle *if* you keep the attribution (and,
  for `-SA`, accept that derivatives inherit the share-alike licence).

Everything else is **reference-only**: most "free" stock libraries (Mixkit, Pixabay
post-2019, BBC RemArc) let you **use** a sound in your own build but forbid
**re-sharing the raw file**. Useful for auditioning or a personal, non-committed
build — but the files must not land in the repo.

**Being non-commercial and open-source does not loosen this — it tightens it.**
"Non-commercial" doesn't unlock those stock libraries, because the blocker is
*redistribution*, not *commerciality*. And because forks inherit the repo (the code
is MIT-licensed), anything carrying **`NC`** (non-commercial) or **`ND`**
(no-derivatives) is out too: `NC` would bar downstream/commercial forks, and `ND`
forbids the routine adapting we do (trim, resample, recolour, loop).

> Litmus test before committing a file: *"Could a stranger who forks our repo — even
> to ship a commercial game — keep this exact file?"* CC0 / CC-BY / CC-BY-SA → yes.
> NC / ND / Mixkit / Pixabay / BBC RemArc → no.

**Legend**
- ✅ **bundle-safe** — CC0 / public domain; commit freely, no obligations (we credit anyway).
- 🅰 **bundle-safe, with attribution** — CC-BY / CC-BY-SA / OGA-BY; commit, but record the credit in the receipt; `-SA` derivatives stay `-SA`.
- ⛔ **reference-only** — `NC`, `ND`, no standalone redistribution, or non-commercial-only; audition & inspiration only, never commit the files.

---

## Audio sources

| Source | Licence | Bundle? | Best for | Notes |
| --- | --- | :---: | --- | --- |
| [OpenGameArt](https://opengameart.org/) (CC0 filter) | CC0 (per-submission — **verify each**) | ✅ | everything | Our current set (see below). Search advanced → licence = CC0. OGA also hosts CC-BY/GPL, so check each submission's licence line. |
| [Kenney](https://kenney.nl/assets?q=audio) | CC0 | ✅ | UI clicks, impacts, jingles | The prior shipped set. Consistent, clean, slightly generic. |
| [Freesound](https://freesound.org/search/) | mixed (CC0 · CC-BY · CC-BY-NC) | ✅ / 🅰 | foley, ambience, combat, crowds | Huge. **CC0 and CC-BY are both bundlable** (credit the CC-BY ones); **avoid CC-BY-NC**. Always check the per-sound licence before downloading. |
| [Pixabay](https://pixabay.com/sound-effects/) | Pixabay Content Licence (**not CC0 since 2019-01-09**) | ⛔ (post-2019) | reference; battle/foley | Free for commercial **use**, no attribution, but **no standalone redistribution** — committing the raw file is the prohibited part. Only items dated **before 2019-01-09 are CC0** (and thus bundle-safe). |
| [BBC Sound Effects (RemArc)](https://sound-effects.bbcrewind.co.uk/) | RemArc Licence | ⛔ | reference; authentic battle ambience | **Personal / educational / research only — non-commercial**, and no redistribution. Excellent authentic material (e.g. the [`Battle ground`](https://sound-effects.bbcrewind.co.uk/search?q=Battle%20ground) results), but cannot be committed. Commercial licensing is separate (Pro Sound Effects). |
| [Mixkit](https://mixkit.co/free-sound-effects/battle/) | Mixkit Free Licence | ⛔ | reference; battle SFX | Free for commercial & personal **use**, no attribution, but you may **not redistribute the files standalone / unmodified** — so they can't be committed here. |

### Per-cue shortlist

`★` = what we ship today (the OpenGameArt CC0 set, PR #89). "Bundle-safe
alternatives" are CC0 or CC-BY/CC-BY-SA (🅰 = keep the credit); ⛔ items are
reference-only.

| Cue | Shipping (★) | Bundle-safe alternatives | Reference-only ideas |
| --- | --- | --- | --- |
| `hit` | ★ thwack — *Thwack Sounds*, AntumDeluge (OGA) | StarNinjas sword clash (OGA); Kenney impact pack | metal-impact foley (Pixabay/BBC ⛔) |
| `shoot` | ★ light swish — *Swishes*, artisticdude (OGA) | OGA *Bow & Arrow Shot*; Freesound CC0 bow/whoosh | bow-release foley (Mixkit/BBC ⛔) |
| `rout` | ★ heavy swish — *Swishes*, artisticdude (OGA) | a war/retreat **horn** — now also fair game under CC-BY 🅰 (e.g. Freesound brass) | BBC battle-horn / brass (⛔) |
| `death` | ★ sword clash — *20 Sword SFX*, StarNinjas (OGA) | heavier thwack; OGA grunt/body-fall packs (CC0 or CC-BY 🅰 — **verify each, avoid `-NC`**) | BBC/Pixabay body-fall (⛔) |
| `select` | ★ menu move — Joth (OGA) | Kenney *Interface Sounds*; other OGA UI packs | — |
| `order` | ★ menu confirm — Joth (OGA) | Kenney *confirmation* | — |
| `victory` | ★ VictorySmall — *8-bit sound FX*, Dizzy Crow (OGA) | cynicmusic *Victory Fanfare Short* (CC0, orchestral, larger); OGA *Hyper-Ultra-Fanfare* | orchestral fanfare stock (⛔) |
| `defeat` | ★ lose trumpet — *Game Over Trumpet*, 0new4y (OGA) | OGA *Game Over – Bad chest*; chiptune lose stings | — |

> **Cohesion notes:** `victory` (chiptune fanfare) and `defeat` (chiptune
> trumpet) are tonally paired; combat cues are organic (swords/swishes/thwack);
> UI cues are clicky. `death` borrows a sword *clash* as a decisive killing blow
> and `rout` borrows a heavier *swish* as a line-breaks-and-flees whoosh — both
> "matter of taste" picks worth revisiting if better CC0 options appear.

---

## Graphics sources

The game ships **no** art yet — units draw as placeholder tokens in `Unit.gd`.
See [`ASSETS.md`](../ASSETS.md) for the standing CC0 art shortlist and the
**do-not-use Total War mod assets** warning. Summary here for one-stop browsing:

| Source | Licence | Bundle? | Best for |
| --- | --- | :---: | --- |
| [Toen's Medieval Strategy Sprite Pack (16×16)](https://opengameart.org/content/toens-medieval-strategy-sprite-pack-v10-16x16) | CC0 | ✅ | soldiers, cavalry, siege, banners |
| [Kenney](https://kenney.nl/assets) | CC0 | ✅ | UI panels/buttons, tiles, fonts, icons |
| [OpenGameArt (CC0 filter)](https://opengameart.org/art-search-advanced?keys=&field_art_licenses_tid%5B%5D=4) | CC0 (verify each) | ✅ | terrain, tiles, props, sprites |
| [game-icons.net](https://game-icons.net/) | CC-BY 3.0 | 🅰 | ability / unit / status icons (4000+) — keep attribution |
| Liberated Pixel Cup (LPC) sets on OGA | CC-BY-SA 3.0 / GPL | 🅰 | characters, terrain — attribution **and** share-alike (derivatives stay `-SA`) |
| itch.io "free" packs | per-pack (**varies**) | 🅰 / ⛔ | read each pack's licence — many are "free to use, no redistribution" (⛔) |
| Pixabay / Freepik / stock | custom (not CC0) | ⛔ | reference / mood only |

---

## Currently bundled

- **Audio:** OpenGameArt CC0 set — see [`assets/sfx/CREDITS.md`](../assets/sfx/CREDITS.md).
  Prior set was Kenney CC0 (replaced in PR #89).
- **Graphics:** none — procedural placeholder primitives in `Unit.gd`.

> **Code vs assets:** the project's *code* is MIT-licensed; bundled *assets* keep
> their own licences (CC0 / CC-BY), recorded in the receipts above. MIT never
> implies a licence over the third-party art and audio.

## Adding a source to this list

1. Find the source's **licence** page and confirm what it allows for *standalone
   redistribution* (not just "free to use").
2. Tag it ✅ / 🅰 / ⛔ and add a row above with a link.
3. If you actually bundle a file, also record it in the matching receipt
   (`assets/sfx/CREDITS.md` or `ASSETS.md`) with source, author, and licence —
   mandatory for 🅰 (CC-BY/CC-BY-SA) attribution.
4. Prefer **CC0**; **CC-BY / CC-BY-SA** are fine with attribution. Never `NC`,
   `ND`, or no-redistribution stock. When in doubt, treat it as ⛔ and keep the
   file out of the repo.
