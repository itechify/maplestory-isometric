class_name ItemIconArt
extends RefCounted
## The art pack's rendered item icons (#69, Project art), found through ArtPack by the item's game_item_id. MisoItemIcon
## draws one over its procedural shape; without the pack, or for an item the pack has no icon for, texture_for() is
## null and the procedural icon draws as before. This is the one pack, not a pack system (PR #58 was set aside).
##
##   var tex := ItemIconArt.shared().texture_for("270", db)   # the Red Potion's icon, or null
##
## Icons load lazily, the first time an item is shown, and are cached for the session.

## The framed icon's square size in px: the pack renders 384 px, the largest slot (the shop detail) is 56 px, so this
## leaves room for a 2x UI scale.
const SIDE := 128
## Empty px around the drawn part, on its longer side (2 px of a 32 px slot, like the procedural shapes).
const MARGIN := 8

static var _shared: ItemIconArt = null

var pack: ArtPack
## game_item_id -> Texture2D, or null when the pack has none.
var _cache: Dictionary = {}


func _init(p_pack: ArtPack) -> void:
	pack = p_pack


## The icons of the installed pack (loaded once), or those use() set.
static func shared() -> ItemIconArt:
	if _shared == null:
		_shared = ItemIconArt.new(ArtPack.load_installed())
	return _shared


## Replaces the shared icons (tests: a stand-in pack). null goes back to the installed pack.
static func use(art: ItemIconArt) -> void:
	_shared = art


## The item's icon, or null (no pack, no icon, or not imported).
func texture_for(item_id: String, db: ContentDB) -> Texture2D:
	if item_id == "" or db == null or not pack.present():
		return null
	var gid := String(db.item(item_id).get("game_item_id", ""))
	if gid == "":
		return null
	if not _cache.has(gid):
		_cache[gid] = _load(pack.icon(ArtPack.ITEM, gid))
	return _cache[gid]


## Frames a rendered icon for every slot size: its drawn part (the non-transparent pixels), not its canvas, is scaled
## to fit SIDE - 2 * MARGIN on its longer side, shape kept, centred in a SIDE x SIDE square and mipmapped. So a ring and
## a spear read at the same size, nothing is cropped, and a 26 px quest reward is as smooth as the 56 px shop detail.
## null for an empty (fully transparent) image.
static func frame(src: Image) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var content := img.get_region(used)
	# Bleed colour into the transparent pixels, so resampling does not darken the edges.
	content.fix_alpha_edges()
	var k := float(SIDE - 2 * MARGIN) / float(maxi(used.size.x, used.size.y))
	var w := maxi(1, roundi(used.size.x * k))
	var h := maxi(1, roundi(used.size.y * k))
	content.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	out.blit_rect(content, Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i((SIDE - w) / 2, (SIDE - h) / 2))
	out.generate_mipmaps()
	return out


func _load(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var img := tex.get_image() if tex != null else null
	var framed := frame(img) if img != null else null
	return ImageTexture.create_from_image(framed) if framed != null else null
