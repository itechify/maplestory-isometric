# Hidden Street captures (monster drop lists and meso amounts)

Hidden Street's "Before Chaos" archive (<https://bc.hidden-street.net/>) is the source of two things, by the project
owner's decision on 2026-10-05:

- **Monster item-drop membership**: which items each Maple Island monster can drop. This replaces MeowDB's
  community-voted drop lists for monsters (MeowDB's lists stay in the canonical drop records as reference, with their
  votes). Drop *chances* still come from KuroDB, and only for items on both lists.
- **Meso amounts** for monsters MeowDB has no player report for (MeowDB's Snail report of 2 mesos is kept; Hidden
  Street says 1, recorded as a discrepancy).

Hidden Street's own front page says the archive is "archived directly from our GMS database ... with its Big Bang
updates and changes" (21 June 2011), so it describes **post-Big-Bang GMS v0.96**, not MapleStory Classic World. Its
monster stats differ from MeowDB's (Snail: HP 15 here, 45 on MeowDB). Nothing but drop membership and meso amounts is
taken from it, and every value that comes from it says so in its provenance.

`monsters.json` holds the 6 Maple Island monster pages, read one at a time in a normal browser after the project owner
passed the site's Cloudflare check. Hidden Street has no breakables, so the Wooden Box keeps MeowDB's drop list.

Do not re-collect these pages automatically. To update a value, read the page again in a browser and replace the
capture with the new reading and its own `read_at` (ISO 8601 with a zone), then regenerate the drop records
(`node tools/meowdb/extract_monsters.mjs`; `docs/runtime/HOWTO.md` "Capture a source page by hand").
