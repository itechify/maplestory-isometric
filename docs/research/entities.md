# MisoStory: Maple Island entities (monsters and NPCs)

Phase-1 research. Covers the 25 canonical classic maps (GMS v8; v22 used for comparison). The machine-readable version is `docs/research/entities.json`.

> **Proprietary reference material.** Everything in `docs/research/ref_sprites/` and `docs/research/raw/` (sprites, map/mob/NPC/quest JSON) comes from Nexon game data served by maplestory.io. Use it only as reference. Do not copy it into game assets or ship it.

**Legend.** Unmarked statements are **facts** from the cited data. **[v22 data]** marks facts that come from GMS v22 data rather than v8. **[memory]** marks things recalled without a source in this pass. **[proposal]** marks design suggestions. All sizes are MapleStory pixels (px); y increases downward.

## Sources

- Map life data: `docs/research/raw/gms_v8/<id>.json` (`mobs[]`, `npcs[]`; from `https://maplestory.io/api/GMS/8/map/<id>`), plus `raw/gms_v22/` for comparison.
- Mob stats and names: `https://maplestory.io/api/GMS/8/mob/<id>`, saved to `raw/entities/mob_v8_<id>.json`. The v22 stats were compared field by field and are identical for all five mobs (`raw/entities/mob_v22_<id>.json`).
- NPC names and dialogue: `https://maplestory.io/api/GMS/8/npc/<id>`, saved to `raw/entities/npc_v8_<id>.json`.
- Quests: `https://maplestory.io/api/GMS/22/quest/<id>`, saved to `raw/entities/quests_v22/`. The parsed v8 endpoint has no quests (`/api/GMS/8/quest/1000` returns 404), **but the raw v8 WZ does have quest data**: `https://maplestory.io/api/wz/GMS/8/Data/Etc/QuestInfo.img` holds 43 entries. Its only Maple Island entry (`island=0`) is `0000100` "Bigg's Collection of Items" (*"get him 10 orange mushroom caps and 30 blue snail shells"*); the other 42 are quests elsewhere (island=1 or 2: Victoria Island, Ludibrium and Zakum subjects). Quest IDs, item names and step text below still come from v22 and are marked **[v22 data]**. A missing v8 QuestInfo entry is not evidence that a quest did not exist.
- Sprites: `https://maplestory.io/api/GMS/8/<mob|npc>/<id>/render/stand/0` (PNG, frame 0 of `stand`), saved to `ref_sprites/<mob|npc>_<id>_<slug>.png`. Mobs also have `..._move0.png` (`/render/move/0`). Only 9300018, 2004 and 2005 (absent from v8) were rendered from `/api/GMS/22/...`. Ria (9010003) exists in the v8 data, so she was rendered from v8. Other endpoints that work: `/render/<anim>` (animated GIF), `/icon` (PNG), `/name`.
- `isShop` is `false` for **every** NPC in both v8 and v22, including the obvious shopkeepers. Do not rely on it. Shop roles below come from the map the NPC stands in and from the NPC's dialogue. Shop inventories are server-side and not available from this API.

## Key findings for 3D proxy modeling

1. **The Snail needs its own base mesh.** Snail (100100) is a different design from Blue Snail (100101) and Red Snail (130101): a flat slug body with a raised single-eye head and a teal shell, in a 37x26 px frame. Blue and Red Snail are one sprite (35x34 px frame) with a cream blob body, two lidded eyes on top and a coloured shell; only 251 pixels differ, all in the shell. So the snails need **two base meshes**: one for the Snail, and one shared by Blue and Red Snail with a shell-material swap.
2. **Shroom and Orange Mushroom are different designs.** The Shroom (36x36 px) has a red-orange cap with peach spots, a tan face-stem and an angry face. The Orange Mushroom (63x58 px) has an orange cap with yellow spots and a white dumpling body with a cute face. Their frame sizes are about 1:1.7.
3. **Several NPCs share a sprite.** In the v8 renders the following groups are pixel-identical (0 differing pixels): Peter = Robin (= Todd = Sam in v22), Heena = Rain, Nina = Yoona, Sera = Maria. Tia/Ria (v22) are a recolour. [proposal] Each group can share one proxy model, with optional palette or prop changes to tell them apart.
4. **Do not use v62+ NPC renders for 2100/2101/2102.** From v62 on, Sera, Heena and Nina are maple-leaf costume variants (checked with `/api/GMS/62/npc/<id>/render/stand/0`). Only the v8 renders show the classic look.
5. **v22 differs from v8** (details in the table at the end). v22 adds the Tutorial Jr. Sentinel and the NPCs Todd and Sam to the tutorial maps, removes Blue Snails from Snail Hunting Ground I, thins out Hunting Ground II/III, moves Mai from Amherst to A Split Road, and swaps Tia for Ria.

## Monsters

| ID | Name | Lv | HP | MP | EXP | Speed | Atk (PAD) | PDD | MDD | Sprite frame (px) | Era |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 100100 | Snail | 1 | 8 | 0 | 3 | -65 | 22 | 0 | 0 | 37x26 | v8 (stats identical in v22) |
| 100101 | Blue Snail | 2 | 15 | 15 | 4 | -50 | 27 | 0 | 0 | 35x34 | v8 (stats identical in v22) |
| 120100 | Shroom | 2 | 20 | 15 | 5 | -30 | 32 | 0 | 0 | 36x36 | v8 (stats identical in v22) |
| 130101 | Red Snail | 4 | 45 | 30 | 8 | -50 | 35 | 3 | 10 | 35x34 | v8 (stats identical in v22) |
| 1210102 | Orange Mushroom | 8 | 80 | 45 | 15 | 0 | 52 | 0 | 10 | 63x58 | v8 (stats identical in v22) |
| 9300018 | Tutorial Jr. Sentinel | 1 | 8 | 15 | 1 | -60 | 20 | 0 | 0 | 40x68 | v22 only, not placed in v8 maps |

All five classic mobs have `isBodyAttack: true` (they damage you on contact) and `isUndead: false`. The Tutorial Jr. Sentinel has `noAttack: true`. Mob 120100 is named "Shroom" by `/mob/120100/name` in v8, v22, v40, v62, v83 and v95, but the text of v22 quest 1016 calls it "Spore".

### Monster visual notes (from viewing the frame-0 sprites)

- **Snail (100100)**, `ref_sprites/mob_100100_snail.png`, 37x26 px. Animation frame counts: die1 9, hit1 1, move 5, stand 1. DIFFERENT BASE DESIGN from Blue/Red Snail. Low, elongated slug body in pale lavender-white with a lavender-blue shaded underside/foot; the front end rises into a neck topped by a round white head with a single sleepy/closed eye drawn as a curved black line (reads like an eye-stalk head). A large dark teal-green spiral shell (teal base, lighter cyan-green highlights, dark spiral groove) sits on the rear and is taller than the head. Faces left in the frame. Smallest, flattest silhouette of the five mobs.
- **Blue Snail (100101)**, `ref_sprites/mob_100101_blue_snail.png`, 35x34 px. Animation frame counts: die1 3, hit1 1, move 4, stand 1. Chunky rounded cream/peach body (wide base tapering upward, like a blob or dumpling), with two large eyes on top under heavy tan/brown droopy half-closed lids (bored expression); white eyeballs, black pupils; a faint short mouth line on the front of the body. A royal/medium-blue spiral shell (darker blue spiral groove, light-blue highlight) sits on the back/right side and is roughly as tall as the body. Taller and chunkier than the 100100 Snail.
- **Shroom (120100)**, `ref_sprites/mob_120100_shroom.png`, 36x36 px. Animation frame counts: die1 4, hit1 1, move 4, stand 3. Small mushroom creature. Dome cap in red-orange with lighter peach/orange blotchy spots and a darker red-orange rim, overhanging a short tan/beige stem that is the face. Asymmetric angry face: one eye squinting under a furrowed brow, the other a large round white eye; small open mouth with red inside. Dark olive-brown lump at the base (feet/ground shadow). Squat; the cap is nearly as wide as the frame.
- **Red Snail (130101)**, `ref_sprites/mob_130101_red_snail.png`, 35x34 px. Animation frame counts: die1 3, hit1 1, move 4, stand 1. Same sprite as Blue Snail (100101) with only the shell recoloured: crimson/magenta-red shell with a darker red spiral groove (251-pixel difference vs Blue Snail; everything else identical: cream body, two lidded eyes on top).
- **Orange Mushroom (1210102)**, `ref_sprites/mob_1210102_orange_mushroom.png`, 63x58 px. Animation frame counts: die1 3, hit1 1, jump 1, move 3, stand 2. Largest island mob. Wide orange cap (orange gradient, darker orange rim) with large yellow spots, tilted slightly to one side; a grey-brown gill ring is visible under the cap. Body is a soft round white/cream dumpling shape, wider than tall, with two small black dot eyes and a small ':3'-style smiling mouth; no visible arms or legs. The cap is wider than the body.
- **Tutorial Jr. Sentinel (9300018)**, `ref_sprites/mob_9300018_tutorial_jr_sentinel.png`, 40x68 px. Animation frame counts: die1 5, hit1 1, move 4, stand 4. v22-only tutorial mob. A round beige stone ball with a black horizontal band and a gold gem in the centre. The sprite also bakes in tutorial UI above the stone (a grey 'Ctrl' keycap graphic with a yellow outline and an orange down-arrow). Not present in the v8 maps.

[proposal] For proxies, give the Snail a teal spiral shell on a low, pale lavender slug body. Give Blue and Red Snail one cream body with two lidded eyes and swap the shell material. The Orange Mushroom is the largest island mob, and the Orange Mushroom `jump` animation (1 frame) suggests a hopping movement.

## NPCs

| ID | Name | Map(s) in v8 | Role (short) | Sprite frame (px) | Same sprite as | v22 `relatedQuests` (partial; see detail) |
|---|---|---|---|---|---|---|
| 2000 | Roger | 10000 Mushroom Town | tutorial instructor (items/inventory) | 56x70 | - | - |
| 2001 | Sen | 20001 Mushroom Town Townstreet | hungry child | 40x58 | - | 1004 |
| 2002 | Peter | 30000 East Entrance to Mushroom Town | tutorial instructor at town exit | 52x70 | 2003, 2004, 2005 | - |
| 2003 | Robin | 40000 Snail Hunting Ground I | tutorial instructor (combat) | 52x70 | 2002, 2004, 2005 | - |
| 2004 | Todd | (v22 only) | tutorial (v22 only) | 52x70 | 2002, 2003, 2005 | 1018 |
| 2005 | Sam | (v22 only) | tutorial (v22 only) | 52x70 | 2002, 2003, 2004 | 1019 |
| 2100 | Sera | 0 West Entrance to Mushroom Town | resident (laundry); tutorial hints | 51x67 | 2103 | 1001 |
| 2101 | Heena | 0 West Entrance to Mushroom Town | resident; tutorial hints | 56x55 | 12101 | 1000 |
| 2102 | Nina | 20000 Mushroom Town | resident (dinner) | 65x74 | 20100 | 1003 |
| 2103 | Maria | 50000 A Split Road | wants a letter delivered | 51x67 | 2100 | 1005 |
| 10000 | Pio | 1010000 Amherst | handyman | 52x68 | - | 1008 |
| 11000 | Sid | 1010001 Amherst Weapon Store | shopkeeper, Amherst Weapon Store | 51x79 | - | - |
| 11100 | Lucy | 1010003 Amherst Department Store | shopkeeper, Amherst Department Store (potions) | 59x69 | - | - |
| 12000 | Lucas | 1010000 Amherst | chief of Amherst | 51x73 | - | 1006 |
| 12100 | Mai | 1010000 Amherst | fighter / trainer | 54x80 | - | 1016, 1017 |
| 12101 | Rain | 1010000 Amherst | tutorial hints | 56x55 | 2101 | 1009, 1010, 1011, 1012, 1013, 1014, 1015 |
| 20001 | Bari | 60000 Southperry | sailor (flavour) | 53x74 | - | - |
| 20002 | Biggs | 60000 Southperry | vain sailor | 46x67 | - | 1007 |
| 20100 | Yoona | 60000 Southperry | resident (flavour) | 65x74 | 2102 | - |
| 21000 | Pan | 60001 Southperry Armor Store | shopkeeper, Southperry Armor Store | 35x57 | - | - |
| 22000 | Shanks | 60000 Southperry | ship captain | 67x77 | - | - |
| 9000000 | Paul | 60000 Southperry | event NPC | 48x60 | - | - |
| 9010000 | Maple Administrator | 60000 Southperry | Maple Administrator | 46x69 | - | 8700 |
| 9010001 | Tia | 60000 Southperry | event/greeter | 74x113 | - | - |
| 9010003 | Ria | (v22 only) | event/greeter (v22 only) | 74x113 | - | - |

### NPC roles (detail)

- **Roger (2000)**: Tutorial instructor in Mushroom Town (10000). v8 dialogue covers the inventory, picking up, using and dropping items, potions/HP, and 'You want to go travel now? Then come talk to me'. Peter's older brother (per Peter's dialogue). No quests in the v22 API data.
- **Sen (2001)**: Hungry child in Mushroom Town Townstreet (20001). v8 dialogue: 'I'm... so ... hungry!'. [v22 data] Completes quest 1003 and starts 1004.
- **Peter (2002)**: Tutorial instructor at the East Entrance to Mushroom Town (30000). v8 dialogue: 'This is the exit to the Mushroom Town', 'If you want to move on to the next stage, talk to me', warns about monsters. Brother of Roger and Robin.
- **Robin (2003)**: Tutorial instructor in Snail Hunting Ground I (40000). v8 dialogue gives combat hints (left Ctrl to attack, Z to pick up, party up), names Mushroom Town, Southperry and Amherst, and says 'try heading up northeast'. Younger brother of Roger and Peter.
- **Todd (2004)**: v22 only: tutorial NPC at the East Entrance to Mushroom Town (30000). [v22 data] Quest 1018 'Todd's How-to-Hunt' (kill 1 Tutorial Jr. Sentinel 9300018, then talk to Peter).
- **Sam (2005)**: v22 only: tutorial NPC in Snail Hunting Ground I (40000). [v22 data] Quest 1019 'Sam's Suggestion' (hunt 10 Snails, then meet Mai).
- **Sera (2100)**: Mushroom Town resident (map 0), Heena's sister, hanging laundry. v8 dialogue: tutorial hints (press Up to climb ladders/ropes, double-click to talk). [v22 data] Completes quest 1000 and starts 1001 (item 4031003 'Sera's Mirror'); the v22 quest text calls her 'Sarah'.
- **Heena (2101)**: Mushroom Town resident (map 0). v8 dialogue: tutorial hints (jump with left Alt, move with the arrow keys) and 'Arrghh, my beautiful skin...' (the v22 quest text explains this as worry about sunlight irritating her face). [v22 data] Starts quest 1000 'Borrowing Sarah's Mirror' and completes 1001 'Bringing a Mirror to Heena'.
- **Nina (2102)**: Mushroom Town resident (20000), Sen's sister. v8 dialogue: wondering what to make for dinner. [v22 data] Starts quest 1003 'What Sen wants to eat' and completes 1004 'Returning to Nina'.
- **Maria (2103)**: Person at A Split Road (50000) who wants a letter delivered. v8 dialogue: 'I need to get this letter sent...'. [v22 data] Starts quest 1005 'Letter for Lucas' (item 4031000 Maria's Letter) and completes 1006 'Lucas' Reply'.
- **Pio (10000)**: Handyman in Amherst. v8 dialogue: 'I can handle machinery really well', is hungry, takes a break from work. [v22 data] Quest 1008 'Pio's Collecting Recycled Goods' (break scrap boxes in the village).
- **Sid (11000)**: Shopkeeper. Sourced facts: he stands in the map named 'Amherst Weapon Store' (1010001), and his v8 dialogue says 'On sale! Really CHEAP!'. The inventory is not available from the API.
- **Lucy (11100)**: Shopkeeper. Sourced facts: she stands in the map named 'Amherst Department Store' (1010003), and her v8 dialogue says 'You definitely need potions to travel' and 'cheap goods'. [proposal] She probably sells potions and consumables. The inventory is not available from the API.
- **Lucas (12000)**: Chief/elder of Amherst. v8 dialogue: distrusts strangers, worried about the town's peace, asks you to deal with monsters around town. [v22 data] Completes quest 1005 and starts 1006 'Lucas' Reply' (item 4031001 Lucas' Letter).
- **Mai (12100)**: Fighter in Amherst. v8 dialogue: 'Is there anyone that can satisfy my desire to fight...?'. [v22 data] Quests 1016 'Mai's Training' (hunt 10 each of Snail, Blue Snail and 120100; the quest text calls 120100 'Spore') and 1017 'Mai's Final Training' (10 Orange Mushrooms). In the v22 maps she stands at A Split Road (50000) instead of Amherst.
- **Rain (12101)**: Amherst tutorial helper. v8 dialogue: jump and movement hints, the same lines as Heena. [v22 data] Gives the 'Rain's Maple Quiz 1-7' quests (1009-1015), but the v8 dialogue has no quiz lines.
- **Bari (20001)**: Southperry sailor/dock worker; flavour only. v8 dialogue: 'Working hard there~', 'Salute~'.
- **Biggs (20002)**: Southperry sailor who is vain about his looks and wants to captain the big ship one day (v8 dialogue). **[v8 data: Etc/QuestInfo.img/0000100]** 'Bigg's Collection of Items': 10 orange mushroom caps and 30 blue snail shells. [v22 data] The v22 quest ID is 1007 (items 4000000 Blue Snail Shell, 4000001 Orange Mushroom Cap).
- **Yoona (20100)**: Southperry resident; flavour only. v8 dialogue: 'Whoa, what are you looking at?!?!'.
- **Pan (21000)**: Shopkeeper. Sourced facts: he stands in the map named 'Southperry Armor Store' (60001), and his v8 dialogue says 'I've got some goods here for sale!!'. The shop inventory is server-side and not in the API, and isShop is false for every NPC, so that flag cannot be used.
- **Shanks (22000)**: Ship captain at Southperry. v8 dialogue: 'I am the captain', 'I'll take you anywhere you want'. [memory] Sails players one way from Maple Island to Lith Harbor on Victoria Island for a mesos fee. Neither the destination nor the fare is in the API data.
- **Paul (9000000)**: Event NPC in Southperry. v8 dialogue: 'Where's my brother...?', 'I need to get to where the event takes place...'. [memory] Used to warp players to GM-run events.
- **Maple Administrator (9010000)**: Maple Administrator (official/GM presence) in Southperry. v8 dialogue: greetings and an anti-hacking-tools reminder. [v22 data] Gives the seasonal quest 8700 'Easter : Easter Basket' (level 8+).
- **Tia (9010001)**: Event/greeter NPC in Southperry. v8 dialogue: 'Hey all!', 'Hope you all have a wonderful day today'. Replaced by Ria (9010003) in the v22 map.
- **Ria (9010003)**: v22 only: replaces Tia in Southperry with the same dialogue. Not placed in any v8 map.

### NPC visual notes (from viewing the frame-0 sprites)

- **Roger (2000)**, `ref_sprites/npc_2000_roger.png`, 56x70 px. Long dark navy/black hair in a low ponytail draped over the right shoulder; heavy-lidded, bored eyes. Red tracksuit-style uniform: a row of white buttons/marks across the chest, a gold shoulder emblem on the right shoulder, a yellow stripe down the trouser leg, white gloves, grey-white shoes.
- **Sen (2001)**, `ref_sprites/npc_2001_sen.png`, 40x58 px. Small child: messy golden-orange hair, teal eyes, rosy cheeks, one finger raised to the mouth (hungry pose); brown/khaki tunic, orange boots.
- **Peter (2002)**, `ref_sprites/npc_2002_peter.png`, 52x70 px. Same outfit design as Roger (2000) but in royal blue: blue uniform with gold shoulder emblem, yellow trouser stripe, white gloves. Shoulder-length ash-brown/taupe hair, same heavy-lidded expression. Pixel-identical to Robin (2003) in the v8 render.
- **Robin (2003)**, `ref_sprites/npc_2003_robin.png`, 52x70 px. Pixel-identical to Peter (2002) in the v8 render: blue uniform with gold shoulder emblem, yellow trouser stripe, white gloves; shoulder-length ash-brown/taupe hair.
- **Todd (2004)**, `ref_sprites/npc_2004_todd.png`, 52x70 px. v22 only. NPC data has link=2003, so it uses Robin's sprite; the render is pixel-identical to Robin/Peter (blue uniform, ash-brown hair).
- **Sam (2005)**, `ref_sprites/npc_2005_sam.png`, 52x70 px. v22 only. NPC data has link=2003, so it uses Robin's sprite; the render is pixel-identical to Robin/Peter (blue uniform, ash-brown hair).
- **Sera (2100)**, `ref_sprites/npc_2100_sera.png`, 51x67 px. Long wavy honey-blonde/olive-gold hair; light-blue apron or bib over a brown dress, hands together at the chest. The frame is cut off around the waist, so the lower body is not visible. Pixel-identical to Maria (2103) in v8.
- **Heena (2101)**, `ref_sprites/npc_2101_heena.png`, 56x55 px. Brown spiky/feathered hair with a pink headband; large dark eye, orange blush marks; both hands clasped at the chin. White top, with a navy-blue garment visible at the bottom edge. The 56x55 frame shows only head and upper body, so the pose is not fully visible. Pixel-identical to Rain (12101).
- **Nina (2102)**, `ref_sprites/npc_2102_nina.png`, 65x74 px. Bunny costume: pink-and-white rabbit-ear headband, spiky dark-blue hair, blue eyes, pink strapless leotard, pink gloves, dark olive/brown tights, pink heels. Pixel-identical to Yoona (20100) in v8.
- **Maria (2103)**, `ref_sprites/npc_2103_maria.png`, 51x67 px. Pixel-identical to Sera (2100) in v8: long wavy honey-blonde hair, light-blue apron over a brown dress; the frame is cut off around the waist.
- **Pio (10000)**, `ref_sprites/npc_10000_pio.png`, 52x68 px. Stocky, tan-skinned handyman with a pale blond buzz cut and an orange-and-white cap worn tilted; eyes squeezed shut, lips pursed (straining). White T-shirt, light-blue denim overalls; carries a red-orange toolbox and a grey wrench.
- **Sid (11000)**, `ref_sprites/npc_11000_sid.png`, 51x79 px. Big, hulking man with olive/tan skin, a blond flat-top, black sunglasses and a frown; blue uniform (same family as Roger/Pan) with yellow shoulder and trouser stripes; hunched, fists held low; grey shoes.
- **Lucy (11100)**, `ref_sprites/npc_11100_lucy.png`, 59x69 px. Girl with big curly brown hair and large green eyes; orange-brown pinafore/jumper dress over a light-blue blouse, hands on hips, brown shoes.
- **Lucas (12000)**, `ref_sprites/npc_12000_lucas.png`, 51x73 px. Elderly village chief: swept-back sandy-blond hair and a full beard, stern face; long white/ivory robe with gold hem trim and a gold belt, a purple stole over one shoulder fastened with a round gold clasp; wooden cane in hand.
- **Mai (12100)**, `ref_sprites/npc_12100_mai.png`, 54x80 px. Young woman with brown high twin pigtails tied with red ribbons, pink/magenta eyes; red sleeveless qipao/cheongsam with a side slit, yellow sash, gold bracelet; holds a large curved broadsword (dao-like) with a gold guard, blade pointing down; red shoes.
- **Rain (12101)**, `ref_sprites/npc_12101_rain.png`, 56x55 px. Pixel-identical to Heena (2101) in v8: brown spiky hair with a pink headband, hands clasped at the chin; the frame shows only the upper body.
- **Bari (20001)**, `ref_sprites/npc_20001_bari.png`, 53x74 px. Older sailor: white sailor cap, short grey hair, tan skin, sleepy-lidded eyes; navy sailor shirt, a large coil of olive/brown rope over the right shoulder, white trousers, brown shoes.
- **Biggs (20002)**, `ref_sprites/npc_20002_biggs.png`, 46x67 px. Young sailor: white sailor cap with a blue band, grey swept hair, scowling/arrogant face; navy sailor top with white stripes and a light-blue neckerchief, white trousers, brown shoes, hands on hips.
- **Yoona (20100)**, `ref_sprites/npc_20100_yoona.png`, 65x74 px. Pixel-identical to Nina (2102) in v8: bunny-ear headband, spiky dark-blue hair, pink leotard and gloves, dark tights, pink heels.
- **Pan (21000)**, `ref_sprites/npc_21000_pan.png`, 35x57 px. Short, chubby man with short brown hair, green-tinted sunglasses and a smug face; blue uniform in the same style as Roger/Peter (silver buttons, yellow shoulder patch, yellow trouser stripe), grey shoes.
- **Shanks (22000)**, `ref_sprites/npc_22000_shanks.png`, 67x77 px. Ship captain: large royal-blue wide-brim hat with a white feather plume on one side, blonde hair, blue eyes; blue long coat with gold trim and gold/orange square cuff panels, light shirt with dark-red detail at the chest. Holds a small gold-and-brown object in one hand (not identified from the sprite).
- **Paul (9000000)**, `ref_sprites/npc_9000000_paul.png`, 48x60 px. Boy in a yellow cap worn backwards with a red brim, dark hair; white T-shirt with red shoulder straps (backpack), blue jeans with a yellow side stripe, red-and-white sneakers; holds a skateboard (pale deck, blue wheels) upright at his side.
- **Maple Administrator (9010000)**, `ref_sprites/npc_9010000_maple_administrator.png`, 46x69 px. Woman in a white newsboy cap with a large blue 'W' logo, short black hair, white skirt suit, white shoes; carries a black briefcase with a white 'W' logo.
- **Tia (9010001)**, `ref_sprites/npc_9010001_tia.png`, 74x113 px. Girl with long auburn/red-brown hair and a small silver tiara, big blue eyes; pink jacket over a light top, blue flared jeans with pink bows at the hems, pink shoes; holds three star-patterned balloons (yellow, pink, cyan) on strings, which fill the top half of the 74x113 frame.
- **Ria (9010003)**, `ref_sprites/npc_9010003_ria.png`, 74x113 px. Recolour of Tia (9010001): long dark-blue hair, purple jacket, black trousers with purple bows, balloons in cyan/pink/yellow. v22 only (replaces Tia in Southperry).

Common style (observed): every NPC is a chibi figure with a big head, about 55-80 px tall (Tia and Ria are 113 px only because of their balloons). Roger, Peter, Robin, Pan and Sid share a tracksuit/uniform design with a gold/yellow shoulder emblem and a yellow trouser stripe; Roger's is red and the others' are blue.

## Per-map placement (GMS v8)

Mob numbers are **spawn-point (life) entries** in the map data, not how many mobs are alive at once. [memory] The server limits the live population based on map size and `mobRate`. Exact spawn coordinates (x, y, foothold id) are in `entities.json` under `per_map.<id>.mob_spawns`.

| Map ID | Map | mobRate | Mob spawn points | NPCs (id name @x,y fh) |
|---|---|---|---|---|
| 0 | West Entrance to Mushroom Town | 1 | - | 2101 Heena @-48,65 fh66; 2100 Sera @833,125 fh8 |
| 10000 | Mushroom Town | 1 | - | 2000 Roger @233,65 fh7 |
| 20000 | Mushroom Town | 1 | - | 2102 Nina @-59,95 fh38 |
| 20001 | Mushroom Town Townstreet | 1 | - | 2001 Sen @24,246 fh25 |
| 30000 | East Entrance to Mushroom Town | 1 | - | 2002 Peter @1314,-925 fh128 |
| 40000 | Snail Hunting Ground I | 1 | Snail x33, Blue Snail x16 (total 49) | 2003 Robin @69,275 fh35 |
| 40001 | Snail Hunting Ground II | 1 | Snail x43, Blue Snail x24 (total 67) | - |
| 40002 | Snail Hunting Ground III | 1 | Snail x36, Blue Snail x26, Red Snail x13 (total 75) | - |
| 50000 | A Split Road | 1.5 | Blue Snail x25, Red Snail x13, Shroom x18 (total 56) | 2103 Maria @159,65 fh151 |
| 60000 | Southperry | 1 | - | 20100 Yoona @-18,287 fh10; 20002 Biggs @950,-193 fh117; 20001 Bari @1013,527 fh58; 22000 Shanks @3223,-13 fh157; 9000000 Paul @4,47 fh160; 9010001 Tia @-450,287 fh27; 9010000 Maple Administrator @-181,287 fh5 |
| 60001 | Southperry Armor Store | 1 | - | 21000 Pan @-270,140 fh11 |
| 1000000 | The Field West of Amherst | 1.3 | Snail x16, Blue Snail x20, Red Snail x26, Shroom x21, Orange Mushroom x7 (total 90) | - |
| 1000001 | In a Small Forest | 1.3 | Snail x16, Blue Snail x10, Red Snail x5, Shroom x11, Orange Mushroom x4 (total 46) | - |
| 1000002 | Dangerous Forest | 1 | Snail x15, Blue Snail x3, Red Snail x5, Orange Mushroom x12 (total 35) | - |
| 1000003 | Mushroom Garden | 1 | Snail x9, Shroom x28, Orange Mushroom x5 (total 42) | - |
| 1000004 | Snail Garden | 1 | Snail x17, Blue Snail x19, Red Snail x11 (total 47) | - |
| 1000005 | Hunting Ground Middle of the Forest I | 1 | Snail x21, Blue Snail x16, Red Snail x10, Shroom x12 (total 59) | - |
| 1000006 | Hunting Ground Middle of the Forest II | 1 | Snail x13, Blue Snail x17, Red Snail x6, Shroom x9, Orange Mushroom x6 (total 51) | - |
| 1010000 | Amherst | 1 | - | 12000 Lucas @1790,154 fh86; 12100 Mai @628,-176 fh17; 12101 Rain @103,274 fh43; 10000 Pio @547,274 fh38 |
| 1010001 | Amherst Weapon Store | 1 | - | 11000 Sid @-270,140 fh11 |
| 1010002 | Amherst Townstreet | 1 | - | - |
| 1010003 | Amherst Department Store | 1 | - | 11100 Lucy @-258,84 fh5 |
| 1010004 | Snail Field of Flowers | 1.2 | Snail x10, Blue Snail x16, Red Snail x17 (total 43) | - |
| 1020000 | The Field East of Amherst | 1 | Snail x8, Blue Snail x19, Red Snail x13, Orange Mushroom x12 (total 52) | - |
| 1020001 | Tomato Field | 1 | Snail x9, Blue Snail x8, Red Snail x4, Orange Mushroom x4 (total 25) | - |

Observations from the table:
- The Mushroom Town maps (0, 10000, 20000, 20001, 30000), the three store interiors (60001, 1010001, 1010003) and the towns (60000 Southperry, 1010000 Amherst) have no mobs in v8. Amherst Townstreet (1010002) has neither mobs nor NPCs.
- The Orange Mushroom (the strongest island mob, Lv 8) appears only in the Amherst-side fields: 1000000, 1000001, 1000002, 1000003, 1000006, 1020000 and 1020001. The Shroom appears in 50000 and in 1000000, 1000001, 1000003, 1000005 and 1000006.
- Snail Hunting Grounds I-III (40000-40002) have only snails: Snail plus Blue Snail, with Red Snail added in III.

## v22 vs v8 differences (life data only)

| Map | Mob spawn-count changes (v8 -> v22) | NPCs added in v22 | NPCs removed in v22 |
|---|---|---|---|
| 30000 East Entrance to Mushroom Town | Tutorial Jr. Sentinel (9300018): 0 -> 3 | 2004 Todd | - |
| 40000 Snail Hunting Ground I | Blue Snail (100101): 16 -> 0 | 2005 Sam | - |
| 40001 Snail Hunting Ground II | Snail (100100): 43 -> 44; Blue Snail (100101): 24 -> 11 | - | - |
| 40002 Snail Hunting Ground III | Snail (100100): 36 -> 25; Blue Snail (100101): 26 -> 15; Red Snail (130101): 13 -> 1 | - | - |
| 50000 A Split Road | - | 12100 Mai | - |
| 60000 Southperry | - | 9010003 Ria | 9010001 Tia |
| 1010000 Amherst | - | - | 12100 Mai |

[proposal] Use the v8 placement as the baseline because it is the earliest data set. The v22 tutorial additions (Todd, Sam, the Jr. Sentinel with its "Ctrl" key graphic) are tutorial UI, not world content, so treat them as optional.

## Files

- `docs/research/entities.json`: mobs, npcs and per_map (required keys), plus `_meta`, `v22_deltas` and extra fields (`mob_spawns`, `fh`, stats, sprite paths and frame sizes, era).
- `docs/research/ref_sprites/`: 36 PNGs (proprietary reference only).
- `docs/research/raw/entities/`: the raw API JSON for mobs, NPCs and v22 quests.
