class_name UnitFormation
## Formation-block geometry for a Unit, extracted from Unit.gd: the file count
## (frontage) and the centred, wider-than-deep grid of local-space slot offsets a
## regiment's soldiers arrange into. Pure and deterministic -- a function of the unit's
## soldier counts and the FORMATION_* constants only -- so it's directly unit-testable and
## replay-safe. The render's per-mark jitter and the world-space transform live elsewhere
## (Unit / the flock render); this is just the bare block layout.


## Number of files (columns) for `n` soldiers: a wider-than-deep grid
## (FORMATION_ASPECT files per rank). Pure of n.
static func _files(n: int) -> int:
	return maxi(1, int(ceil(sqrt(float(n) * Unit.FORMATION_ASPECT))))


## The regiment's stable file count (frontage): `_files` at FULL strength, so the LINE
## KEEPS ITS WIDTH as casualties thin its DEPTH (ranks). Keying the slot layout and the
## engaged-rank cutoff off this -- not the live count -- stops the whole grid from
## reflowing (every soldier jumping to a new file at once) each
## time the count crosses a sqrt threshold mid-fight. At full strength it equals
## `_files(soldiers)`, so nothing changes there.
##
## A player-set `frontage_override` (> 0) wins over the auto width, clamped to
## [1, max_soldiers] -- so the line can be widened (shallower) or narrowed (deeper)
## by hand, still keying every downstream layout off one stable file count.
static func frontage(u: Unit) -> int:
	if u.frontage_override > 0:
		return clampi(u.frontage_override, 1, maxi(1, u.max_soldiers))
	return _files(u.max_soldiers)


## File count for a drag-resize handle pulled to `half_width` world units from the
## regiment's centre along its file axis. A grid of f files spans (f-1) gaps of
## `spacing`, so its half-width is (f-1)/2 * spacing; invert that and round to the
## nearest file. `spacing` defaults to the plain FORMATION_SPACING constant, but a
## live unit's actual grid may be density-scaled (LOOSE order) -- callers with a unit
## on hand should pass `Unit.FORMATION_SPACING * u.spacing_scale` so the inverse
## mapping matches what slots() actually laid out. Clamped to [1, max_soldiers]. Pure
## -- unit-testable, and the drag preview and the committed value read the same mapping.
static func files_for_halfwidth(half_width: float, max_soldiers: int,
		spacing: float = Unit.FORMATION_SPACING) -> int:
	var f: int = int(round(2.0 * half_width / spacing)) + 1
	return clampi(f, 1, maxi(1, max_soldiers))


## "%d file(s)" with correct singular/plural, for the HUD readout and resize preview.
static func files_label(n: int) -> String:
	return "%d file" % n if n == 1 else "%d files" % n


## Local-space slot offsets for `n` soldier marks: a centred, wider-than-deep grid (front
## rank toward -Y, the rotated "forward"). Pure and deterministic -- a function of `n`,
## the unit's frontage, and its density (TIGHT/NORMAL/LOOSE scales spacing without
## changing the file/rank count) -- so it's unit-testable; the render adds stable jitter
## on top.
static func slots(u: Unit, n: int) -> PackedVector2Array:
	return block_slots(n, frontage(u), Unit.FORMATION_SPACING * u.spacing_scale)


# --- Grid operations (#367) --------------------------------------------------
# Primitives that reshape the formation grid -- transpose ranks<->columns, change the
# file count (split/merge), and change density (spacing) -- all in the unit's LOCAL frame,
# independent of its world position or facing. Pure functions of (n, files, spacing), so
# they're unit-testable and replay-safe. A maneuver layers a body relabel on top (which
# soldier takes which new slot); these just lay out the target shape.


## Rank count (rows) for `n` soldiers at the given `files` frontage.
static func ranks_for(n: int, files: int) -> int:
	if n <= 0 or files <= 0:
		return 0
	return int(ceil(float(n) / float(files)))


## The general grid layout: `n` slots in a centred, wider-than-deep block with `files`
## columns at `spacing` px, front rank toward -Y. Full ranks span the whole frontage; a
## partial rear rank closes up onto the CENTRE files of that same frontage, so its survivors
## stay centred within the frontage -- the men step up toward the middle rather than fanning
## out to the wings. This mirrors how a phalanx or
## legion closed after casualties: the file (column), led at the front and closed at the
## rear by the ouragos/file-closer, was the unit of cohesion; the outer files shortened as
## the wings closed toward the standard while the centre files stayed deepest.
##
## The partial rank stays laterally centred to the half-file: when its count and the frontage
## have opposite parity it straddles the centre line on HALF-columns (offset by half a
## spacing), so it is both symmetric about the unit centre (centroid on the axis) and still a
## regular grid -- each survivor sits half a file off the men ahead, closed toward the centre.
## `slots()` is the wrapper that feeds it the unit's frontage and the default spacing; grid-ops
## feed it reshaped (files, spacing) for the transposed / widened / opened block.
static func block_slots(n: int, files: int, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n <= 0 or files <= 0:
		return out
	var ranks: int = ranks_for(n, files)
	var y0: float = -(ranks - 1) * 0.5 * spacing
	for i in range(n):
		var file: int = i % files
		var rank: int = i / files
		var rank_count: int = mini(files, n - rank * files)
		# Close the rank onto the centre files of the full frontage: the survivors span a
		# contiguous, laterally-centred run of columns (rx0 = -(rank_count-1)/2), so a short
		# rear rank clusters on the middle files while the wings shorten -- and it stays exactly
		# symmetric about the unit centre, keeping the block's centroid on the axis.
		var rx0: float = -(rank_count - 1) * 0.5 * spacing
		out.push_back(Vector2(rx0 + file * spacing, y0 + rank * spacing))
	return out


# --- Square / orbis grid (real hollow/solid square footprint) ---------------
# The anti-cavalry square is a genuine square block, not the standard wide-line
# frontage: it uses its own file count (files ~= ranks, so the bbox aspect is ~1)
# and marks which slots sit on the outer ring, so the perimeter can face outward
# (Unit.soldier_world_facings) while the interior keeps the unit's heading.


## File count for a roughly-square grid of `n` soldiers: files ~= ranks ~= sqrt(n),
## unlike `_files` (which deliberately widens past sqrt for the line frontage). Pure.
static func square_files(n: int) -> int:
	return maxi(1, int(ceil(sqrt(float(n)))))


## Local-space slot offsets for `n` soldiers laid out as a square block (reuses
## block_slots' centred rank-major grid, just with a square file count instead of
## the wide-line frontage). Pure and deterministic like `slots()`.
static func square_slots(n: int, spacing: float) -> PackedVector2Array:
	return block_slots(n, square_files(n), spacing)


## True when slot index `i` (of `n` total soldiers laid out at `files` columns via
## block_slots) sits on the block's outer ring: the first or last rank, or the
## first/last column of its own (possibly partial) rank. Mirrors block_slots' exact
## rank/file indexing so it always agrees with what square_slots laid out. Pure.
static func square_is_perimeter(i: int, n: int, files: int) -> bool:
	if files <= 0 or i < 0 or i >= n:
		return false
	var ranks: int = ranks_for(n, files)
	var rank: int = i / files
	var rank_count: int = mini(files, n - rank * files)
	var file: int = i % files
	return rank == 0 or rank == ranks - 1 or file == 0 or file == rank_count - 1


## File count after a 90° in-place turn (quarter-turn, #371): frontage and depth swap,
## so the new file count is the old rank count. Transposing twice returns to the original
## frontage for a full grid (a partial last rank can shift it by one -- the caller reforms).
static func transposed_files(n: int, files: int) -> int:
	return maxi(1, ranks_for(n, files))


## Explicatio (#373): widen the frontage -- double the files, halving the depth -- capped
## at `n` (a single rank). The rear half of each file steps out laterally to form new files.
static func widened_files(n: int, files: int) -> int:
	return mini(maxi(1, n), files * 2)


## Duplicatio (#373): narrow the frontage -- halve the files, doubling the depth. Alternate
## files tuck in behind their neighbours. Floored at one file (a single column).
static func narrowed_files(files: int) -> int:
	return maxi(1, files / 2)
