"""The landmark alias table (#75; Project art, ADR 0002): per-map ``X<mapid>_*`` landmark -> pack model or kit art.

The pack's mapping (``environment/source_catalog_mapping.json``) covers the 149 kit catalog names only; the houses,
shops, ship and lighthouse players actually see are the 183 per-map ``X<mapid>_*`` landmarks defined in
``src/misostory/maps/m<mapid>_*.py``. This table decides each of them:

- ``ALIASES``: the landmark is built from a pack model, ``(model id, rationale)``. The model id is a pack catalog name
  (``source_asset_id`` in the mapping, e.g. ``Shop_Armor``) or, for the few pack models no catalog name maps to, the
  pack manifest's asset ``id`` (e.g. ``village_welcome_gate``); never a file name. ``kit.ensure`` then builds it like
  a swapped catalog asset (``art_pack.build``): scaled uniformly to the landmark's own procedural size, keeping its
  name, category, footprint, tags and collision tag. Per-landmark fit exceptions (the door on the map's door portal,
  parts out of the body band) are the ``pack=`` spec on the landmark's own ``@asset`` in its map module.
- ``KIT_ART``: the landmark stays the procedural kit art, ``rationale``. These are the scope of Jarvis's later
  landmark pack (#76, T13).

Every entry was decided by comparing renders, never by name: each landmark rendered on its own (procedural) next to
each of the pack's 40 building and landmark models (houses, shops, tree house, ship, lighthouse, gates, arches,
doors, stall, rowboat), then each candidate fitted in place and rendered from the map's cameras. The alias pool is the
pack's buildings (owner decision 11 on #59: pack houses and shops onto the landmarks where they fit; the ticket adds
ship, lighthouse and tree house); the pack's props, trees and foliage are the catalog swaps' (#72, #73) and are not
aliased onto landmarks here.

Pure data (no bpy): ``python src/misostory/kit/landmark_aliases.py`` prints the table as Markdown
(docs/LANDMARK_ALIASES.md).
"""

ALIASES = {
    # Amherst (1010000)
    "X1010000_DeptStore": (
        "House_Mushroom_LimeLong",
        "Same shape: a long lime cap with cream spots on a long round stem, chimney at the back. Fitted by its stem "
        "to the kit stem (7.0 m wide), so the wall stands where the kit wall did; the 2 m pack door spans in02's "
        "portal (0.6 m west of the stem axis)."),
    "X1010000_YellowHouse": (
        "House_Mushroom_Yellow",
        "Same shape: a yellow mushroom cap on a round cream stem, door on the front. Fitted by its stem like the "
        "catalog mushroom houses (#74); the kit's bamboo door becomes the pack's oak door."),
    "X1010000_GiantTree": (
        "TreeHouse_Giant",
        "Same shape: a giant tree with a door in its trunk, windows and a balcony up the trunk, a leaf canopy. "
        "Fitted by its trunk to the kit trunk (5.2 m), so X1010000_TreePods still grow out of it."),
    "X1010000_TownGate": (
        "village_welcome_gate",
        "Same shape: two posts under a lintel with a hanging welcome board, the street running through. Fitted to "
        "the kit gate's span (7 m): the posts stand where the kit pillars did, clear of route Main."),
    # Southperry (60000)
    "X60000_ArmorStore": (
        "Shop_Armor",
        "Same shape: a white gabled shop with a blue roof, chimney, the door left of centre on the long front. "
        "Fitted by its walls (6.4 m, which puts its door on the kit door's x) and set 0.3 m back and 0.2 m down so "
        "its proud door and door step keep in00 clear; the display counter and its produce, which stand across the "
        "front in the pack, are left out so in00 and its route reach the door."),
    "X60000_Lighthouse_Tall": (
        "Lighthouse_Southperry",
        "Same shape: a tapered cream tower with a red band, a railed gallery round a lantern room, a blue dome "
        "and a finial, door at the foot. The pack tower is stouter: fitted to the kit tower's base width and then "
        "1.15x by eye it stands ~80% of the kit height (fitted to the full height, its foot blocked route Main)."),
    # East Entrance (30000)
    "X30000_HouseYellowBrim": (
        "House_Mushroom_Yellow",
        "Same shape: a yellow mushroom cap over a round cream stem with a front door. Fitted by its stem; the pack "
        "cap starts higher than the kit's low brim, above any jump, so it needs no overhead hull."),
    # Mushroom Town (20000)
    "X20000_StoneArch": (
        "arch",
        "Same shape: a freestanding stone arch of two piers and a voussoir ring. Fitted by its piers to the kit "
        "pillars' span, so the opening stays as wide on the walk to in01."),
    # Hunting Ground in the Middle of the Forest II (1000006)
    "X1000006_Gate_Posts": (
        "village_welcome_gate",
        "Same shape: an open gate of two posts under a crossbar with a sign board on top. Fitted by its posts to "
        "the kit posts' span (3.4 m); it stands ~1 m taller than the kit gate."),
}


_NATURE = ("Nature dressing (bush, flower, fungus, tree, stump, vine or rock), not a building. Compared against "
           "the pack's 40 building and landmark models: none has this shape. The pack's foliage, trees and rocks are "
           "the catalog swaps' (#72, #74), not the alias pool.")
_PROP = ("Outdoor prop, sign or set dressing, not a building. Compared against the pack's 40 building and landmark "
         "models: none has this shape. The pack's props are the catalog swaps' (#73), not the alias pool.")
_INTERIOR = ("Interior furnishing or wall piece of a walk-in map, not a building. Compared against the pack's 40 "
             "building and landmark models: none has this shape (the pack's furniture is the catalog props' swap, "
             "#73).")
_BOOTH = ("Roofed shop booth inside an interior, the shopkeeper behind its counter. Compared against the pack's "
          "buildings and the market stall: none is a walk-behind booth of this size.")
_SANTORINI = ("White cubic port house with a blue dome or flat stepped roof terraces (Southperry's Santorini look). "
              "Compared against the pack's houses: all of them are gabled cottages or mushroom houses, so none has "
              "this shape.")

KIT_ART = {}


def _kit(why, *names):
    for n in names:
        KIT_ART[n] = why


_kit(_NATURE,
     "X0_HeenaBush", "X0_BerryBush",
     "X1000000_StalkMushroom_Cluster", "X1000000_Bush_Autumn", "X1000000_Bush_Mustard",
     "X1000001_GiantTrunk_White", "X1000001_BracketFungus", "X1000001_Bush_RedBerry",
     "X1000002_Vine_Leaves", "X1000002_Stump_Roots", "X1000002_Pine_Gloom", "X1000002_Tall_Gloom",
     "X1000002_Birch_Dusk", "X1000002_Bush_A", "X1000002_Bush_B", "X1000002_Bush_C", "X1000002_Birch_Rust",
     "X1000002_Birch_Ochre", "X1000002_Tree_Dead", "X1000002_Bramble", "X1000002_Toadstool_Dark",
     "X1000002_Thorn_Vine",
     "X1000003_Berry_Hedge",
     "X1000004_Carrot_Row", "X1000004_Butterfly_White",
     "X1000005_Tree_Mixed", "X1000005_Giant_Tree", "X1000005_Shelf_Fungus", "X1000005_Fern",
     "X1000006_Lily_Of_The_Valley", "X1000006_Daffodils", "X1000006_Umbrella_Leaf", "X1000006_Olive_Bush",
     "X1000006_Leaf_Litter", "X1000006_Hanging_Roots",
     "X10000_CropRow",
     "X1010004_Marigold_Bed", "X1010004_Butterfly_Orange",
     "X1020000_WhiteMushrooms",
     "X1020001_PoleVine",
     "X20000_NinaStump", "X20000_NinaStumpRoots", "X20000_Tulips",
     "X30000_PaleStalks",
     "X40000_Islet_Root", "X40001_Arch_Body",
     "X40002_Hollow_Log")

_kit(_PROP,
     "X0_LaundryBasket", "X0_Washtub",
     "X1000000_Sign_Amherst", "X1000000_Signpost_Vined",
     "X1000002_Bones",
     "X1000004_Trellis",
     "X1000005_Rainbow_Fountain", "X1000005_Log_Pile",
     "X10000_VegFence", "X10000_WateringCan", "X10000_Firewood", "X10000_PicnicTable",
     "X1010000_FaceCutout_Red", "X1010000_FaceCutout_Yellow", "X1010000_BannerPole", "X1010000_PotionSign",
     "X1010000_Birdhouse", "X1010000_SwordSign", "X1010000_MysticStone",
     "X1020000_LogPile",
     "X1020001_CratesTomatoes", "X1020001_DeckFrame", "X1020001_TrellisLeg",
     "X30000_RainbowFountain", "X30000_ClimbFlag", "X30000_LogBench",
     "X40002_Chimney_Banner",
     "X50000_Signboard_Amherst", "X50000_Signboard_Southperry", "X50000_Fork_Signpost", "X50000_Mailbox_Post",
     "X60000_PhotoBoard_Lady", "X60000_PhotoBoard_Ring", "X60000_FabricRolls", "X60000_BluePots",
     "X60000_BlueCrate", "X60000_ShieldSign", "X60000_TicketBooth", "X60000_FishStall", "X60000_CargoDerrick",
     "X60000_RopeDavit", "X60000_CafeTable", "X60000_WallWindow")

_kit(_INTERIOR,
     "X1010001_Forge", "X1010001_GlassTank", "X1010001_Anvil", "X1010001_Grindstone", "X1010001_WeaponBarrel",
     "X1010001_GearWindow", "X1010001_ArmorAlcove", "X1010001_CrossedSwords", "X1010001_WeaponSign",
     "X1010001_PipeRun", "X1010001_DisplayBench", "X1010001_QuenchTub",
     "X1010002_Bookcase",
     "X1010003_PotionRow", "X1010003_Jar", "X1010003_JarLit", "X1010003_Poster", "X1010003_BookStacks",
     "X1010003_AppleBarrel", "X1010003_ScrollRack", "X1010003_DisplayTable", "X1010003_RugSquare",
     "X20001_Cupboard", "X20001_BellLamp", "X20001_CurtainWindow", "X20001_RoundWindow", "X20001_WallShelf",
     "X20001_Stove", "X20001_DiningSet", "X20001_Nightstand", "X20001_RugBraided", "X20001_RugBlue",
     "X20001_RugGreen", "X20001_Bed", "X20001_CoatRack", "X20001_ShoeBench", "X20001_Armchair", "X20001_Firewood",
     "X20001_WashTub", "X20001_MushroomCrate", "X20001_PottedPlant",
     "X60001_ShipWheel", "X60001_ShieldWall", "X60001_Mirror", "X60001_HelmetPile", "X60001_KnightArmor",
     "X60001_ShieldBarrel", "X60001_BootsCrate", "X60001_ShieldPlaque", "X60001_LobsterPot", "X60001_NetPile",
     "X60001_NetWall", "X60001_CargoNet", "X60001_SeaWindow", "X60001_TabardMannequin", "X60001_ChainmailStand",
     "X60001_GloveRack", "X60001_RugRope")

_kit(_BOOTH, "X1010001_SidBooth", "X1010003_WelcomeBooth", "X60001_PanKiosk")

_kit(_SANTORINI, "X60000_DomeHouse", "X60000_DomeTower", "X60000_CubeHouse", "X60000_StepHouse_A",
     "X60000_StepHouse_B", "X60000_WallArch")

KIT_ART.update({
    "X1000000_Barrel_Door_Gate_Excl": (
        "An open barrel tunnel through a turf arch, its round door swung open and the map's warning plaque on the "
        "keystone; players walk through it into the portal. The pack's Barrel_Door_Mound is a closed door in a "
        "mound: not this shape."),
    "X1000000_Barrel_Door_Gate_Skull": (
        "An open barrel tunnel through a turf arch between two mounds, skull plaque on the keystone; players walk "
        "through it into the portal. The pack's Barrel_Door_Mound is a closed door in a mound: not this shape."),
    "X1000000_Barrel_Door_Gate_SkullTilt": (
        "An open barrel tunnel through a turf arch between two mounds, tilted skull plaque on the keystone; players "
        "walk through it into the portal. The pack's Barrel_Door_Mound is a closed door in a mound: not this "
        "shape."),
    "X1000000_Barrel_Door_Gate_Dark": (
        "An open, dark-staved barrel tunnel with ivy and the DANGER board; players walk through it into the portal. "
        "The pack's Barrel_Door_Mound is a closed door in a mound: not this shape."),
    "X10000_ToolShed": (
        "A small plank shed with a red lean-to roof. The pack's smallest buildings are plaster cottages and "
        "mushroom houses twice its size: not this shape."),
    "X1010000_Annex": (
        "An open-fronted thatched lean-to against the weapon store. Every pack house is a closed building: not "
        "this shape."),
    "X1010000_RedTower": (
        "A tall tower (10 m, the stem 6 m) under a red spotted cap. The pack's red mushroom house has the cap but a "
        "squat 4 m stem: fitted by its stem it stands half the tower's height, and the landmark is the tower."),
    "X1010000_Lookout": (
        "The timber frame of the plaza lookout around the walkable decks, under a red spotted roof. No pack model "
        "is a tower frame; the decks are terrain and must line up with this frame."),
    "X1010000_TreePods": (
        "Two capped pods grown into the giant tree's trunk. No pack model has them; they stay kit art on the "
        "aliased TreeHouse_Giant trunk."),
    "X1010002_CutawayHouse": (
        "A cut-away mushroom house whose open side shows the room the players walk in. Every pack house is closed: "
        "not this shape."),
    "X20000_OvenTower": (
        "A slim stone oven tower with a barrel chimney and a little door. No pack model is a stone tower of this "
        "shape (the lighthouse is three times its girth)."),
    "X20001_Door": (
        "An arched plank door in a stone surround. The pack's Door_Plank is a square-topped door: not this shape."),
    "X60001_Door_Arch": (
        "A pink double door under a blue round arch. The pack's Door_Plank is a single square-topped door: not this "
        "shape."),
    "X1010004_Vine_Arch": (
        "A slim vine hoop 1.9 m wide and 2.6 m tall over the top of each climbable vine, open to 1.75 m. The pack's "
        "leafy arch (Arch_Leafy) is a wide, low 5.1 m garden arch with a sign board: fitted to this width it stands "
        "2 m tall with a lower opening, so not this shape."),
    "X1020001_TrellisArch": (
        "The plank-topped tomato trellis over the deck walk, one piece of a set with X1020001_DeckFrame and "
        "X1020001_TrellisLeg. The pack's leafy arch is an arch of leaf lumps on timber posts: it fits the outline "
        "but not the trellis set it belongs to."),
    "X60000_Gazebo": (
        "An open gazebo: a striped tent roof on posts over a deck. No pack model is an open pavilion."),
    "X60000_Ship_Victoria": (
        "A 26 m three-masted ship whose quarterdeck, forecastle and climbable mast carry the map's walkable decks "
        "and routes. The pack's Ship_Southperry is a one-masted sloop with an aft cabin: fitted to the hull its "
        "deck and mast miss the decks and the mast route."),
})


def markdown():
    """The table as Markdown (docs/LANDMARK_ALIASES.md)."""
    lines = ["# Landmark alias table (#75)", "",
             "Generated by `python src/misostory/kit/landmark_aliases.py`; edit the table there. Each per-map "
             "`X<mapid>_*` landmark is either built from a pack model (an alias) or stays kit art; the kit-art "
             "landmarks are the scope of Jarvis's later landmark pack (#76).", "",
             f"## Aliased ({len(ALIASES)})", "", "| landmark | pack model | rationale |", "|---|---|---|"]
    lines += [f"| `{n}` | `{m}` | {why} |" for n, (m, why) in sorted(ALIASES.items())]
    lines += ["", f"## Stays kit art: #76 scope ({len(KIT_ART)})", "", "| landmark | rationale |", "|---|---|"]
    lines += [f"| `{n}` | {why} |" for n, why in sorted(KIT_ART.items())]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    import sys
    sys.stdout.buffer.write(markdown().encode("utf-8"))  # LF and UTF-8 on every platform
