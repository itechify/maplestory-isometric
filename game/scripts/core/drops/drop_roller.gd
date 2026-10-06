class_name DropRoller
extends RefCounted
## Turns a monster kill (or a broken Wooden Box) into the list of things that land on the ground, from the owner's
## canonical drop record (schema 3, contract C1) as DropRates reads it: membership from MeowDB's community list, each
## member's chance from the owner-approved table (category x Henesys.gg rarity, data/misostory/drop_rates.json, decision
## D3-11), the meso bag from MeowDB's player report or the level formula (data/misostory/meso_rules.json, D3-12). Pure:
## no scene tree, and every random number comes from the RNG passed in, so the same seed, data and context always give
## the same drops.
##
##   var drops := DropRoller.roll(monster_id, Data.db, Game.rng, DropRoller.context_for(Game.character))
##   # -> [{"kind": "mesos", "amount": 4}, {"kind": "item", "item_id": "349", "qty": 1}, ...]
##
##   var recs := DropRoller.ground_records(drops, Game.clock, "player", Data.db)   # expires_at, owner, scatter
##   # add the kill position along the ground axis (offset_m) as pos_local, then MapInstanceState.add_drop(rec)
##
## The caller (map instance / drop actors) places the records, drops them once expires_at passes, checks
## may_pick_up and DropRates.pickup_box_m, and hands a picked-up record to ItemService.pickup(rec).
##
## Roll rule (C1): an entry rolls only when its item resolves to a local item, its rarity and table category are
## resolved, and it has no quest gate or the gate quest is in progress (ctx.quests_in_progress, contract C2; no context =
## gated entries never roll). Unresolved entries never roll. The meso bag rolls with meso_rules.json's chance unless the
## owner never drops mesos (DropRates.meso_rule), and the amount is a uniform integer in [min, max].


## The roll context for a character (contract C2): {"quests_in_progress": its QuestLog.active_ids()}; {} without one.
static func context_for(character: CharacterState) -> Dictionary:
	if character == null or character.quests == null:
		return {}
	return {DropRates.CTX_QUESTS: character.quests.active_ids()}


## Rolls one kill of `owner_id` (monster id or breakable id). Order: the meso bag first (if any), then the entries in
## the record's order. Every entry with a resolved chance and item costs one randf(), gated or not, and a drop costs a
## randi_range only when its quantity is a range (quantity_per_drop is 1), so a quest starting or ending never shifts
## the rolls of the other entries. A meso drop costs one randi_range for its amount. Unknown owners drop nothing.
static func roll(owner_id: String, db: ContentDB, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Array:
	if not DropRates.has_table(owner_id, db):
		return []
	return roll_resolved(DropRates.effective_entries(owner_id, db), DropRates.meso_rule(owner_id, db), rng, ctx)


## Rolls already-resolved rates (DropRates.effective_entries / meso_rule), for callers that roll one owner often.
static func roll_resolved(entries: Array, meso: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	var meso_chance := float(meso.get("chance", 0.0))
	if meso_chance > 0.0:
		var r := rng.randf()
		if meso_chance >= 1.0 or r < meso_chance:
			var amount := rng.randi_range(int(meso.min), int(meso.max))
			if amount > 0:
				out.append({"kind": "mesos", "amount": amount})
	var quests := DropRates.quests_in_progress(ctx)
	for e in entries:
		var chance := float(e.chance)
		if chance <= 0.0 or String(e.get("excluded", "")) != "":
			continue
		var r := rng.randf()
		if not DropRates.may_roll(e, quests):
			continue
		if chance >= 1.0 or r < chance:
			var lo := int(e.min_quantity)
			var hi := int(e.max_quantity)
			out.append({"kind": "item", "item_id": String(e.item_id), "qty": rng.randi_range(lo, hi) if hi > lo else lo})
	return out


## Turns rolled drops into ground records for MapInstanceState.add_drop (MAP_ARCHITECTURE.md 4.7.2: {item_id | mesos,
## amount, pos_local, expires_at, owner}). Each record keeps "kind" and "item_id" (items) or "mesos" (meso bags), and
## gets:
##   "amount"                 item quantity or meso amount (what ItemService.pickup reads)
##   "expires_at"             now + DropRates.ground_lifetime_s (drops.json, unverified), on the pausable game clock
##   "owner", "free_at"       who may take it first, and from when anyone may (now + owner_exclusive_s)
##   "offset_px", "offset_m"  signed spacing from the kill point along the ground: 0, +s, -s, +2s, -2s, ... with
##                            s = scatter_spacing_px, converted with WorldScale.h. The caller adds the kill position
##                            along its ground axis to get pos_local.
static func ground_records(drops: Array, now: float, owner: String, db: ContentDB) -> Array:
	var out: Array = []
	var life := DropRates.ground_lifetime_s(db)
	var exclusive := DropRates.owner_exclusive_s(db)
	var spacing := DropRates.scatter_spacing_px(db)
	for i in drops.size():
		if not (drops[i] is Dictionary):
			continue
		var d: Dictionary = drops[i]
		var rec := {"kind": "item"}
		if ItemService.is_meso_drop(d):
			rec.kind = "mesos"
			rec["amount"] = ItemService.quantity_of(d.get("amount", d.get("mesos", 0)))
			rec["mesos"] = rec.amount
		else:
			rec["item_id"] = ItemDef.id_of(d.get("item_id", ""))
			rec["amount"] = ItemService.quantity_of(d.get("qty", d.get("amount", 1)))
		var step := (i + 1) >> 1
		var offset_px := float(step if i % 2 == 1 else -step) * spacing
		rec["offset_px"] = offset_px
		rec["offset_m"] = WorldScale.h(offset_px)
		rec["expires_at"] = now + life
		rec["owner"] = owner
		rec["free_at"] = now + exclusive
		out.append(rec)
	return out


## True if `who` may pick up a ground record at game time `now`: its owner always, anyone once "free_at" has passed
## (records without an owner are free).
static func may_pick_up(record: Dictionary, who: String, now: float) -> bool:
	var owner := ItemDef.id_of(record.get("owner", ""))
	return owner == "" or owner == who or now >= float(record.get("free_at", 0.0))


## Rolls `kills` kills under the roll context `ctx` and sums them: {"kills", "mesos" (total), "meso_drops" (kills that
## dropped mesos), "meso_amounts" {amount: bags}, "items" {item_id: total qty}, "item_drops" {item_id: kills that
## dropped it}}. For tests, the offline simulation and the debug console. A simulation only checks that the roller
## behaves as configured; it is never a source of a chance.
static func simulate(owner_id: String, kills: int, db: ContentDB, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Dictionary:
	var entries := DropRates.effective_entries(owner_id, db) if DropRates.has_table(owner_id, db) else []
	var meso := DropRates.meso_rule(owner_id, db)
	var items := {}
	var item_drops := {}
	var meso_amounts := {}
	var mesos := 0
	var meso_drops := 0
	for i in kills:
		for d in roll_resolved(entries, meso, rng, ctx):
			if d.kind == "mesos":
				mesos += int(d.amount)
				meso_drops += 1
				meso_amounts[int(d.amount)] = int(meso_amounts.get(int(d.amount), 0)) + 1
			else:
				items[d.item_id] = int(items.get(d.item_id, 0)) + int(d.qty)
				item_drops[d.item_id] = int(item_drops.get(d.item_id, 0)) + 1
	return {"kills": kills, "mesos": mesos, "meso_drops": meso_drops, "meso_amounts": meso_amounts, "items": items,
		"item_drops": item_drops}
