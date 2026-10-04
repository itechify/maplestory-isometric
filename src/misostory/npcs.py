"""Classic Maple Island NPC appearances (from docs/research/entities.md visual notes) and their ids.

Map modules call ``m.npc("Heena", x, y)``; the chibi proxy spec is looked up here so
each NPC looks the same wherever it appears. Colors are palette keys (materials.PALETTE).

Ids: ``meowdb`` is the MeowDB MS Classic NPC id (a string, the gameplay key: game/data/canonical/npcs/<id>.json and
the ``npcs`` list of game/data/canonical/maps/<map>.json); ``id`` is the GMS id Iteration One researched (an int,
kept for reference; Todd and Sam only exist in v22-era data). The NPC set follows MeowDB (docs/canonical/
topology_diff.md, MAP_ARCHITECTURE.md 3.3): Todd (000000030) and Sam (000000040) are in, Mai stands on A Split Road
(000000050), and Paul, Tia and the Maple Administrator (Iteration One's v8 Southperry extras) are not on Maple Island
in MeowDB, so they have no entry here and no proxy.
"""

NPCS = {
    # Mushroom Town / Maple Road
    "Heena": dict(id=2101, meowdb="1", role="Resident; tutorial hints", hair="hair_brown", top="cloth_white",
                  bottom="roof_blue", hat="headband", hat_color="flower_pink", skirt=True),
    "Sera": dict(id=2100, meowdb="2", role="Resident hanging laundry; Heena's sister", hair="hair_blonde", top="wood",
                 bottom="wood", long_hair=True, skirt=True, extras=("apron",)),
    "Roger": dict(id=2000, meowdb="3", role="Tutorial instructor (items)", hair="hair_black", top="roof_red",
                  bottom="roof_red", long_hair=True, extras=("gold_trim",), shoes="cloth_white"),
    "Nina": dict(id=2102, meowdb="4", role="Resident (dinner); Sen's sister", hair="roof_blue", top="flower_pink",
                 bottom="wood_dk", hat="bunny", shoes="flower_pink"),
    "Sen": dict(id=2001, meowdb="5", role="Hungry child", hair="hair_blonde", top="wood", bottom="wood_dk", scale=0.8,
                shoes="roof_orange"),
    "Peter": dict(id=2002, meowdb="6", role="Tutorial instructor at the town exit", hair="hair_brown",
                  top="roof_blue", bottom="roof_blue", extras=("gold_trim",), shoes="cloth_white"),
    "Todd": dict(id=2004, meowdb="7", role="Tutorial guide at the East Entrance (combat and pickup hints)",
                 hair="hair_black", top="roof_green", bottom="wood_dk", hat="cap", hat_color="roof_green",
                 extras=("sword",), shoes="wood"),
    "Robin": dict(id=2003, meowdb="8", role="Tutorial instructor (combat)", hair="hair_brown", top="roof_blue",
                  bottom="roof_blue", extras=("gold_trim",), shoes="cloth_white"),
    "Sam": dict(id=2005, meowdb="9", role="Tutorial guide in Snail Hunting Ground I", hair="hair_blonde",
                top="roof_orange", bottom="roof_blue", hat="headband", hat_color="roof_orange", extras=("staff",),
                shoes="wood_dk"),
    "Maria": dict(id=2103, meowdb="10", role="Wants a letter delivered to Lucas", hair="hair_blonde", top="wood",
                  bottom="wood", long_hair=True, skirt=True, extras=("apron",)),
    "Mai": dict(id=12100, meowdb="11", role="Fighter / trainer", hair="hair_brown", top="cloth_red",
                bottom="cloth_red", pigtails=True, skirt=True, extras=("broadsword",), shoes="cloth_red"),
    # Southperry
    "Biggs": dict(id=20002, meowdb="12", role="Vain sailor", hair="rock", top="roof_blue", bottom="cloth_white",
                  hat="sailor", hat_color="roof_blue"),
    "Yoona": dict(id=20100, meowdb="13", role="Resident", hair="roof_blue", top="flower_pink", bottom="wood_dk",
                  hat="bunny", shoes="flower_pink"),
    "Bari": dict(id=20001, meowdb="14", role="Old sailor", hair="rock", top="roof_blue", bottom="cloth_white",
                 hat="sailor", hat_color="cloth_white", extras=("rope_coil",)),
    "Shanks": dict(id=22000, meowdb="15", role="Ship captain (to Victoria Island)", hair="hair_blonde",
                   top="roof_blue", bottom="cloth_white", hat="feather", hat_color="roof_blue", coat="roof_blue",
                   extras=("gold_trim",)),
    "Pan": dict(id=21000, meowdb="16", role="Shopkeeper, Southperry Armor Store", hair="hair_brown", top="roof_blue",
                bottom="roof_blue", extras=("sunglasses", "gold_trim"), scale=0.85),
    # Amherst
    "Lucas": dict(id=12000, meowdb="17", role="Chief of Amherst", hair="hair_blonde", top="cloth_white",
                  bottom="cloth_white", coat="cloth_white", extras=("beard", "stole", "cane", "gold_trim")),
    "Pio": dict(id=10000, meowdb="18", role="Handyman", hair="hair_blonde", top="cloth_white", bottom="roof_blue",
                hat="cap", hat_color="roof_orange", extras=("toolbox",)),
    "Rain": dict(id=12101, meowdb="19", role="Tutorial hints", hair="hair_brown", top="cloth_white",
                 bottom="roof_blue", hat="headband", hat_color="flower_pink", skirt=True),
    "Sid": dict(id=11000, meowdb="20", role="Shopkeeper, Amherst Weapon Store", hair="hair_blonde", top="roof_blue",
                bottom="roof_blue", extras=("sunglasses", "gold_trim"), scale=1.12),
    "Lucy": dict(id=11100, meowdb="21", role="Shopkeeper, Amherst Department Store", hair="hair_brown", top="wood",
                 bottom="wood", long_hair=True, skirt=True),
}

_META = ("id", "meowdb", "role")


def spec(name):
    """Chibi proxy parameters of an NPC (no ids or role)."""
    return {k: v for k, v in NPCS[name].items() if k not in _META}


def info(name):
    """(GMS id int, role) of an NPC (the Iteration One reference id)."""
    d = NPCS[name]
    return d.get("id"), d.get("role", "")


def meowdb_id(name):
    """The MeowDB MS Classic NPC id (a string, e.g. "7" for Todd): the gameplay key."""
    return str(NPCS[name]["meowdb"])
