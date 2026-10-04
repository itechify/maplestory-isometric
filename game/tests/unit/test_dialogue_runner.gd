extends TestCase
## DialogueRunner + DialogueContext on small hand-written graphs: branching, Back, Yes/No, menus, conditions,
## actions and failure routing. Independent of the generated NPC conversations.


func _engine(level: int = 1) -> QuestEngine:
	var c := CharacterState.new()
	c.level = level
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return QuestEngine.new(c, db(), r)


func _lit(text: String) -> Dictionary:
	return {"text": text, "source": "test"}


func _start(nodes: Dictionary, e: QuestEngine, start: String = "start", npc: String = "9") -> DialogueRunner:
	var g := DialogueGraph.from_dict({"id": "test", "npc_id": npc, "start": start, "nodes": nodes})
	assert_eq(g.validate(db()).size(), 0, "test graph valid: %s" % "\n".join(g.validate(db())))
	var r := DialogueRunner.new()
	r.start(g, DialogueContext.new(e, npc), {"npc_id": npc, "name": "Sam", "portrait": "npc_9"})
	return r


func test_say_chain_next_and_back() -> void:
	var r := _start({
		"start": {"type": "say", "line": _lit("one"), "next": "two"},
		"two": {"type": "say", "line": _lit("two"), "next": "three"},
		"three": {"type": "say", "line": _lit("three"), "next": ""},
	}, _engine())
	var v := r.view()
	assert_eq(v["text"], "one")
	assert_eq(v["buttons"], ["next"], "no Back on the first page")
	assert_eq(v["speaker_name"], "Sam")
	assert_eq(v["portrait"], "npc_9")
	v = r.press("next")
	assert_eq(v["text"], "two")
	assert_eq(v["buttons"], ["back", "next"])
	v = r.press("next")
	assert_eq(v["text"], "three")
	assert_eq(v["buttons"], ["back", "ok"], "last page ends with OK")
	v = r.press("back")
	assert_eq(v["text"], "two")
	v = r.press("back")
	assert_eq(v["text"], "one")
	assert_false(r.can_back())
	assert_eq(r.press("back")["text"], "one", "Back at the start does nothing")
	r.press("next")
	r.press("next")
	v = r.press("ok")
	assert_false(bool(v["open"]))
	assert_false(r.is_open())


func test_yes_no_branches() -> void:
	var nodes := {
		"start": {"type": "yes_no", "line": _lit("Want it?"), "yes": {"next": "y"}, "no": {"next": "n"}},
		"y": {"type": "say", "line": _lit("yes!"), "next": ""},
		"n": {"type": "say", "line": _lit("no..."), "next": ""},
	}
	var r := _start(nodes, _engine())
	assert_eq(r.view()["buttons"], ["yes", "no"])
	assert_eq(r.press("yes")["text"], "yes!")
	var r2 := _start(nodes, _engine())
	assert_eq(r2.press("no")["text"], "no...")
	assert_eq(r2.press("back")["text"], "Want it?", "Back across a plain Yes/No")


func test_menu_conditions_filter_choices() -> void:
	var e := _engine(3)
	e.character.mesos = 100
	e.character.flags["met_sam"] = true
	var nodes := {
		"start": {"type": "menu", "line": _lit("Pick"), "choices": [
			{"line": _lit("level 5+"), "condition": {"type": "level", "min": 5}, "next": "a"},
			{"line": _lit("rich"), "condition": {"type": "mesos", "min": 50}, "next": "b"},
			{"line": _lit("flag"), "condition": {"type": "flag", "flag": "met_sam"}, "next": "c"},
			{"line": _lit("not flag"), "condition": {"type": "not", "of": {"type": "flag", "flag": "met_sam"}}, "next": "a"},
			{"line": _lit("beginner"), "condition": {"type": "job", "is": "Beginner"}, "next": "a"},
			{"line": _lit("has egg"), "condition": {"type": "item_count", "item": "237", "min": 1}, "next": "a"},
			{"line": _lit("1006 open"), "condition": {"type": "quest_available", "quest": "1006"}, "next": "a"},
			{"line": _lit("1006 active"), "condition": {"type": "quest_status", "quest": "1006", "is": "in_progress"}, "next": "a"},
			{"line": _lit("any"), "condition": {"type": "any", "of": [{"type": "level", "max": 1}, {"type": "mesos", "max": 100}]}, "next": "a"},
		]},
		"a": {"type": "say", "line": _lit("a"), "next": ""},
		"b": {"type": "say", "line": _lit("b"), "next": ""},
		"c": {"type": "say", "line": _lit("c"), "next": ""},
	}
	var r := _start(nodes, e)
	var texts: Array = []
	for c: Dictionary in r.view()["choices"]:
		texts.append(c["text"])
	assert_eq(texts, ["rich", "flag", "beginner", "1006 open", "any"])
	assert_has(r.view()["buttons"], "end")
	var v := r.choose(2)
	assert_eq(v["text"], "c", "choice index is the original index")
	assert_eq(r.press("back")["type"], "menu")
	r.close()
	e.accept("1006", "9")
	var r2 := _start(nodes, e)
	texts.clear()
	for c: Dictionary in r2.view()["choices"]:
		texts.append(c["text"])
	assert_has(texts, "1006 active")
	assert_false("1006 open" in texts, "conditions are evaluated live")


func test_branch_and_auto_single_menu() -> void:
	var e := _engine(1)
	var nodes := {
		"start": {"type": "menu", "line": _lit("hub"), "auto_single": true, "empty_next": "idle", "choices": [
			{"line": _lit("x"), "condition": {"type": "level", "min": 10}, "next": "high"},
			{"line": _lit("y"), "condition": {"type": "level", "max": 9}, "next": "route"},
		]},
		"route": {"type": "branch", "cases": [{"condition": {"type": "mesos", "min": 1}, "next": "rich"}], "default": "poor"},
		"rich": {"type": "say", "line": _lit("rich"), "next": ""},
		"poor": {"type": "say", "line": _lit("poor"), "next": ""},
		"high": {"type": "say", "line": _lit("high"), "next": ""},
		"idle": {"type": "say", "line": _lit("idle"), "next": ""},
	}
	assert_eq(_start(nodes, e).view()["text"], "poor", "single visible choice taken without showing the menu")
	e.character.mesos = 5
	assert_eq(_start(nodes, e).view()["text"], "rich")
	e.character.level = 10
	assert_eq(_start(nodes, e).view()["text"], "high")


func test_actions_clear_history_and_route_failures() -> void:
	var e := _engine(1)
	var nodes := {
		"start": {"type": "say", "line": _lit("hello"), "next": "ask"},
		"ask": {"type": "yes_no", "line": _lit("Take Sam's quest?"),
			"yes": {"actions": [{"type": "accept_quest", "quest": "1006"}, {"type": "set_flag", "flag": "took", "value": 1}],
				"next": "ok", "on_fail": {"not_available": "nope", "*": "fail"}},
			"no": {"next": ""}},
		"ok": {"type": "say", "line": _lit("accepted"), "next": ""},
		"nope": {"type": "say", "line": _lit("not available"), "next": ""},
		"fail": {"type": "say", "line": _lit("failed"), "next": ""},
	}
	var r := _start(nodes, e)
	r.press("next")
	var v := r.press("yes")
	assert_eq(v["text"], "accepted")
	assert_eq(e.status("1006"), QuestLog.IN_PROGRESS)
	assert_eq(e.character.flags.get("took"), 1, "second action ran")
	assert_false(r.can_back(), "Back cannot cross an executed action")
	var types: Array = []
	for fx: Dictionary in r.ctx.effects:
		types.append(fx["type"])
	assert_eq(types, ["quest_started", "flag_set"])
	# Accepting again fails -> on_fail by reason.
	var r2 := _start(nodes, e)
	r2.press("next")
	assert_eq(r2.press("yes")["text"], "not available")


func test_action_node_and_shop_request() -> void:
	var e := _engine(1)
	var got: Array = []
	var ctx := DialogueContext.new(e, "21", func(fx: Array) -> void: got.append_array(fx))
	var g := DialogueGraph.from_dict({"id": "t", "npc_id": "21", "nodes": {
		"start": {"type": "say", "line": _lit("Welcome"), "next": "open"},
		"open": {"type": "action", "actions": [{"type": "open_shop", "shop": "maple-road-lucy"}], "next": ""},
	}})
	var r := DialogueRunner.new()
	r.start(g, ctx, {"npc_id": "21", "name": "Lucy"})
	var v := r.press("next")
	assert_false(bool(v["open"]), "chat closes after opening the shop")
	assert_eq(got, [{"type": "open_shop", "shop_id": "maple-road-lucy", "npc_id": "21"}])


func test_give_and_take_item_actions() -> void:
	var e := _engine(1)
	var ctx := DialogueContext.new(e, "9")
	assert_true(bool(ctx.run([{"type": "give_item", "item": "237", "qty": 2}])["ok"]))
	assert_eq(e.character.inventory.count("237"), 2)
	assert_true(ctx.check({"type": "item_count", "item": "237", "min": 2, "max": 2}))
	assert_false(bool(ctx.run([{"type": "take_item", "item": "237", "qty": 3}])["ok"]), "cannot take more than held")
	assert_eq(e.character.inventory.count("237"), 2, "nothing taken on failure")
	assert_true(bool(ctx.run([{"type": "take_item", "item": "237", "qty": 2}])["ok"]))
	assert_eq(e.character.inventory.count("237"), 0)


func test_objective_condition() -> void:
	var e := _engine(1)
	e.accept("1006", "9")
	var ctx := DialogueContext.new(e, "11")
	var kills_open := {"type": "objective", "quest": "1006", "kind": "monster_kills", "done": false}
	assert_true(ctx.check(kills_open))
	for k in 10:
		e.on_monster_killed("2")
	assert_false(ctx.check(kills_open))
	assert_true(ctx.check({"type": "objective", "quest": "1006", "kind": "monster_kills", "id": "2"}))
	assert_true(ctx.check({"type": "quest_can_complete", "quest": "1006"}), "at Mai")


func test_validation_reports_bad_graphs() -> void:
	var g := DialogueGraph.from_dict({"id": "bad", "nodes": {
		"start": {"type": "say", "line": _lit("x"), "next": "missing"},
		"m": {"type": "menu", "line": _lit("m"), "choices": [{"line": _lit("c"), "condition": {"type": "weather"}, "next": ""}]},
		"a": {"type": "action", "actions": [{"type": "teleport"}], "next": ""},
		"q": {"type": "say", "line": {"quest": "1006", "section": "on_accept", "line": 99}, "next": ""},
		"z": {"type": "dance"},
	}})
	var errs := "\n".join(g.validate(db()))
	assert_true("target 'missing' does not exist" in errs, errs)
	assert_true("unknown condition type 'weather'" in errs, errs)
	assert_true("unknown action type 'teleport'" in errs, errs)
	assert_true("does not resolve" in errs, errs)
	assert_true("unknown type 'dance'" in errs, errs)


func test_override_adds_and_replaces_nodes() -> void:
	var g := DialogueGraph.from_dict({"id": "o", "nodes": {
		"start": {"type": "say", "line": _lit("old"), "next": "gone"},
		"gone": {"type": "say", "line": _lit("bye"), "next": ""},
	}})
	g.apply_override({"nodes": {"start": {"type": "say", "line": _lit("new"), "next": "extra"},
		"extra": {"type": "say", "line": _lit("extra"), "next": ""}}, "remove_nodes": ["gone"]})
	assert_false(g.has_node("gone"))
	assert_eq(g.validate(db()).size(), 0)
	var r := DialogueRunner.new()
	r.start(g, DialogueContext.new(_engine(), "9"))
	assert_eq(r.view()["text"], "new")
	assert_eq(r.press("next")["text"], "extra")


func test_override_patches_single_keys_and_reports_missing_targets() -> void:
	var g := DialogueGraph.from_dict({"id": "p", "nodes": {
		"start": {"type": "say", "line": _lit("old"), "next": "", "title": "kept"},
	}})
	g.apply_override({"patch_nodes": {"start": {"line": _lit("patched")}, "ghost": {"line": _lit("x")}}})
	assert_eq(g.node("start")["title"], "kept", "other keys survive a patch")
	assert_eq(g.node("start")["line"]["text"], "patched")
	assert_false(g.has_node("ghost"), "a patch never creates a node")
	var errs := "\n".join(g.validate(db()))
	assert_true("patch for node 'ghost'" in errs, errs)


func test_counter_specs_are_validated() -> void:
	var spec := {"quest": "1012", "section": "on_accept", "branch": "accepted", "line": 1,
		"counters": [{"segment": 11, "item_id": "441"}]}
	var good := DialogueGraph.from_dict({"id": "c", "nodes": {"start": {"type": "say", "line": spec, "next": ""}}})
	assert_eq(good.validate(db()).size(), 0, "\n".join(good.validate(db())))
	var bad_spec := spec.duplicate(true)
	bad_spec["counters"] = [{"segment": 10, "item_id": "441"}, {"segment": 99, "item_id": "nope"}]
	var bad := DialogueGraph.from_dict({"id": "c", "nodes": {"start": {"type": "say", "line": bad_spec, "next": ""}}})
	var errs := "\n".join(bad.validate(db()))
	assert_true("is not a number" in errs, "segment 10 is the text ' ', not a counter: %s" % errs)
	assert_true("counter segment 99" in errs, errs)
	assert_true("counter item 'nope'" in errs, errs)


func test_line_specs_without_content_do_not_crash() -> void:
	assert_eq(DialogueText.resolve({"quest": "1006", "section": "on_accept", "line": 0}, null)["text"], "")
	assert_eq(DialogueText.resolve({"system": "inventory_full"}, null)["text"], "")
	assert_eq(DialogueText.resolve({"text": "literal", "source": "t"}, null)["text"], "literal")
	var r := DialogueRunner.new()
	var g := DialogueGraph.from_dict({"id": "n", "nodes": {"start": {"type": "say", "line": {"npc": "3", "line": 0}, "next": ""}}})
	var v := r.start(g, DialogueContext.new(QuestEngine.new(CharacterState.new(), null), "3"))
	assert_true(bool(v["open"]))
	assert_eq(v["text"], "", "no content, no text, no crash")


func test_answer_quiz_action() -> void:
	var e := _engine(5)
	e.accept("1013", "19")
	var ctx := DialogueContext.new(e, "19")
	assert_eq(ctx.run([{"type": "answer_quiz", "quest": "1013", "choice": 0}])["reason"], "wrong_answer")
	assert_false(e.can_complete("1013", "19"))
	assert_true(bool(ctx.run([{"type": "answer_quiz", "quest": "1013", "choice": 2}])["ok"]))
	assert_true(e.can_complete("1013", "19"), "graded right, not yet completed")
	assert_eq(e.status("1013"), QuestLog.IN_PROGRESS)
	assert_true("needs 'choice'" in "\n".join(DialogueContext.validate_action({"type": "answer_quiz", "quest": "1013"})))
