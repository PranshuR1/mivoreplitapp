#!/usr/bin/env python3
"""Second batch of tabs for the Mivo Pricing Model sheet: Budget, Shipping Places, Legal Checklist,
Sponsors & Partners. Written to Mivo-Hand-Made-Blueprint-new-tabs-2.xlsx; import with
File > Import > Upload > "Insert new sheet(s)".

The Budget tab has 17 cells (B5:B21) that must link to the older tabs, but an import cannot
resolve sheet names that are not in the file. They are written as plain numbers here and the
LINKS list below is typed into the live Sheet after the import.
Research dated 2026-10-23; every row names its source.
"""
import math
import pathlib

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

OUT = pathlib.Path(__file__).parent / "Mivo-Hand-Made-Blueprint-new-tabs-2.xlsx"
DARK, SAND, CREAM, DEEP, BODY, GREEN = "3D2313", "F0E4CC", "FAF3E8", "B5621E", "6E5238", "0B8043"
S_BUD, S_SHIP, S_LEGAL, S_SPON = "Budget", "Shipping Places", "Legal Checklist", "Sponsors & Partners"
thin = Side(style="thin", color="D9CDBE")
UC, SL = "'Hand-Made Unit Cost'!", "'Shopping List'!"

# Budget!B5:B21 -> formula typed after import (value written here is today's result)
sticker, cover = 7.99 / 10, 9.60 / 500
card = 28.99 / 250 / 4 + 0.08 * 2 / 4
env = 18.99 / 100
post, pct, fixed, allow = 0.82, 0.029, 0.30, 0.03
m1 = sticker + cover + card + env
m3 = 3 * sticker + 3 * cover + card + env
a1, a3 = allow * (m1 + post), allow * (m3 + post)
fee1 = pct * 17.98 + fixed
fee3 = pct * 34.99 + fixed
p1 = 17.98 - (m1 + post + a1 + fee1)
p3 = 34.99 - (m3 + post + a3 + fee3)
LINKS = [
    (5, "Single Spot: total charged to the buyer", f"={UC}B39", 17.98, "$#,##0.00"),
    (6, "3-pack: total charged to the buyer", f"={UC}C39", 34.99, "$#,##0.00"),
    (7, "Single: stickers + cover + card + envelope", f"={UC}B45", m1, "$#,##0.00"),
    (8, "3-pack: stickers + covers + card + envelope", f"={UC}C45", m3, "$#,##0.00"),
    (9, "Postage per order (1 oz letter, stamped)", f"={UC}B46", post, "$#,##0.00"),
    (10, "Single: replacement allowance", f"={UC}B47", a1, "$#,##0.00"),
    (11, "3-pack: replacement allowance", f"={UC}C47", a3, "$#,##0.00"),
    (12, "Card fee, percent", f"={UC}B30", pct, "0.0%"),
    (13, "Card fee, fixed", f"={UC}B31", fixed, "$#,##0.00"),
    (14, "Minutes of your time per order", f"={UC}B33", 10, "0"),
    (15, "Supplies: week-1 order (Day 1 items)", f"={SL}G13", 65.57, "$#,##0.00"),
    (16, "Supplies: 20 stamps (Day 5)", f"={SL}G11", 16.40, "$#,##0.00"),
    (17, "Supplies: second sticker order (Day 8)", f"={SL}G6", 12.50, "$#,##0.00"),
    (18, "Profit on one Single Spot", f"={UC}B50", p1, "$#,##0.00"),
    (19, "Profit on one 3-pack", f"={UC}C50", p3, "$#,##0.00"),
    (20, "Single: price before shipping", f"={UC}B37", 14.99, "$#,##0.00"),
    (21, "Replacement allowance, percent", f"={UC}B32", allow, "0.0%"),
]


def font(bold=False, color="000000", size=10, italic=False, underline=None):
    return Font(name="Arial", size=size, bold=bold, color=color, italic=italic, underline=underline)


def put(ws, ref, value, bold=False, color="000000", fill=None, num=None, wrap=True, size=10, italic=False,
        link=None, align="left", valign="top"):
    c = ws[ref]
    c.value = value
    if isinstance(value, str) and value.startswith("=") and "!" in value and color == "000000":
        color = GREEN
    c.font = font(bold, "0563C1" if link else color, size, italic, "single" if link else None)
    if link:
        c.hyperlink = link
    if fill:
        c.fill = PatternFill("solid", fgColor=fill)
    if num:
        c.number_format = num
    c.alignment = Alignment(wrap_text=wrap, vertical=valign, horizontal=align)
    return c


def inp(ws, ref, value, num=None, align="right", ph=False):
    c = put(ws, ref, value, color="0000FF", fill="FFFF00" if ph else None, num=num, align=align, wrap=False)
    c.border = Border(left=thin, right=thin, top=thin, bottom=thin)
    return c


def header(ws, row, labels, start_col=1):
    for i, text in enumerate(labels):
        c = ws.cell(row=row, column=start_col + i, value=text)
        c.font = font(True, "FFFFFF")
        c.fill = PatternFill("solid", fgColor=DARK)
        c.alignment = Alignment(wrap_text=True, vertical="center")


def section(ws, row, text, last_col):
    for col in range(1, last_col + 1):
        ws.cell(row=row, column=col).fill = PatternFill("solid", fgColor=SAND)
    c = ws.cell(row=row, column=1, value=text)
    c.font = font(True, DARK, 11)
    c.alignment = Alignment(vertical="center", wrap_text=False)


def widths(ws, spec):
    for col, w in spec.items():
        ws.column_dimensions[col].width = w


def fit_rows(ws, first, last, skip=()):
    for r in range(first, last + 1):
        if r in skip:
            continue
        lines = 1
        for c in ws[r]:
            if isinstance(c.value, str) and not c.value.startswith("="):
                w = ws.column_dimensions[c.column_letter].width or 10
                lines = max(lines, sum(math.ceil(max(len(p), 1) / (w * 1.05)) for p in c.value.split("\n")))
        ws.row_dimensions[r].height = max(16, 13.5 * lines + 3)


def title(ws, text, sub):
    put(ws, "A1", text, bold=True, size=15, color=DARK, wrap=False, valign="center")
    ws.row_dimensions[1].height = 26
    put(ws, "A2", sub, italic=True, color=BODY, wrap=False)


wb = Workbook()
ws_bud = wb.active
ws_bud.title = S_BUD
ws_ship = wb.create_sheet(S_SHIP)
ws_legal = wb.create_sheet(S_LEGAL)
ws_spon = wb.create_sheet(S_SPON)
for w in (ws_bud, ws_ship, ws_legal, ws_spon):
    w.sheet_properties.tabColor = "B5621E"
    w.sheet_view.showGridLines = False

# --------------------------------------------------------------------------- Budget
ws = ws_bud
title(ws, "Budget: what you spend and what you keep",
      "Blue = input, black = formula, green = link to another tab, yellow = placeholder guess. Prices checked 2026-10-23.")
widths(ws, {"A": 52, "B": 15, "C": 15, "D": 15, "E": 15, "F": 40})
section(ws, 4, "A. Numbers pulled from your other tabs (green: change them on those tabs, not here)", 6)
for row, label, _formula, value, fmt in LINKS:
    put(ws, f"A{row}", label)
    c = put(ws, f"B{row}", value, num=fmt, align="right", color=GREEN)

section(ws, 23, "B. One-time set-up and legal costs (set Include? to Yes or No)", 6)
header(ws, 24, ["Item", "Cost", "Include?", "Notes"])
setup = [
    ("State sales tax permit", 0, "Yes", False, "Free in Georgia (guides) and Texas (Comptroller page)"),
    ("EIN from the IRS", 0, "No", False, "Free at IRS.gov; a sole proprietor can use their SSN instead. Skip paid EIN services"),
    ("Trade name registration (only if you sell under a business name)", 171, "No", False, "Forsyth County clerk, per a third-party site: notarized, newspaper notice. Confirm on (770) 781-2120"),
    ("Georgia LLC, if you and your co-founder want liability protection", 110, "No", False, "State guide: $100 filing + $10 service charge by mail"),
    ("LLC annual registration, per year", 50, "No", False, "Most sources say $50 online; others say $30 or $60. Confirm on sos.ga.gov"),
    ("County business license (Occupational Tax Certificate)", 0, "Yes", True, "Fee not found. Call Forsyth County (770) 781-2115. Placeholder"),
]
for i, (item, cost, inc, ph, note) in enumerate(setup):
    r = 25 + i
    put(ws, f"A{r}", item)
    inp(ws, f"B{r}", cost, "$#,##0.00", ph=ph)
    inp(ws, f"C{r}", inc, align="center")
    put(ws, f"D{r}", note, color=BODY)
    ws.merge_cells(f"D{r}:F{r}")
put(ws, "A31", "Total set-up costs included", bold=True)
put(ws, "B31", '=SUMIF(C25:C30,"Yes",B25:B30)', num="$#,##0.00", align="right", bold=True)
dv = DataValidation(type="list", formula1='"Yes,No"', allow_blank=False)
ws.add_data_validation(dv)
dv.add("C25:C30")

section(ws, 33, "C. Cash to set aside before your first sale", 6)
put(ws, "A34", "Supplies (week 1 + stamps + second sticker order)")
put(ws, "B34", "=B15+B16+B17", num="$#,##0.00", align="right")
put(ws, "A35", "Set-up and legal costs")
put(ws, "B35", "=B31", num="$#,##0.00", align="right")
put(ws, "A36", "Cushion for mistakes, percent of supplies")
inp(ws, "B36", 0.10, "0%", ph=True)
put(ws, "A37", "Cushion")
put(ws, "B37", "=B34*B36", num="$#,##0.00", align="right")
put(ws, "A38", "Total to set aside", bold=True)
put(ws, "B38", "=B34+B35+B37", num="$#,##0.00", align="right", bold=True)
for col in "AB":
    ws[f"{col}38"].fill = PatternFill("solid", fgColor=CREAM)

section(ws, 40, "D. A month of sales (change the blue cells)", 6)
header(ws, 41, ["", "Slow", "Steady", "Good", "Busy"])
put(ws, "A42", "Orders in the month")
for col, v in zip("BCDE", (5, 10, 25, 50)):
    inp(ws, f"{col}42", v, "0")
put(ws, "A43", "Share that are 3-packs")
for col in "BCDE":
    inp(ws, f"{col}43", 0.20, "0%", ph=True)
put(ws, "A44", "Sales tax rate (Cumming GA 7%, Frisco TX 8.25%: set yours)")
inp(ws, "B44", 0.07, "0.00%", ph=True)
for col in "CDE":
    put(ws, f"{col}44", "=$B$44", num="0.00%", align="right")
rows = [
    (45, "Singles", "=ROUND({c}42*(1-{c}43),0)", "0"),
    (46, "3-packs", "={c}42-{c}45", "0"),
    (47, "Collected from buyers, before tax", "={c}45*$B$5+{c}46*$B$6", "$#,##0.00"),
    (48, "Sales tax collected (belongs to the state)", "={c}44*{c}47", "$#,##0.00"),
    (49, "Your costs: materials, postage, replacements", "={c}45*($B$7+$B$9+$B$10)+{c}46*($B$8+$B$9+$B$11)", "$#,##0.00"),
    (50, "Card fees (also charged on the tax)", "=$B$12*({c}47+{c}48)+$B$13*{c}42", "$#,##0.00"),
    (51, "Profit before your time", "={c}47-{c}49-{c}50", "$#,##0.00"),
    (52, "Hours of your time", "={c}42*$B$14/60", "0.0"),
    (53, "Profit per hour", "=IF({c}52>0,{c}51/{c}52,0)", "$#,##0.00"),
    (54, "Set aside for the state", "={c}48", "$#,##0.00"),
]
for r, label, f, fmt in rows:
    put(ws, f"A{r}", label, bold=(r == 51))
    for col in "BCDE":
        put(ws, f"{col}{r}", f.format(c=col), num=fmt, align="right", bold=(r == 51))
for col in "ABCDE":
    ws[f"{col}51"].fill = PatternFill("solid", fgColor=CREAM)
put(ws, "F51", "Fees on the tax make this a few cents lower than Hand-Made Unit Cost", color=BODY)

section(ws, 56, "E. When you break even", 6)
put(ws, "A57", "Average profit per order at the Slow column's mix")
put(ws, "B57", "=(1-B43)*B18+B43*B19", num="$#,##0.00", align="right")
put(ws, "A58", "Orders to earn back what you set aside", bold=True)
put(ws, "B58", "=ROUNDUP(B38/B57,0)", num="0", align="right", bold=True)

section(ws, 60, "F. Where each dollar of a Single Spot order goes", 6)
header(ws, 61, ["Line", "Dollars", "Share of what the buyer paid"])
lines = [
    (62, "Stickers, cover, card, envelope", "=B7"),
    (63, "Postage", "=B9"),
    (64, "Replacement allowance", "=B10"),
    (65, "Card fee", "=B12*B5+B13"),
    (66, "You keep", "=B5-SUM(B62:B65)"),
]
for r, label, f in lines:
    put(ws, f"A{r}", label, bold=(r == 66))
    put(ws, f"B{r}", f, num="$#,##0.00", align="right", bold=(r == 66))
    put(ws, f"C{r}", f"=B{r}/$B$5", num="0.0%", align="right")
put(ws, "A67", "Self-check: this should equal Hand-Made Unit Cost profit (shows 0.00 when it does)", italic=True, color=BODY)
put(ws, "B67", "=ROUND(B66-B18,2)", num="0.00", align="right")
fit_rows(ws, 5, 67, skip=(4, 23, 33, 40, 56, 60))
ws.freeze_panes = "A4"

# --------------------------------------------------------------------------- Shipping Places
ws = ws_ship
title(ws, "Shipping places: what it costs you to send one Single Spot",
      "Every row ships the pack as a 1 oz letter unless it says otherwise. Postage: USPS Notice 123, effective 2026-10-04 (read on pe.usps.com).")
widths(ws, {"A": 34, "B": 30, "C": 11, "D": 11, "E": 12, "F": 12, "G": 13, "H": 11, "I": 12, "J": 34, "K": 34, "L": 36})
put(ws, "A4", "Single Spot price before shipping", bold=True, wrap=False)
put(ws, "B4", f"={S_BUD}!B20", num="$#,##0.00", align="right")
put(ws, "A5", "Shipping you charge, United States", bold=True, wrap=False)
inp(ws, "B5", 2.99, "$#,##0.00")
put(ws, "A6", "Shipping you charge, abroad", bold=True, wrap=False)
inp(ws, "B6", 4.99, "$#,##0.00", ph=True)
put(ws, "A7", "Extra card fee on international cards", bold=True, wrap=False)
inp(ws, "B7", 0.015, "0.0%")
put(ws, "C7", "Stripe pricing page: + 1.5% for international cards (read)", italic=True, color=BODY, wrap=False)
header(ws, 9, ["Destination", "How it ships", "Postage, 1 oz", "Postage, 2 oz", "Shipping you charge", "Collected",
               "Materials + replacements", "Card fee", "Profit on a single", "Paperwork", "The buyer may also pay", "Source and confidence"])
places = [
    ("United States: 50 states and DC", "First-Class Mail letter, stamped", 0.82, 1.11, "=$B$5", 0,
     "None", "Sales tax at your state's rate, added on top (see Legal Checklist)", "USPS Notice 123: $0.82 at 1 oz, $0.78 metered. Verified"),
    ("Canada", "First-Class Mail International letter", 1.75, 2.35, "=$B$6", 1,
     "Customs declaration PS Form 2976 for merchandise (Stamps.com help page; check the current USPS International Mail Manual)",
     "Import duties or taxes set by Canada: not researched", "USPS Notice 123 (price group 1). Price verified; paperwork and duties not"),
    ("Mexico", "First-Class Mail International letter", 1.75, 2.60, "=$B$6", 1,
     "Same customs declaration", "Import duties or taxes: not researched", "USPS Notice 123 (price group 2). Price verified; rest not"),
    ("Every other country (price groups 3 to 9: UK, EU, Australia, India and more)", "First-Class Mail International letter", 1.75, 3.50, "=$B$6", 1,
     "Same customs declaration", "VAT, duty and import fees: not researched. The UK and EU commonly charge VAT on small parcels", "USPS Notice 123 (price groups 3-9). Price verified; rest not"),
    ("United States, tracked (a paid upgrade)", "USPS Ground Advantage up to 4 oz, retail, zone 1", 8.40, 8.40, 9.99, 0,
     "None", "Sales tax", "USPS Notice 123: retail $8.40 to $10.20, commercial $7.33 to $8.95 by zone. Verified. The $9.99 charge is my suggestion"),
    ("United States, if a pack fails the letter test", "Large envelope (flat)", 1.69, 1.98, "=$B$5", 0,
     "None", "Sales tax", "USPS Notice 123: $1.69 at 1 oz. The 2 oz price is from your Shipping tab"),
]
for i, (dest, how, p1_, p2_, charge, intl, paper, buyer, src) in enumerate(places):
    r = 10 + i
    put(ws, f"A{r}", dest, bold=True)
    put(ws, f"B{r}", how)
    inp(ws, f"C{r}", p1_, "$#,##0.00")
    inp(ws, f"D{r}", p2_, "$#,##0.00")
    if isinstance(charge, str):
        put(ws, f"E{r}", charge, num="$#,##0.00", align="right")
    else:
        inp(ws, f"E{r}", charge, "$#,##0.00", ph=True)
    put(ws, f"F{r}", f"=$B$4+E{r}", num="$#,##0.00", align="right")
    put(ws, f"G{r}", f"={S_BUD}!$B$7+{S_BUD}!$B$21*({S_BUD}!$B$7+C{r})", num="$#,##0.00", align="right")
    extra = "+$B$7" if intl else ""
    put(ws, f"H{r}", f"=({S_BUD}!$B$12{extra})*F{r}+{S_BUD}!$B$13", num="$#,##0.00", align="right")
    put(ws, f"I{r}", f"=F{r}-C{r}-G{r}-H{r}", num="$#,##0.00", align="right", bold=True)
    put(ws, f"J{r}", paper, color=BODY)
    put(ws, f"K{r}", buyer, color=BODY)
    put(ws, f"L{r}", src, color=BODY)
put(ws, "A17", "International parcel (tracked), about $19 to $25 each, from your Shipping tab (not re-checked): too dear for a $14.99 Spot.", italic=True, color=BODY, wrap=False)

put(ws, "A19", "What I would do", bold=True, color=DARK, size=11, wrap=False)
advice = [
    "Launch United States only. A letter costs the same $0.82 to every state, so there is nothing to work out by distance.",
    "Add Canada after about 20 US orders go smoothly. The postage is $1.75, but check Canada's import rules and add the customs declaration first.",
    "Treat every other country as later: the postage is also $1.75, but VAT and duty rules differ by country and I did not research them.",
    "Letters have no tracking and no insurance. Your Shipping tab allows for 1 to 3% lost mail; offer the tracked upgrade for buyers who want it.",
    "Not researched: delivery times, APO/FPO and US territories, and which countries refuse mail with electronics. Ask the post office before promising.",
]
for i, t in enumerate(advice):
    put(ws, f"A{20 + i}", f"{i + 1}. {t}", wrap=False)
fit_rows(ws, 10, 15)
ws.freeze_panes = "B10"

# --------------------------------------------------------------------------- Legal Checklist
ws = ws_legal
title(ws, "Legal and tax checklist",
      "Not legal or tax advice. 'Read' = I opened the official page; 'Guide' = a third-party guide or search snippet: confirm before you rely on it.")
widths(ws, {"A": 4, "B": 22, "C": 30, "D": 52, "E": 40, "F": 11, "G": 13, "H": 44})
header(ws, 4, ["#", "Topic", "What to do", "Georgia (my best guess for you)", "Texas (my first guess; keep if you live there)", "Cost", "Status", "Source and confidence"])
GA_DOR = "https://dor.georgia.gov/what-subject-sales-and-use-tax"
legal = [
    ("Where you live", "Tell me your state. Use only that column.",
     "Your Mivo agreements show a Georgia phone number and a Georgia sponsor, so I now treat Georgia as likely.",
     "I first guessed Texas from an Amazon page that said 'Delivering to Frisco'. That is not proof of where you live.", "$0", None,
     "Low until you confirm"),
    ("Who owns the business", "Decide how you and your co-founder sell.",
     "Two people selling for profit are generally a general partnership by default, each personally liable. A Georgia LLC costs $100 + $10 mail service charge; annual registration is about $50 online (sources say $30 to $60). Write a founders' agreement either way.",
     "The same default rule applies in Texas (Texas State Bar answer). Texas LLC fee not researched.", "$0 to $110", "https://sos.ga.gov/how-to-guide/how-guide-register-domestic-entity",
     "Guide for the default rule; the Georgia filing fee is from the state's own how-to guide"),
    ("Sales tax permit", "Register before your first sale.",
     "Georgia Tax Center. No fee and about 1 to 5 business days, per guides. A sole proprietor with no EIN uses their SSN.",
     "Texas Comptroller eSystems. No fee. Allow 2 to 3 weeks. Needs your SSN. Do not put a DBA in the legal-name field.", "$0", "https://comptroller.texas.gov/taxes/permit",
     "Texas: read on the Comptroller page. Georgia: guides"),
    ("Sales tax rate", "Charge the right rate.",
     "Cumming: 7% (4% state + 3% Forsyth County). ZIP 30028 sits in a district at 8%. Confirm for your address.",
     "Frisco: 8.25% (state 6.25% + city 2%).", "n/a", "https://www.salestaxhandbook.com/georgia/rates/cumming",
     "Guide (two sources agree)"),
    ("Tax on your shipping charge", "Charge tax on the item and on shipping.",
     "Taxable: Georgia DOR says a separate delivery charge on a taxable item is taxable.",
     "Taxable: the Comptroller FAQ says delivery charges on taxable items are taxable.", "n/a", GA_DOR,
     "Georgia: read on dor.georgia.gov. Texas: read in the Comptroller FAQ"),
    ("Filing returns", "File on time, even with no sales.",
     "New accounts start on monthly returns, due the 20th (guides). Zero returns are required. Ask to move to quarterly after 6 months if your tax is small.",
     "Returns are required even with no sales. Your schedule: not researched.", "$0", None,
     "Guide. Confirm the schedule in your Georgia Tax Center account"),
    ("Selling to other states", "Check before you ship outside your state.",
     "Each state sets its own threshold for when you must register there (Georgia's is $100,000 or 200 sales into Georgia). At hand-made volume this is unlikely, but track sales by state.",
     "Texas's threshold for out-of-state sellers is $500,000.", "n/a", None,
     "Thresholds are for sellers outside the state; your own rules by state: not researched"),
    ("County or city business license", "Check before selling from home.",
     "Forsyth County (unincorporated): Occupational Tax Certificate, renewed yearly. Home businesses file the residential application with a location verification letter, notarized affidavits and, if you use one, your trade name registration. Fee not found. Call (770) 781-2115 or email businesslicense@forsythco.com. If you live inside Cumming city limits the city may differ: not researched.",
     "Not researched. Check your city.", "Unknown", "https://www.forsythco.com/DepartmentsOffices/BusinessLicenses/Applications",
     "Guide from the county's own pages in search results; fee not found"),
    ("Trade name", "Only if you sell under a name other than your own.",
     "Forsyth County Clerk of Superior Court: $171 per a third-party site, notarized, notice in the county legal paper for two weeks. Call (770) 781-2120.",
     "Not researched.", "$171?", None, "Guide only"),
    ("EIN", "Optional.",
     "Free at IRS.gov. A sole proprietor with no employees can use their SSN. Do not pay a service for it.",
     "Same.", "$0", "https://www.irs.gov/instructions/iss4", "IRS Form SS-4 instructions, via search"),
    ("FTC Mail Order Rule", "Applies to online orders.",
     "Say when you ship. Ship within that time, or within 30 days if you gave none. If you can't, send a delay notice with the right to cancel and refund without being asked.",
     "Same federal rule.", "$0", "https://www.ftc.gov/business-guidance/resources/business-guide-ftcs-mail-internet-or-telephone-order-merchandise-rule",
     "FTC business guidance, via search"),
    ("Refund and replacement policy", "Write it and put it on the checkout page.",
     "Suggested: free replacement if a Spot does not work. It matches the 3% allowance in Hand-Made Unit Cost.", "Same.", "$0", None, "My suggestion"),
    ("Privacy policy and terms", "Update usemivo.app/privacy and /terms before taking orders.",
     "I read the website's privacy page on 2026-10-23: it only covers sign-in. Add what you collect for orders (name, shipping address, payment through Stripe), who sees it, and the refund terms.",
     "Same.", "$0", None, "Read in usemivo-website/app/privacy/page.tsx"),
    ("App is ready for customers", "Do not sell until the App Store app supports Spots.",
     "The App Store version is 3.0, released 2026-08-26, and its notes talk about Mac. The Spots work was committed 19 to 22 October, so the live app does not include physical Spots yet (your website code says the same). usemivo.app/s/ and the universal-link file are live. Confirm the Supabase Spots migrations are applied to production.",
     "Same.", "$0", "https://apps.apple.com/us/app/mivo-scrolling/id6762094544",
     "Checked with the iTunes lookup API and your repo on 2026-10-23"),
    ("Product rules (FCC)", "Keep your supplier's spec sheet.",
     "Plain passive NFC stickers with no battery are commonly treated as exempt (NXP forum answers). Keep the spec as your record.",
     "Same.", "$0", "https://community.nxp.com/message/859598", "Forum opinion, not legal advice"),
    ("Customs paperwork abroad", "Only when you ship abroad.",
     "A letter with merchandise needs a customs declaration (PS Form 2976), per a Stamps.com help page. Check the current USPS International Mail Manual.",
     "Same.", "$0", "https://help.stamps.com/hc/articles/21039971825691", "Guide"),
    ("Income tax", "Keep every receipt, log every order, set aside part of profit.",
     "Not researched in detail. Talk to a tax pro once you have real sales.", "Same.", "$0", None, "Not researched"),
    ("Free help", "Ask before paying anyone.",
     "Georgia SBDC (UGA) offers free one-on-one consulting: georgiasbdc.org/consulting. SCORE offers free mentoring: score.org/ga/atlanta/contact-us.",
     "Texas SBDC: not researched.", "$0", "https://georgiasbdc.org/consulting", "Guide from search results"),
]
for i, (topic, todo, ga, tx, cost, link, src) in enumerate(legal):
    r = 5 + i
    put(ws, f"A{r}", i + 1, align="center")
    put(ws, f"B{r}", topic, bold=True)
    put(ws, f"C{r}", todo)
    put(ws, f"D{r}", ga)
    put(ws, f"E{r}", tx, color=BODY)
    put(ws, f"F{r}", cost, align="center")
    inp(ws, f"G{r}", "Not started", align="left")
    if link:
        put(ws, f"H{r}", src + ": " + link, color="0563C1", link=link)
    else:
        put(ws, f"H{r}", src, color=BODY)
last_legal = 5 + len(legal) - 1
dv = DataValidation(type="list", formula1='"Not started,In progress,Done,Not needed"', allow_blank=False)
ws.add_data_validation(dv)
dv.add(f"G5:G{last_legal}")
fit_rows(ws, 5, last_legal)
ws.freeze_panes = "C5"

# --------------------------------------------------------------------------- Sponsors & Partners
ws = ws_spon
title(ws, "Sponsors and partners: who to contact",
      "Leads, not promises. I only list contacts I could verify; nothing here has been contacted. 'Fit' is my judgment.")
widths(ws, {"A": 4, "B": 30, "C": 16, "D": 44, "E": 50, "F": 42, "G": 7, "H": 13, "I": 36})
header(ws, 4, ["#", "Who", "Kind", "Why they might help", "How to reach them (verified)", "What to ask for", "Fit", "Status", "Source"])
leads = [
    ("7 Tequilas Cantina, Cumming GA", "Past sponsor", "Funded the $300 Referral Challenge prize pool in your agreement draft. That challenge was removed from the app on 2026-10-19, so a new ask needs a new idea.",
     "You already have this contact. Address in your agreement: 5063 Post Road, Cumming, GA 30040.", "A small local giveaway: 'win a Spot kit', or a few Spots for their staff to try. Do not reuse the old agreement as is.", "High", None,
     "Your file: output/sponsorship"),
    ("Studies Timer", "Partner", "Your draft agreement (1 Aug 2026 to 31 Jan 2027) has them paying you $150 plus six monthly payments of $200.",
     "studiestimer.com appeared in search; I found no contact details there, so use the contact you already have. The draft leaves both legal entity names blank.", "Cross-promotion for the Spot launch, once the app update with Spots is live.", "High", None,
     "Your file: output/partnership"),
    ("Forsyth County Chamber of Commerce", "Local network", "A local business community that runs networking and showcase events with local sponsors.",
     "212 Webb Street, Cumming, GA 30040. Phone 770-887-6461 ext. 7 (U.S. Chamber listing: confirm it is current).", "Their sponsorship packet and the price of a business showcase table.", "Medium", "https://uschamber.com/co/chambers/georgia/cumming",
     "U.S. Chamber listing"),
    ("Georgia SBDC (UGA) and SCORE Atlanta", "Free advice", "Free one-on-one advisers who also know local grants and lenders.",
     "georgiasbdc.org/consulting (enter your ZIP). score.org/ga/atlanta/contact-us.", "A free session on sponsors, the LLC question and the business license.", "High", "https://georgiasbdc.org/consulting",
     "Search results; the SBDC page says its consulting is free"),
    ("UGA Next Top Entrepreneur", "Competition", "Open to current students of any college. $17,500 in prizes in 2026 (top prize $10,000). The 2026 deadline was March 20.",
     "terry.uga.edu/events/next-top-entrepreneur. The next round probably opens in the new year: confirm.", "Entry, if you are a current college student.", "Medium", "https://www.terry.uga.edu/events/next-top-entrepreneur",
     "UGA page via search"),
    ("UGA Innovation Quick Pitch", "Competition", "Winners get up to $1,000.",
     "innovation.uga.edu, 'student looking for funding'.", "Entry. Check who is eligible; the snippet listed UGA students, employees and community members.", "Low", "https://innovation.uga.edu/resource_cat/student-looking-for-funding/",
     "UGA page via search"),
    ("Georgia Tech Startup Launch (CREATE-X)", "Program", "$5,000 optional seed funding plus coaching for Georgia Tech teams.",
     "gatech.edu news page via search; ask CREATE-X for the next cohort.", "Only if a team member is a Georgia Tech student.", "Low", "https://hg.gatech.edu/node/688851",
     "Georgia Tech page via search"),
    ("EVERFI Digital Wellness Network", "Coalition", "A coalition of companies, nonprofits and educators working on digital wellness, where funders and schools meet.",
     "everfi.com/networks/digital-wellness-network (no direct contact found).", "An introduction, or a place to list Mivo.", "Medium", "https://everfi.com/networks/digital-wellness-network",
     "EVERFI page via search"),
    ("Peace in Schools", "School partner", "Partnered with another screen-time app (Dayo), so it shows schools do work with apps like Mivo.",
     "peaceinschools.org (see its news page on digital wellbeing).", "A pilot with a school or club, with Spots on desks.", "Medium", "https://www.peaceinschools.org/news/tools-for-digital-wellbeing",
     "Peace in Schools page via search"),
    ("LiveMore ScreenLess", "School partner", "A Minnesota nonprofit running screen-time clubs in schools, funded by a $1 million state grant.",
     "Found only through a Fox 9 news story: search the name for its site.", "A pilot in one school club.", "Low", "https://www.fox9.com/news/minnesota-nonprofit-forms-partnership-with-schools-to-help-kids-cut-down-on-screentime",
     "Fox 9 story via search"),
    ("Family Online Safety Institute", "Funder network", "Receives most of its money from tech companies, which makes it a place to meet funders.",
     "Not researched: no contact found.", "An introduction. Low fit for a hand-made sticker launch.", "Low", None,
     "Reuters report via search"),
]
for i, (who, kind, why, how, ask, fit, link, src) in enumerate(leads):
    r = 5 + i
    put(ws, f"A{r}", i + 1, align="center")
    put(ws, f"B{r}", who, bold=True)
    put(ws, f"C{r}", kind)
    put(ws, f"D{r}", why)
    put(ws, f"E{r}", how)
    put(ws, f"F{r}", ask, color=BODY)
    put(ws, f"G{r}", fit, align="center")
    inp(ws, f"H{r}", "Not contacted", align="left")
    if link:
        put(ws, f"I{r}", src, color="0563C1", link=link)
    else:
        put(ws, f"I{r}", src, color=BODY)
last = 5 + len(leads) - 1
dv = DataValidation(type="list", formula1='"Not contacted,Asked,Replied,Yes,No"', allow_blank=False)
ws.add_data_validation(dv)
dv.add(f"H5:H{last}")
r = last + 2
put(ws, f"A{r}", "How to ask (a starting point, untested)", bold=True, color=DARK, size=11, wrap=False)
ask = [
    "Say what a Mivo Spot is in one sentence: a sticker on your desk that makes you pause before you scroll.",
    "Make a small, specific ask: for example $100 to $300 toward a giveaway of Spot kits, or ten kits placed in their space.",
    "Offer something concrete back: their name on the giveaway page and a post, and nothing that gives them user data.",
    "Wait for the app update with Spots to be live before you ask anyone to put money toward Spots.",
    "I have not contacted anyone. Review any message before you send it.",
]
for i, t in enumerate(ask):
    put(ws, f"A{r + 1 + i}", f"{i + 1}. {t}", wrap=False)
fit_rows(ws, 5, last)
ws.freeze_panes = "C5"

wb.save(OUT)
print("saved", OUT)
print("LINKS", len(LINKS))
