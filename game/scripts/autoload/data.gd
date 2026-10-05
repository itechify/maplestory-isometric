extends Node
## Autoload "Data": the game's single ContentDB instance (see scripts/core/content_db.gd).
## Systems read content through Data.db; tests build their own ContentDB so they never depend on autoload state.

var db: ContentDB = ContentDB.new()


func _enter_tree() -> void:
	db.load_all()
	for e in db.load_errors:
		push_error("[Data] " + e)
