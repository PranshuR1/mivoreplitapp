# Pricing Model v2: hand-made tabs

`build_blueprint.py` and `build_blueprint2.py` made the two .xlsx files that were imported into the live Google Sheet ("Mivo Pricing Model v2", Mivo Google account) with File, Import, "Insert new sheet(s)". **The live Sheet is the source of truth.** It was edited by hand afterwards, so rebuilding from these scripts would bring back wording that was changed:

- Sticker source set to the Amazon 10-pack first; Tagstand moved to a second order (Shopping List, Plan, START HERE, Save Money).
- Tabs reordered; Budget, Shipping Places, Legal Checklist and Sponsors & Partners added from the second file, with the 17 `Budget!B5:B21` cells typed as links to the older tabs.
- Georgia only (2026-10-23): the Texas column and every Texas or Frisco reference were removed; the Legal Checklist, Plan, START HERE, Budget and Sources tabs now cite Georgia sources.
- Unincorporated Forsyth County (2026-10-23): licence and tax details now come from the county's own pages and application PDF; Budget B30 is $125 (two founders), so the cash to set aside is $228.92 and break-even is 13 orders.
- Plan tasks 37 to 41 and START HERE item 7 were added (county licence, TestFlight for friends, confirm the Spots update is live, shipping time at checkout, privacy page).

`Mivo-Hand-Made-Blueprint-new-tabs.xlsx` and `...-2.xlsx` are the originals as imported, kept for reference.
