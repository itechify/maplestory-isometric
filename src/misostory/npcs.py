"""Classic Maple Island NPC appearances (from docs/research/entities.md visual notes).

Map modules call ``m.npc("Heena", x, y)``; the chibi proxy spec is looked up here so
each NPC looks the same wherever it appears. Colors are palette keys (materials.PALETTE).
"""

NPCS = {
    # Mushroom Town / Maple Road
    "Heena": dict(id=2101, role="Resident; tutorial hints", hair="hair_brown", top="cloth_white", bottom="roof_blue",
                  hat="headband", hat_color="flower_pink", skirt=True),
    "Sera": dict(id=2100, role="Resident hanging laundry; Heena's sister", hair="hair_blonde", top="wood",
                 bottom="wood", long_hair=True, skirt=True, extras=("apron",)),
    "Roger": dict(id=2000, role="Tutorial instructor (items)", hair="hair_black", top="roof_red", bottom="roof_red",
                  long_hair=True, extras=("gold_trim",), shoes="cloth_white"),
    "Nina": dict(id=2102, role="Resident (dinner); Sen's sister", hair="roof_blue", top="flower_pink",
                 bottom="wood_dk", hat="bunny", shoes="flower_pink"),
    "Sen": dict(id=2001, role="Hungry child", hair="hair_blonde", top="wood", bottom="wood_dk", scale=0.8,
                shoes="roof_orange"),
    "Peter": dict(id=2002, role="Tutorial instructor at the town exit", hair="hair_brown", top="roof_blue",
                  bottom="roof_blue", extras=("gold_trim",), shoes="cloth_white"),
    "Robin": dict(id=2003, role="Tutorial instructor (combat)", hair="hair_brown", top="roof_blue",
                  bottom="roof_blue", extras=("gold_trim",), shoes="cloth_white"),
    "Maria": dict(id=2103, role="Wants a letter delivered to Lucas", hair="hair_blonde", top="wood", bottom="wood",
                  long_hair=True, skirt=True, extras=("apron",)),
    # Southperry
    "Shanks": dict(id=22000, role="Ship captain (to Victoria Island)", hair="hair_blonde", top="roof_blue",
                   bottom="cloth_white", hat="feather", hat_color="roof_blue", coat="roof_blue",
                   extras=("gold_trim",)),
    "Biggs": dict(id=20002, role="Vain sailor", hair="rock", top="roof_blue", bottom="cloth_white", hat="sailor",
                  hat_color="roof_blue"),
    "Bari": dict(id=20001, role="Old sailor", hair="rock", top="roof_blue", bottom="cloth_white", hat="sailor",
                 hat_color="cloth_white", extras=("rope_coil",)),
    "Yoona": dict(id=20100, role="Resident", hair="roof_blue", top="flower_pink", bottom="wood_dk", hat="bunny",
                  shoes="flower_pink"),
    "Paul": dict(id=9000000, role="Event NPC", hair="hair_black", top="cloth_white", bottom="roof_blue",
                 hat="cap_back", hat_color="flower_yellow", extras=("skateboard",), shoes="roof_red"),
    "Maple Administrator": dict(id=9010000, role="Maple Administrator", hair="hair_black", top="cloth_white",
                                bottom="cloth_white", hat="newsboy", skirt=True, extras=("briefcase",),
                                shoes="cloth_white"),
    "Tia": dict(id=9010001, role="Event greeter", hair="wood", top="flower_pink", bottom="roof_blue", hat="tiara",
                long_hair=True, extras=("balloons",), shoes="flower_pink"),
    "Pan": dict(id=21000, role="Shopkeeper, Southperry Armor Store", hair="hair_brown", top="roof_blue",
                bottom="roof_blue", extras=("sunglasses", "gold_trim"), scale=0.85),
    # Amherst
    "Lucas": dict(id=12000, role="Chief of Amherst", hair="hair_blonde", top="cloth_white", bottom="cloth_white",
                  coat="cloth_white", extras=("beard", "stole", "cane", "gold_trim")),
    "Mai": dict(id=12100, role="Fighter / trainer", hair="hair_brown", top="cloth_red", bottom="cloth_red",
                pigtails=True, skirt=True, extras=("broadsword",), shoes="cloth_red"),
    "Rain": dict(id=12101, role="Tutorial hints", hair="hair_brown", top="cloth_white", bottom="roof_blue",
                 hat="headband", hat_color="flower_pink", skirt=True),
    "Pio": dict(id=10000, role="Handyman", hair="hair_blonde", top="cloth_white", bottom="roof_blue", hat="cap",
                hat_color="roof_orange", extras=("toolbox",)),
    "Sid": dict(id=11000, role="Shopkeeper, Amherst Weapon Store", hair="hair_blonde", top="roof_blue",
                bottom="roof_blue", extras=("sunglasses", "gold_trim"), scale=1.12),
    "Lucy": dict(id=11100, role="Shopkeeper, Amherst Department Store", hair="hair_brown", top="wood",
                 bottom="wood", long_hair=True, skirt=True),
}


def spec(name):
    d = dict(NPCS[name])
    d.pop("id", None)
    d.pop("role", None)
    return d


def info(name):
    d = NPCS[name]
    return d.get("id"), d.get("role", "")
