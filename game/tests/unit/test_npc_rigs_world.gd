extends TestCase
## The island's NPCs with the art pack (#66): IslandWorld hands its ArtPack to every WorldNpc it places, so each of the
## 21 canonical NPCs resolves to its pack model by NPC id, none to a library proxy or a placeholder. The island is
## built synchronously (collision only) with the pack injected; build_now() alone keeps the proxies (the headless
## world tools and the other world tests). Needs the Blender export (INCLUDE_WORLD=1) and the art pack; prints one SKIP
## line without either.


func test_every_island_npc_resolves_to_its_pack_model() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_island_npc_resolves_to_its_pack_model: game/assets/world not present " +
			"(run with INCLUDE_WORLD=1)")
		return
	var art := ArtPack.load_installed()
	if not art.present():
		print("SKIP test_every_island_npc_resolves_to_its_pack_model: no art pack installed (bash scripts/art_pack.sh fetch)")
		return
	var world := IslandWorld.new()
	world.name = "NpcWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	world.art = art
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(world)
	world.build_now(db())
	var ids := db().ids("npcs")
	assert_eq(world.npc_nodes.size(), ids.size(), "every canonical NPC is placed")
	for id in ids:
		var n := world.npc_nodes.get(id) as WorldNpc
		assert_true(n != null, "npc %s is placed" % id)
		if n == null:
			continue
		assert_true(n.visual != null and not n.visual.has_meta("placeholder"), "%s: no placeholder" % id)
		assert_eq(n.model_source, art.model(ArtPack.NPC, id), "%s: its pack model, not a proxy" % id)
		assert_true(n.has_clip(WorldNpc.CLIP_IDLE), "%s: idles" % id)
	world.free()


func test_build_now_without_an_injected_pack_keeps_the_proxies() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_build_now_without_an_injected_pack_keeps_the_proxies: game/assets/world not present " +
			"(run with INCLUDE_WORLD=1)")
		return
	var world := IslandWorld.new()
	world.name = "NpcWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(world)
	world.build_now(db())
	for id in world.npc_nodes:
		var n := world.npc_nodes[id] as WorldNpc
		assert_false(n.model_source.begins_with("res://"), "%s: the library proxy (%s)" % [id, n.model_source])
		assert_false(n.has_clip(WorldNpc.CLIP_IDLE), "%s: no rig" % id)
	world.free()
