extends TestCase
## InteractionResolver: which one interactable the prompt names, in what words, and that the interact key only talks
## when the prompt is an NPC's (no double handling with the controller's ladder grab or PortalInteractor).


func _npc(name: String = "Roger", id: String = "3", d: float = 1.0) -> Dictionary:
	return {"kind": "npc", "id": id, "name": name, "distance": d}


func _portal(dest: String = "Mushroom Town", shows: bool = true) -> Dictionary:
	return {"kind": "portal", "id": "000000010.out00", "name": dest, "detail": dest, "shows_prompt": shows}


func test_npc_prompt_text_uses_the_interact_key() -> void:
	var p := InteractionResolver.resolve({"nearest": _npc()})
	assert_eq(p["kind"], "npc")
	assert_eq(p["action"], "interact")
	assert_eq(p["key"], "F", "Controls binds interact to F")
	assert_eq(p["text"], "[F] Talk to Roger")
	assert_eq(p["target_id"], "3")


func test_portal_prompt_names_up_and_the_destination() -> void:
	var p := InteractionResolver.resolve({"portal": _portal()})
	assert_eq(p["kind"], "portal")
	assert_eq(p["action"], "portal_enter")
	assert_eq(p["text"], "[Up] Enter portal")
	assert_eq(p["detail"], "Mushroom Town")


func test_climb_prompt_up_or_down_at_the_top() -> void:
	assert_eq(InteractionResolver.resolve({"climbable": {"at_top": false}})["text"], "[Up] Climb")
	var top := InteractionResolver.resolve({"climbable": {"at_top": true}})
	assert_eq(top["text"], "[Down] Climb down")
	assert_eq(top["action"], "climb_down")


func test_drop_prompt_uses_the_pickup_key() -> void:
	var p := InteractionResolver.resolve({"drop": {"uid": "u1", "label": "Snail Shell"}})
	assert_eq(p["text"], "[Z] Pick up Snail Shell")
	assert_eq(p["action"], "pickup")
	assert_eq(p["target_id"], "u1")


func test_priority_climb_beats_npc_beats_portal_beats_drop() -> void:
	var all := {"climbable": {"at_top": false}, "nearest": _npc(), "portal": _portal(),
		"drop": {"uid": "u", "label": "Egg"}}
	assert_eq(InteractionResolver.resolve(all)["kind"], "climb", "the controller grabs first, on Up and on F")
	all.erase("climbable")
	assert_eq(InteractionResolver.resolve(all)["kind"], "npc", "the world says the NPC is nearer than the portal")
	all["nearest"] = {"kind": "portal", "id": "p", "distance": 0.5, "shows_prompt": true, "name": "X"}
	assert_eq(InteractionResolver.resolve(all)["kind"], "portal", "the portal is the nearest interactable")
	all.erase("nearest")
	all.erase("portal")
	assert_eq(InteractionResolver.resolve(all)["kind"], "drop")


func test_blocked_or_climbing_shows_nothing() -> void:
	var snap := {"nearest": _npc(), "drop": {"uid": "u", "label": "Egg"}}
	assert_eq(InteractionResolver.resolve(snap.merged({"blocked": true})), {}, "modal / warp / dead")
	assert_eq(InteractionResolver.resolve(snap.merged({"climbing": true})), {}, "on a ladder")
	assert_eq(InteractionResolver.resolve({}), {}, "nothing around")


func test_hidden_portal_shows_no_prompt_but_lower_candidates_still_do() -> void:
	assert_eq(InteractionResolver.resolve({"portal": _portal("X", false)}), {}, "type-1 portals stay hidden")
	var p := InteractionResolver.resolve({"portal": _portal("X", false), "drop": {"uid": "u", "label": "Egg"}})
	assert_eq(p["kind"], "drop")


func test_interact_talks_only_when_the_prompt_is_an_npc() -> void:
	assert_true(InteractionResolver.interact_talks({"nearest": _npc()}))
	assert_false(InteractionResolver.interact_talks({"nearest": _npc(), "climbable": {"at_top": false}}),
		"F grabs the ladder (controller); talking too would be double handling")
	assert_false(InteractionResolver.interact_talks({"nearest": {"kind": "portal", "id": "p", "shows_prompt": true}}),
		"F enters the portal (PortalInteractor)")
	assert_false(InteractionResolver.interact_talks({"nearest": _npc(), "blocked": true}))
	assert_false(InteractionResolver.interact_talks({"nearest": _npc(), "climbing": true}))
	assert_false(InteractionResolver.interact_talks({"drop": {"uid": "u", "label": "Egg"}}))


func test_custom_key_labels() -> void:
	var p := InteractionResolver.resolve({"nearest": _npc("Sera", "2")},
		func(a: StringName) -> String: return "<%s>" % a)
	assert_eq(p["text"], "[<interact>] Talk to Sera")
