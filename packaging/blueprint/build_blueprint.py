#!/usr/bin/env python3
"""Builds the new "hand-made launch" tabs for the Mivo Pricing Model sheet as a stand-alone .xlsx.

The file holds only the new tabs. Import it into the existing Google Sheet with
File > Import > Upload > "Insert new sheet(s)", so the sheet keeps its link and old tabs.
Research dated 2026-10-23; every price has a row on the "Hand-Made Sources" tab.
"""
import datetime
import math
import pathlib

from openpyxl import Workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

OUT = pathlib.Path(__file__).parent / "Mivo-Hand-Made-Blueprint-new-tabs.xlsx"

DARK, SAND, CREAM, AMBER, DEEP, BODY = "3D2313", "F0E4CC", "FAF3E8", "D4872A", "B5621E", "6E5238"
S_START, S_PLAN, S_SHOP, S_COST = "START HERE", "Hand-Made Plan", "Shopping List", "Hand-Made Unit Cost"
S_SAVE, S_SOP, S_ORD, S_UP, S_SRC = "Save Money", "Pack-Out SOP", "Orders", "Upgrade Triggers", "Hand-Made Sources"
COST = f"'{S_COST}'!"
thin = Side(style="thin", color="D9CDBE")


def font(bold=False, color="000000", size=10, italic=False, underline=None):
    return Font(name="Arial", size=size, bold=bold, color=color, italic=italic, underline=underline)


def put(ws, ref, value, bold=False, color="000000", fill=None, num=None, wrap=True, size=10, italic=False,
        link=None, align="left", valign="top", border=False):
    c = ws[ref]
    c.value = value
    if isinstance(value, str) and value.startswith("=") and "!" in value and color == "000000":
        color = "0B8043"  # the sheet's own legend: green text = link to another tab
    c.font = font(bold, "0563C1" if link else color, size, italic, "single" if link else None)
    if link:
        c.hyperlink = link
    if fill:
        c.fill = PatternFill("solid", fgColor=fill)
    if num:
        c.number_format = num
    c.alignment = Alignment(wrap_text=wrap, vertical=valign, horizontal=align)
    if border:
        c.border = Border(bottom=thin)
    return c


def inp(ws, ref, value, num=None, align="right", ph=False):
    """An input cell, in the sheet's own legend: blue text; yellow fill only for a placeholder guess."""
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
    c.alignment = Alignment(vertical="center")


def widths(ws, spec):
    for col, w in spec.items():
        ws.column_dimensions[col].width = w


def fit_rows(ws, first, last, skip=()):
    """Set row heights from the longest wrapped cell (Sheets does not always auto-fit imported rows)."""
    for r in range(first, last + 1):
        if r in skip:
            continue
        lines = 1
        for c in ws[r]:
            if isinstance(c.value, str) and not c.value.startswith("="):
                w = ws.column_dimensions[c.column_letter].width or 10
                lines = max(lines, sum(math.ceil(max(len(p), 1) / (w * 1.05)) for p in c.value.split("\n")))
        ws.row_dimensions[r].height = max(16, 13.5 * lines + 3)


def title(ws, text, sub=None, cols=8):
    put(ws, "A1", text, bold=True, size=15, color=DARK, wrap=False, valign="center")
    ws.row_dimensions[1].height = 26
    if sub:
        put(ws, "A2", sub, italic=True, color=BODY, wrap=False)


wb = Workbook()
ws_start = wb.active
ws_start.title = S_START
ws_plan = wb.create_sheet(S_PLAN)
ws_shop = wb.create_sheet(S_SHOP)
ws_cost = wb.create_sheet(S_COST)
ws_save = wb.create_sheet(S_SAVE)
ws_sop = wb.create_sheet(S_SOP)
ws_ord = wb.create_sheet(S_ORD)
ws_up = wb.create_sheet(S_UP)
ws_src = wb.create_sheet(S_SRC)
for w, color in ((ws_start, AMBER), (ws_plan, DEEP), (ws_shop, DEEP), (ws_cost, DEEP), (ws_save, DEEP),
                 (ws_sop, DEEP), (ws_ord, DEEP), (ws_up, DEEP), (ws_src, "A8896F")):
    w.sheet_properties.tabColor = color
    w.sheet_view.showGridLines = False

# --------------------------------------------------------------------------- Hand-Made Unit Cost
ws = ws_cost
title(ws, "Hand-made unit cost: what one order costs you and earns",
      "Same colours as README: blue text = input, black = formula, green = link to another tab, yellow fill = placeholder guess. USD. Prices checked 2026-10-23.")
widths(ws, {"A": 44, "B": 17, "C": 17, "D": 46, "E": 46, "F": 34})

section(ws, 4, "1. Sticker sources (pick one in B13)", 6)
header(ws, 5, ["Source", "Pack size", "Pack price", "Each", "Chip and adhesive", "Status on 2026-10-23"])
sources = [
    ("Tagstand 25-pack sample", 25, 12.50, "Genuine NXP NTAG213, 25 mm, 3M 467MP adhesive", "In stock, 3 packs left"),
    ("Amazon TimesKey 10-pack", 10, 7.99, "NTAG213 (listing says genuine), white PET, adhesive not stated", "The listing you chose; 30-day free returns"),
    ("Walmart generic 100-pack", 100, 9.20, "Chip maker and size not stated", "Price from a search snapshot; quality unknown"),
    ("Your own quote", None, None, "Type a pack size and price to compare", ""),
]
for i, (name, size, price, chip, status) in enumerate(sources):
    r = 6 + i
    put(ws, f"A{r}", name)
    if size:
        inp(ws, f"B{r}", size, "0")
        inp(ws, f"C{r}", price, "$#,##0.00")
    else:
        inp(ws, f"B{r}", None, "0")
        inp(ws, f"C{r}", None, "$#,##0.00")
    put(ws, f"D{r}", f'=IF(B{r}>0,C{r}/B{r},"")', num="$0.000", align="right")
    put(ws, f"E{r}", chip)
    put(ws, f"F{r}", status)

section(ws, 11, "2. Inputs", 6)
header(ws, 12, ["Item", "Value", "Unit", "Where the number comes from"])
rows = [
    (13, "Sticker source used", "Amazon TimesKey 10-pack", None, "", "Dropdown: choose a source from table 1"),
    (14, "Sticker cost each", "=INDEX(D6:D9,MATCH(B13,A6:A9,0))", "$0.000", "$", "Formula: looked up from table 1"),
    (15, "Clear cover roll price", 9.60, "$#,##0.00", "$", "LabelValue 1.5 in clear round labels, roll of 500, free US shipping (6+ rolls: $7.53 each)"),
    (16, "Covers per roll", 500, "0", "count", "Same listing"),
    (17, "Clear cover cost each", "=B15/B16", "$0.000", "$", "Formula"),
    (18, "Cardstock pack price", 28.99, "$#,##0.00", "$", "Staples 65 lb cardstock, 8.5 x 11, 250 sheets (coloured pack; white is similar, check). Walmart had one at $22.99"),
    (19, "Sheets per pack", 250, "0", "count", "Same listing"),
    (20, "Cards cut from one sheet", 4, "0", "count", "The home-print sheet gives four 5.5 x 4.25 in cards"),
    (21, "Cardstock cost per card", "=B18/B19/B20", "$0.000", "$", "Formula"),
    (22, "Ink cost per printed page", 0.08, "$0.000", "$", "Low end of 8 to 30 cents per colour page for cartridge printers; ink-tank printers are 1 to 5 cents (retailer estimates). Use your own number"),
    (23, "Printed pages per sheet", 2, "0", "count", "Front and back"),
    (24, "Ink cost per card", "=B22*B23/B20", "$0.000", "$", "Formula"),
    (25, "Card cost (paper + ink)", "=B21+B24", "$0.000", "$", "Formula"),
    (26, "Envelope pack price", 18.99, "$#,##0.00", "$", "JAM Paper A6 (4 3/4 x 6 1/2 in) white, 100-pack, Staples. A6 kraft: $66 for 250 (Walmart)"),
    (27, "Envelopes per pack", 100, "0", "count", "Same listing"),
    (28, "Envelope cost each", "=B26/B27", "$0.000", "$", "Formula"),
    (29, "Postage per order (1 oz letter, stamped)", 0.82, "$0.00", "$", "USPS Notice 123, effective 2026-10-04. Metered is $0.78; 2 oz is $1.11"),
    (30, "Card fee, percent", 0.029, "0.0%", "%", "Stripe standard US card rate; Payment Links cost nothing extra"),
    (31, "Card fee, fixed", 0.30, "$0.00", "$", "Stripe, per successful charge"),
    (32, "Replacement allowance", 0.03, "0.0%", "%", "Your Sheet's 3% allowance: re-send when a sticker fails. Applied to materials + postage"),
    (33, "Minutes of your time per order", 10, "0", "min", "My guess for packing plus order handling. Time one real order and replace it"),
]
for r, label, val, fmt, unit, note in rows:
    put(ws, f"A{r}", label)
    if isinstance(val, str) and val.startswith("="):
        put(ws, f"B{r}", val, num=fmt, align="right")
    elif r == 13:
        inp(ws, f"B{r}", val)
        ws[f"B{r}"].alignment = Alignment(wrap_text=True, horizontal="left", vertical="top")
    else:
        inp(ws, f"B{r}", val, fmt, ph=r in (18, 22, 32, 33))
    put(ws, f"C{r}", unit, align="center")
    put(ws, f"D{r}", note, color=BODY)
    ws.merge_cells(f"D{r}:F{r}")
dv = DataValidation(type="list", formula1="=$A$6:$A$9", allow_blank=False)
ws.add_data_validation(dv)
dv.add("B13")

section(ws, 35, "3. What one order costs and earns", 6)
header(ws, 36, ["Line", "Single Spot", "3-pack", "Note"])
money = "$#,##0.00"
lines = [
    (37, "Price charged", 14.99, 34.99, "Prices from your Pricing Model v2 plan", "input"),
    (38, "Shipping charged", 2.99, 0, "Your Sheet's plan: charge shipping on a single, free on the 3-pack", "input"),
    (39, "Total charged", "=B37+B38", "=C37+C38", "", "f"),
    (40, "Stickers in the order", 1, 3, "", "inputint"),
    (41, "Stickers", "=B40*$B$14", "=C40*$B$14", "", "f"),
    (42, "Clear covers", "=B40*$B$17", "=C40*$B$17", "One per sticker", "f"),
    (43, "Card", "=$B$25", "=$B$25", "One card per order", "f"),
    (44, "Envelope", "=$B$28", "=$B$28", "", "f"),
    (45, "Materials subtotal", "=SUM(B41:B44)", "=SUM(C41:C44)", "", "fb"),
    (46, "Postage", "=$B$29", "=$B$29", "A card and envelope are about 0.4 oz (my estimate: weigh one)", "f"),
    (47, "Replacement allowance", "=$B$32*(B45+B46)", "=$B$32*(C45+C46)", "", "f"),
    (48, "Card processing fee", "=$B$30*B39+$B$31", "=$B$30*C39+$B$31", "Fee is charged on shipping too", "f"),
    (49, "Total cost to you", "=B45+B46+B47+B48", "=C45+C46+C47+C48", "", "fb"),
    (50, "Profit before your time", "=B39-B49", "=C39-C49", "Before sales tax, which you collect and pass on", "fb"),
    (51, "Margin", "=B50/B39", "=C50/C39", "", "pct"),
    (52, "Profit per hour of your time", "=B50/($B$33/60)", "=C50/($B$33/60)", "Only as good as the minutes guess in B33", "f"),
    (53, "Old bulk-route profit (Pricing Model v2, my 2026-10-20 notes)", 12.71, 27.09, "Different assumptions: printed tags at $0.77 landed, $0.21 cards, flat postage", "inputref"),
    (54, "Difference: hand-made minus bulk route", "=B50-B53", "=C50-C53", "", "f"),
]
for r, label, b, c, note, kind in lines:
    put(ws, f"A{r}", label, bold=kind in ("fb",))
    for col, v in (("B", b), ("C", c)):
        if kind in ("input", "inputref"):
            inp(ws, f"{col}{r}", v, money)
        elif kind == "inputint":
            inp(ws, f"{col}{r}", v, "0")
        elif kind == "pct":
            put(ws, f"{col}{r}", v, num="0.0%", align="right")
        else:
            put(ws, f"{col}{r}", v, num=money, align="right", bold=(kind == "fb"))
    put(ws, f"D{r}", note, color=BODY)
    ws.merge_cells(f"D{r}:F{r}")
for r in (49, 50):
    for col in "ABC":
        ws[f"{col}{r}"].fill = PatternFill("solid", fgColor=CREAM)

section(ws, 56, "4. Paying back the starter spend", 6)
put(ws, "A57", "Starter shopping list total")
put(ws, "B57", f"='{S_SHOP}'!G12", num=money, align="right")
put(ws, "D57", "From the Shopping List tab (buy-now items)", color=BODY)
put(ws, "A58", "Profit on one Single Spot")
put(ws, "B58", "=B50", num=money, align="right")
put(ws, "A59", "Single Spots to sell to repay it", bold=True)
put(ws, "B59", "=ROUNDUP(B57/B58,0)", num="0", align="right", bold=True)
for r in (57, 58, 59):
    ws.merge_cells(f"D{r}:F{r}")
fit_rows(ws, 6, 59, skip=(11, 35, 56))
ws.freeze_panes = "A4"

# --------------------------------------------------------------------------- Shopping List
ws = ws_shop
title(ws, "Shopping list for the first 25 to 35 Spots",
      "Quantities are for one hand-made batch. Prices are the ones I found on 2026-10-23: check at checkout. Tax and shipping on supplies are not included.")
widths(ws, {"A": 5, "B": 9, "C": 26, "D": 52, "E": 7, "F": 11, "G": 11, "H": 40, "I": 12, "J": 11, "K": 52})
header(ws, 4, ["#", "Priority", "Item", "Exact thing to buy", "Qty", "Unit price", "Line total", "Where", "Buy when", "Bought?", "Notes"])
section(ws, 5, "BUY NOW: enough for about 25 to 35 Spots", 11)
tag = "https://www.tagstand.com/products/25-sample-stickers-the-25-25-25-roll-of-ntag213-stickers-25mm-circle-25-cents-each"
amz = "https://www.amazon.com/dp/B09NXXTXHL"
lbl = "https://www.labelvalue.com/15-round-labels-clear-p-929.html"
card = "https://www.staples.com/staples-65-lb-cardstock-paper-8-5-x-11-bright-blue-250-sheets-pack-92099/product_24695615"
env = "https://www.staples.com/jam-paper-a6-booklet-envelope-4-3-4-x-6-1-2-white-100-pack-j0567d/product_24604576"
buy_now = [
    (1, "Next", "NFC stickers for customers (second order)", "Tagstand 25 mm NTAG213 sticker, 25-pack sample (genuine NXP chip, 3M 467MP adhesive)", 1, 12.50, ("Tagstand", tag), "Day 8", "Order after the Amazon 10-pack passes your tests. Only 3 packs were in stock on 2026-10-23; if gone, buy two Amazon 10-packs (20 stickers for $15.98)"),
    (2, "Must", "NFC stickers: first order (test pack)", "Amazon TimesKey 25 mm NTAG213 white, 10-pack (the listing you picked)", 1, 7.99, ("Amazon", amz), "Day 1", "Order this first. Use all 10 for your tap, cover and peel tests. 30-day free returns"),
    (3, "Must", "Clear covers", "LabelValue 1.5 in clear round labels, roll of 500, permanent adhesive", 1, 9.60, ("LabelValue", lbl), "Day 1", "Free US shipping. 500 covers lasts well past this batch. 1.25 in clear labels are not sold as cheap stock"),
    (4, "Must", "Cardstock", "65 lb white cardstock, 8.5 x 11 in, 250 sheets", 1, 28.99, ("Staples", card), "Day 1", "Price shown is Staples' coloured pack; buy white and check the price. 250 sheets makes 1,000 cards"),
    (5, "Must", "Envelopes", "JAM Paper A6 envelopes, 4 3/4 x 6 1/2 in, white, 100-pack", 1, 18.99, ("Staples", env), "Day 1", "A6 is the size that fits a 5.5 x 4.25 in card. 4 x 6 in envelopes are too small. A6 kraft costs more ($66 for 250)"),
    (6, "Must", "Stamps", "USPS Forever stamps (1 oz letter)", 20, 0.82, ("Post office", None), "Day 5", "Buy them when you take your test pack to be weighed. Metered letters are $0.78 but need a meter or online postage"),
]
r = 6
for n, pri, item, spec, qty, price, (wname, wurl), when, note in buy_now:
    put(ws, f"A{r}", n, align="center")
    put(ws, f"B{r}", pri)
    put(ws, f"C{r}", item, bold=True)
    put(ws, f"D{r}", spec)
    inp(ws, f"E{r}", qty, "0")
    inp(ws, f"F{r}", price, "$#,##0.00", ph=(n == 4))
    put(ws, f"G{r}", f"=E{r}*F{r}", num="$#,##0.00", align="right")
    put(ws, f"H{r}", wname, link=wurl)
    put(ws, f"I{r}", when)
    put(ws, f"J{r}", "No")
    put(ws, f"K{r}", note, color=BODY)
    r += 1
put(ws, "C12", "TOTAL (all six items)", bold=True)
put(ws, "G12", "=SUM(G6:G11)", num="$#,##0.00", align="right", bold=True)
put(ws, "C13", "Pay in week 1 (Day 1 items)", bold=True)
put(ws, "G13", '=SUMIF(I6:I11,"Day 1",G6:G11)', num="$#,##0.00", align="right", bold=True)
for col in "ABCDEFGHIJK":
    ws[f"{col}12"].fill = PatternFill("solid", fgColor=CREAM)
dv = DataValidation(type="list", formula1='"No,Ordered,Received"', allow_blank=False)
ws.add_data_validation(dv)
dv.add("J6:J11")
dv.add("J15:J18")

section(ws, 14, "ALREADY HAVE OR FREE (cost $0)", 11)
free = [
    ("Home printer and ink", "Ink is modelled per card on the Hand-Made Unit Cost tab. Do not buy a new printer for 25 Spots"),
    ("Scissors, ruler, craft knife", "Cut the home-print sheet on the dashed lines. A paper trimmer is optional later"),
    ("Post office scale", "Free: the clerk weighs your test pack"),
    ("Pen for addressing", "Write addresses by hand until you ship more than about 20 a week"),
]
for i, (item, note) in enumerate(free):
    rr = 15 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", "Have")
    put(ws, f"C{rr}", item, bold=True)
    inp(ws, f"E{rr}", 0, "0")
    inp(ws, f"F{rr}", 0, "$#,##0.00")
    put(ws, f"G{rr}", f"=E{rr}*F{rr}", num="$#,##0.00", align="right")
    put(ws, f"J{rr}", "No")
    put(ws, f"K{rr}", note, color=BODY)

section(ws, 20, "BUY LATER: only when a trigger on the Upgrade Triggers tab fires (not in the total)", 11)
later = [
    ("Stickers in bulk", "Tagstand 25 mm NTAG213 roll of 500", 1, 170.00, ("Tagstand", "https://www.tagstand.com/products/500-count-ntag213-25-25-25-stickers-25mm-round/"), "$0.34 each. Out of stock on 2026-10-23"),
    ("Clear covers in bulk", "LabelValue 1.5 in clear round labels, 12+ rolls", 12, 6.95, ("LabelValue", lbl), "Price per roll of 500 at 12 or more rolls"),
    ("Cheaper envelopes", "#10 white envelopes, 500-box", 1, 20.99, ("Staples", "https://www.staples.com/Staples-Gummed-10-Envelope-4-1-8-x-9-1-2-White-500-Box-187013NB/product_187013"), "About $0.04 each, but cards must be cut 4.0 in tall to fit. Price from a search snapshot; the page blocked my check"),
    ("Paper trimmer", "Not researched", 0, 0, ("", None), "Skip until you cut more than about 50 cards a week"),
]
for i, (item, spec, qty, price, (wname, wurl), note) in enumerate(later):
    rr = 21 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", "Later")
    put(ws, f"C{rr}", item, bold=True)
    put(ws, f"D{rr}", spec)
    inp(ws, f"E{rr}", qty, "0")
    inp(ws, f"F{rr}", price, "$#,##0.00")
    put(ws, f"G{rr}", f"=E{rr}*F{rr}", num="$#,##0.00", align="right")
    if wname:
        put(ws, f"H{rr}", wname, link=wurl)
    put(ws, f"K{rr}", note, color=BODY)
fit_rows(ws, 6, 24, skip=(14, 20))
ws.freeze_panes = "A5"

# --------------------------------------------------------------------------- START HERE
ws = ws_start
widths(ws, {"A": 3, "B": 58, "C": 22, "D": 78})
put(ws, "B2", "Mivo Spots: hand-made launch blueprint", bold=True, size=18, color=DARK, wrap=False, valign="center")
ws.row_dimensions[2].height = 30
put(ws, "B3", "Updated 2026-10-23. Nothing is automated yet, so every step below is done by hand, with the cheapest options I could verify.",
    italic=True, color=BODY, wrap=False)
put(ws, "B5", "Your start date (change this one cell; every due date moves)", bold=True)
inp(ws, "C5", datetime.date(2026, 10, 26), "ddd mmm d, yyyy")

section(ws, 7, "Your numbers (live from the other tabs)", 4)
ws["A7"].value = None
for col in "BCD":
    ws[f"{col}7"].fill = PatternFill("solid", fgColor=SAND)
put(ws, "B7", "Your numbers (live from the other tabs)", bold=True, color=DARK, size=11, fill=SAND)
nums = [
    (8, "Cost to make and ship one Single Spot", f"={COST}B49", "Stickers, cover, card, envelope, postage, card fee, replacements"),
    (9, "Profit on one Single Spot ($14.99 + $2.99 shipping)", f"={COST}B50", "Before your time and before sales tax"),
    (10, "Cost to make and ship one 3-pack", f"={COST}C49", ""),
    (11, "Profit on one 3-pack ($34.99, free shipping)", f"={COST}C50", ""),
    (12, "Starter shopping list (about 25 to 35 Spots)", f"='{S_SHOP}'!G12", "Shopping List tab, buy-now items"),
    (13, "Single Spots to sell to repay the starter spend", f"={COST}B59", ""),
    (14, "Minutes of your time per order (your estimate)", f"={COST}B33", "Replace with a real timing after your first pack-out"),
]
for rr, label, formula, note in nums:
    put(ws, f"B{rr}", label)
    fmt = "0" if rr in (13, 14) else "$#,##0.00"
    put(ws, f"C{rr}", formula, num=fmt, align="right", bold=True)
    put(ws, f"D{rr}", note, color=BODY)

put(ws, "B16", "Do these first (this week)", bold=True, color=DARK, size=11, fill=SAND)
for col in "CD":
    ws[f"{col}16"].fill = PatternFill("solid", fgColor=SAND)
first = [
    ("1. Order the first batch of supplies", "Amazon 10-pack first (your pick), then clear labels, cardstock and A6 envelopes. Tagstand waits until the 10-pack passes your tests"),
    ("2. Apply for a Texas sales tax permit", "Free, takes 2 to 3 weeks, needs your SSN (comptroller.texas.gov/taxes/permit). Only if you live in Texas: tell me if not"),
    ("3. Open or confirm your Stripe account", "2.9% + 30 cents per sale, no monthly fee. Do not switch on the $10 a month custom domain"),
    ("4. Print one home-print test sheet and cut a card", "File: packaging/print/home-print.pdf (single) or home-print-3pack.pdf. Settings are on the Pack-Out SOP tab"),
    ("5. Take a packed test card to the post office", "Buy 20 stamps, have it weighed, and ask if it prices as a letter with no surcharge"),
    ("6. Tell me where you live", "So I can fix the tax steps. The first sticker order is decided: the Amazon 10-pack"),
]
for i, (a, b) in enumerate(first):
    put(ws, f"B{17 + i}", a, bold=True)
    put(ws, f"D{17 + i}", b, color=BODY)

put(ws, "B24", "How the tabs fit together", bold=True, color=DARK, size=11, fill=SAND)
for col in "CD":
    ws[f"{col}24"].fill = PatternFill("solid", fgColor=SAND)
header(ws, 25, ["Tab", "Kind", "What it is for"], start_col=2)
tabs = [
    (S_PLAN, "NEW", "The step-by-step plan with dates, in order. Work down it."),
    (S_SHOP, "NEW", "Exactly what to buy, how many, and where, with live totals."),
    (S_SOP, "NEW", "How to assemble and pack a Spot by hand, with a quality checklist."),
    (S_ORD, "NEW", "Log each order here. Totals update on their own."),
    (S_COST, "NEW", "What one order costs and earns. Change an input and everything updates."),
    (S_SAVE, "NEW", "Every way I found to spend less, with the evidence and the catch."),
    (S_UP, "NEW", "When to stop doing it by hand, and what to switch to."),
    (S_SRC, "NEW", "Every link and date behind the numbers."),
    ("To-Dos", "OLD", "41 tasks for the bulk, printed-tag route. Use Hand-Made Plan now; come back when a trigger fires."),
    ("Landed Cost, Suppliers, Launch Budget", "OLD", "Bulk-route costs (GoToTags or Shenzhen tags, printed cards). Not your route yet."),
    ("Tag Spec", "OLD", "What to ask a tag supplier for. Still right: NTAG213, 25 to 30 mm, genuine NXP."),
    ("Shipping", "OLD", "USPS rates. I re-checked the letter and flat rows on 2026-10-23: they are correct."),
    ("Spot Economics, Assumptions, Price Test", "OLD", "Pricing logic. Unchanged. The hand-made profit is on Hand-Made Unit Cost."),
    ("Subscriptions, 12-Month Projection, Feature Gating, Fixed Costs, Competitors, Risks, Sources", "OLD", "Mivo Plus and the wider business. Unchanged."),
]
for i, (name, kind, what) in enumerate(tabs):
    rr = 26 + i
    put(ws, f"B{rr}", name, bold=(kind == "NEW"))
    put(ws, f"C{rr}", kind, color=("5F7F63" if kind == "NEW" else BODY), bold=True)
    put(ws, f"D{rr}", what, color=BODY)

put(ws, "B41", "Only you can do or decide these", bold=True, color=DARK, size=11, fill=SAND)
for col in "CD":
    ws[f"{col}41"].fill = PatternFill("solid", fgColor=SAND)
only_you = [
    ("Where you live and ship from", "The Amazon page showed delivery to Frisco, TX, so I assumed Texas (8.25% sales tax there). Confirm"),
    ("Pay for supplies and open Stripe", "I can't make purchases or enter your tax or account details"),
    ("Apply for the sales tax permit", "It needs your SSN"),
    ("Second sticker order", "Decided: the Amazon 10-pack first. If it passes your tests, Tagstand costs less per sticker and names the adhesive"),
    ("Business name", "Selling as yourself needs nothing extra. Using 'Mivo' as a business name may need an assumed-name filing with your county clerk (I did not check the fee)"),
]
for i, (a, b) in enumerate(only_you):
    put(ws, f"B{42 + i}", a, bold=True)
    put(ws, f"D{42 + i}", b, color=BODY)
fit_rows(ws, 8, 46, skip=(16, 24, 41))
ws.freeze_panes = "A4"

# --------------------------------------------------------------------------- Hand-Made Plan
ws = ws_plan
title(ws, "Hand-made launch plan",
      "Work down the list. Day numbers count from your start date on START HERE. Change Status as you go.")
widths(ws, {"A": 5, "B": 20, "C": 38, "D": 70, "E": 6, "F": 14, "G": 9, "H": 10, "I": 13, "J": 36})
put(ws, "A3", "Start date", bold=True, wrap=False)
put(ws, "C3", f"='{S_START}'!C5", num="ddd mmm d, yyyy", align="left")
put(ws, "A4", "Progress", bold=True, wrap=False)
header(ws, 6, ["#", "Phase", "Task", "How", "Day", "Due", "Time", "Cost ($)", "Status", "Notes"])
tasks = [
    ("0 Decide", "Confirm you sell and ship in the US only", "International parcels cost $19 to $25 (Shipping tab), more than a Spot earns. Add other countries later.", 0, "5 min", 0),
    ("0 Decide", "Confirm the launch products and prices", "Single $14.99 plus $2.99 shipping. 3-pack $34.99, free shipping. The Kit (3 Spots + 1 year Plus) waits: the app has no Plus subscription yet.", 0, "10 min", 0),
    ("0 Decide", "Confirm where you live", "The Amazon page showed delivery to Frisco, TX, so this plan assumes Texas. If that is wrong, the tax steps change.", 0, "2 min", 0),
    ("0 Decide", "Apply for a Texas sales tax permit", "Free. comptroller.texas.gov/taxes/permit, 'Apply for Permit via eSystems'. Needs your SSN. Allow 2 to 3 weeks. Do not enter a DBA in the legal-name field.", 1, "30 min", 0),
    ("0 Decide", "Open or confirm your Stripe account", "stripe.com. 2.9% + 30 cents per card sale, no monthly fee. Leave the $10 a month custom domain and the 0.4% invoices off.", 1, "30 min", 0),
    ("0 Decide", "Decide the business name on receipts", "Selling as yourself is the default. Using 'Mivo' as a name may need an assumed-name filing with your county clerk (fee not checked).", 2, "15 min", 0),
    ("1 Buy", "Order the first batch of supplies", "Amazon 10-pack first (your pick), then clear labels, cardstock and A6 envelopes. Keep every receipt. Stamps wait until Day 5 and the second sticker order until your tests pass.", 1, "20 min", f"=SUMIF('{S_SHOP}'!I6:I11,\"Day 1\",'{S_SHOP}'!G6:G11)"),
    ("1 Buy", "Buy 20 Forever stamps", "At the post office, on the day you take them your test pack.", 5, "10 min", f"='{S_SHOP}'!G11"),
    ("2 Prove it works", "Program 10 stickers", "Mivo app, Admin Center, Spots: choose 10, tap 'Generate 10 & start programming', then hold each sticker to the phone in turn. 'Continue programming' resumes a batch.", 4, "15 min", 0),
    ("2 Prove it works", "Tap-test every sticker", "Tap each with an iPhone: it should open 'Meet your new Mivo Spot'. Leave before the last step so it stays unclaimed. Set aside any sticker that does not read.", 4, "10 min", 0),
    ("2 Prove it works", "Add covers to 3 stickers and re-test", "Follow the cover steps on Pack-Out SOP. Tap again through the cover.", 5, "10 min", 0),
    ("2 Prove it works", "Stick one on a desk, a car dash and bare metal", "Expect the metal one to fail (the listing says not for metal). Note how the cover holds after a few days.", 5, "10 min", 0),
    ("2 Prove it works", "Peel-test a sticker off the cardstock", "It should lift cleanly. If it tears the card face, switch to glossy cardstock.", 5, "5 min", 0),
    ("2 Prove it works", "Print and cut one test sheet", "home-print.pdf: Letter, landscape, Actual size, two-sided. Test the duplex flip. Cut on the dashed lines. Check no ink clips at the sheet edge.", 5, "20 min", 0),
    ("2 Prove it works", "Weigh and price a packed test order", "Card plus covered sticker in an A6 envelope. Ask the clerk to confirm a stamped 1 oz letter with no rigid or lumpy surcharge ($0.49).", 6, "20 min", 0),
    ("2 Prove it works", "Mail one to yourself", "Check it arrives flat, the sticker is intact, and it still reads.", 6, "5 min", 0.82),
    ("2 Prove it works", "Time one full pack-out, then order the next stickers", "Write the minutes in B33 on Hand-Made Unit Cost. If at least 9 of 10 stickers read and the cover held, order the Tagstand 25-pack (or more Amazon packs): allow about a week for delivery.", 7, "10 min", f"='{S_SHOP}'!G6"),
    ("3 Friends beta", "Make 10 packs", "Needs the second sticker order: the first 10-pack went into your tests. Use the batch workflow on Pack-Out SOP.", 11, "45 min", 0),
    ("3 Friends beta", "Give them to 10 people you trust", "Hand over or mail. Sit with at least 3 while they do the first tap. Write down every moment of confusion.", 12, "2 h", 0),
    ("3 Friends beta", "Fix the card wording", "Edit the text in packaging/build.py and reprint, or ask Claude to.", 15, "1 h", 0),
    ("3 Friends beta", "Check claims in Admin", "Packs handed out vs Spots claimed. Any 'taken', 'invalid' or 'disabled' messages mean a bad sticker or a mix-up.", 15, "15 min", 0),
    ("3 Friends beta", "Decide go or no-go", "Go if at least 8 of 10 people set up without your help and no tag failed after a week.", 17, "10 min", 0),
    ("4 Open sales", "Create the Stripe Payment Links", "One-time prices. Single $14.99 with a $2.99 shipping rate. 3-pack $34.99 with free shipping. Collect a shipping address, United States only.", 18, "1 h", 0),
    ("4 Open sales", "Decide how to handle sales tax at checkout", "If you hold the Texas permit, you must charge tax on physical goods (Frisco is 8.25%). Stripe Tax can add it but is a paid add-on whose fee I did not check; the other way is to include tax in the price.", 19, "30 min", 0),
    ("4 Open sales", "Add the Payment Links to usemivo.app", "Ask Claude to add a Spots buy section. The site deploys with the vercel CLI.", 19, "1 h", 0),
    ("4 Open sales", "Write the replacement policy", "Suggested: 'If a Spot doesn't work, we replace it free.' Matches the 3% allowance.", 19, "20 min", 0),
    ("4 Open sales", "Check support is ready", "usemivo.app/support exists. Decide who answers and promise a reply within 24 hours.", 20, "20 min", 0),
    ("4 Open sales", "Make 15 more packs for stock", "Same workflow. Restock stickers if fewer than 10 packs remain.", 21, "1 h", 0),
    ("4 Open sales", "Tell your own audience", "Post the link on Mivo's accounts and to the friends from the beta.", 22, "30 min", 0),
    ("5 Run weekly", "On every order: pack within 2 business days", "Stripe email, pull a pack, stamp and address, mail, then log it on the Orders tab.", 22, "5 min each", 0),
    ("5 Run weekly", "Weekly: restock check", "Reorder when stickers or covers cover fewer than 10 packs. Allow about a week for delivery.", 29, "10 min", 0),
    ("5 Run weekly", "Weekly: match Stripe payouts to the Orders tab", "Catch any refund or missing address early.", 29, "15 min", 0),
    ("5 Run weekly", "Monthly: file the Texas sales tax return", "Returns are due even with no sales. Due dates are on your Comptroller account (not checked).", 45, "20 min", 0),
    ("5 Run weekly", "Monthly: read the Upgrade Triggers tab", "Switch only when a trigger has fired.", 45, "10 min", 0),
    ("6 App fixes (ask Claude)", "Add tag write-lock to Admin programming", "I searched the app code on 2026-10-23 and found no tag-lock call, so anyone with an NFC app can overwrite a sticker. Add before many Spots are out.", 14, "1 session", 0),
    ("6 App fixes (ask Claude)", "Do not rely on iPhone TagInfo to prove chips are genuine", "An NXP forum thread says iPhone TagInfo does not reliably check the originality signature. Buy from a seller that names NXP and test every tag instead.", 4, "0", 0),
]
first_task, last_task = 7, 7 + len(tasks) - 1
phase_fill = {"0": "FFF8DC", "1": "FAF3E8", "2": "F0E4CC", "3": "FAF3E8", "4": "F0E4CC", "5": "FAF3E8", "6": "FFF8DC"}
for i, (phase, task, how, day, time, cost) in enumerate(tasks):
    rr = first_task + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", phase, bold=True, color=DEEP)
    put(ws, f"C{rr}", task, bold=True)
    put(ws, f"D{rr}", how)
    inp(ws, f"E{rr}", day, "0", align="center")
    put(ws, f"F{rr}", f"=$C$3+E{rr}", num="ddd mmm d", align="center")
    put(ws, f"G{rr}", time, align="center")
    if isinstance(cost, str):
        put(ws, f"H{rr}", cost, num="$#,##0.00", align="right")
    else:
        inp(ws, f"H{rr}", cost, "$#,##0.00")
    inp(ws, f"I{rr}", "Not started")
    put(ws, f"J{rr}", "")
    for col in "ABC":
        ws[f"{col}{rr}"].fill = PatternFill("solid", fgColor=phase_fill[phase[0]])
put(ws, "C4", f'=COUNTIF(I{first_task}:I{last_task},"Done")&" of "&COUNTA(C{first_task}:C{last_task})&" tasks done"', bold=True, align="left")
dv = DataValidation(type="list", formula1='"Not started,In progress,Done,Blocked"', allow_blank=False)
ws.add_data_validation(dv)
dv.add(f"I{first_task}:I{last_task}")
ws.conditional_formatting.add(
    f"A{first_task}:J{last_task}",
    FormulaRule(formula=[f'$I{first_task}="Done"'], font=Font(name="Arial", color="8A8A8A", strike=True)),
)
ws.conditional_formatting.add(
    f"I{first_task}:I{last_task}",
    FormulaRule(formula=[f'$I{first_task}="Blocked"'], fill=PatternFill("solid", bgColor="F4C7C3")),
)
fit_rows(ws, first_task, last_task)
ws.freeze_panes = "A7"

# --------------------------------------------------------------------------- Save Money
ws = ws_save
title(ws, "Save money: every lever I found, with the evidence and the catch",
      "Prices checked 2026-10-23. 'Verified' means I read it on the seller's or USPS's page. 'Medium' means a search snapshot or secondary source.")
widths(ws, {"A": 4, "B": 14, "C": 34, "D": 11, "E": 34, "F": 11, "G": 11, "H": 13, "I": 30, "J": 9, "K": 56, "L": 30})
header(ws, 5, ["#", "Where the money goes", "Default option", "Default $ per Spot", "Cheaper option", "Cheaper $ per Spot",
               "Saves per Spot", "Saves over 100 Spots", "Confidence", "Do it?", "The catch", "Source"])
levers = [
    ("Postage", "Large envelope (flat), 1 oz", 1.69, "Letter, stamped, 1 oz", f"={COST}B29", "Verified", "Do now",
     "Needs to stay 1 oz, flexible and lump-free. Weigh and flex-test one at the post office. A rigid or lumpy letter adds $0.49.", "USPS Notice 123"),
    ("Postage", "Ground Advantage up to 4 oz, commercial, zones 1-2", 7.33, "Letter, stamped, 1 oz", f"={COST}B29", "Verified (7.33 is from your Shipping tab, not re-checked)", "Do now",
     "Letters are untracked. Your Sheet allows for 1 to 3% lost mail. Offer tracked shipping as a paid upgrade.", "Shipping tab; USPS Notice 123"),
    ("Postage", "Stamped letter", f"={COST}B29", "Metered letter", 0.78, "Verified", "Later",
     "Needs a postage meter or an online postage account. Not worth it until you send 100+ letters a month.", "USPS Notice 123"),
    ("Stickers", "Amazon TimesKey 10-pack", f"={COST}D7", "Tagstand 25-pack (genuine NXP, 3M 467MP adhesive)", f"={COST}D6", "Verified", "Later",
     "Order after your Amazon 10-pack passes the tests. Only 3 packs were in stock on 2026-10-23.", "Tagstand product page; Amazon listing"),
    ("Stickers", "Amazon TimesKey 10-pack", f"={COST}D7", "Walmart generic 100-pack", f"={COST}D8", "Price medium; quality unknown", "Later",
     "Chip maker and size are not stated. Buy only after a small sample passes your tap and read tests.", "Walmart search result"),
    ("Envelope", "A6 white, 100-pack", f"={COST}B28", "#10 white, 500-box", 0.042, "Medium (search snapshot; the page blocked my check)", "Later",
     "#10 is 4 1/8 in tall, so cards must be cut 4.0 in tall, not 4.25, and the home-print layout changes.", "Staples listing"),
    ("Ink", "Cartridge printer, per card", f"={COST}B24", "Ink-tank printer at 2 cents a page", f"=0.02*{COST}B23/{COST}B20", "Estimate (retailer ranges)", "Skip",
     "A tank printer costs about $150 to $250 and saves about 3 cents a card, so it pays back only after thousands of cards.", "Castle Ink; HP; Digital Trends"),
    ("Selling", "Etsy: 6.5% + 3% + $0.25, plus $0.20 listing (per single order)", f"={COST}B39*0.095+0.45", "Stripe Payment Link: 2.9% + $0.30", f"={COST}B48", "Medium (Etsy from comparison sites; Stripe from stripe.com/pricing)", "Do now",
     "Etsy brings buyers; a Payment Link does not. You send people to your own link.", "Stripe pricing; NerdWallet"),
    ("Selling", "Shopify Basic at 25 orders a month ($29 to $39 a month; sources differ)", "=34/25", "Stripe Payment Link, no monthly fee", 0, "Medium", "Do now",
     "No storefront, cart or inventory sync. Fine for two products.", "Trueprofit; NerdWallet"),
    ("Selling", "Stripe custom domain add-on, $10 a month, at 25 orders a month", "=10/25", "Leave it off", 0, "Verified", "Do now",
     "Payment Links work on Stripe's own address.", "Stripe pricing"),
    ("Replacements", "Skip testing and reship the 3% that fail (cost of a full re-send)", f"={COST}B49*0.03", "Tap-test every sticker before it goes in a pack", 0, "Estimate (3% is your Sheet's allowance)", "Do now",
     "About 20 seconds per sticker. Do not skip it, especially with unbranded stickers.", "Amazon reviews; Hand-Made Unit Cost"),
]
for i, (area, d_opt, d_cost, c_opt, c_cost, conf, act, catch, src) in enumerate(levers):
    rr = 6 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", area, bold=True)
    put(ws, f"C{rr}", d_opt)
    put(ws, f"D{rr}", d_cost, num="$#,##0.000", align="right")
    put(ws, f"E{rr}", c_opt)
    put(ws, f"F{rr}", c_cost, num="$#,##0.000", align="right")
    put(ws, f"G{rr}", f"=D{rr}-F{rr}", num="$#,##0.00", align="right", bold=True)
    put(ws, f"H{rr}", f"=G{rr}*100", num="$#,##0", align="right", bold=True)
    put(ws, f"I{rr}", conf)
    put(ws, f"J{rr}", act, bold=True, color={"Do now": "5F7F63", "Later": DEEP, "Skip": "8A8A8A"}[act])
    put(ws, f"K{rr}", catch, color=BODY)
    put(ws, f"L{rr}", src, color=BODY)
last_lever = 6 + len(levers) - 1
dv = DataValidation(type="list", formula1='"Do now,Later,Skip"', allow_blank=False)
ws.add_data_validation(dv)
dv.add(f"J6:J{last_lever}")
put(ws, f"B{last_lever + 2}", "Where not to economise", bold=True, color=DARK, size=11, fill=SAND)
for col in "CDEFGHIJKL":
    ws[f"{col}{last_lever + 2}"].fill = PatternFill("solid", fgColor=SAND)
dont = [
    "Do not skip the tap test on every sticker. A dud costs a full re-send plus a customer who tried it.",
    "Do not put stickers with an unnamed chip maker into customer packs. NXP forum posts say iPhone TagInfo can't prove a chip is genuine, so rely on a seller that names NXP, then test.",
    "Do not skip the weigh test. If a pack is rigid or lumpy it costs $0.49 more, or $0.87 more as a flat.",
    "Do not buy a box or rigid mailer. It turns a $0.82 letter into a parcel: $7.33 or more.",
]
for i, t in enumerate(dont):
    put(ws, f"B{last_lever + 3 + i}", f"{i + 1}. {t}", wrap=False)
fit_rows(ws, 6, last_lever)
ws.freeze_panes = "C6"

# --------------------------------------------------------------------------- Pack-Out SOP
ws = ws_sop
title(ws, "Pack-out procedure (by hand)", "Time estimates are my guesses. Time one real batch and fix them.")
widths(ws, {"A": 5, "B": 46, "C": 70, "D": 10})
put(ws, "A4", "A. Batch workflow: 10 Spots at a time", bold=True, color=DARK, size=11, fill=SAND, wrap=False)
for col in "BCD":
    ws[f"{col}4"].fill = PatternFill("solid", fgColor=SAND)
header(ws, 5, ["#", "Step", "How", "Minutes"])
batch = [
    ("Generate and program 10 stickers", "Mivo app, Admin Center, Spots: choose 10, tap 'Generate 10 & start programming', hold each sticker to the phone in turn. If you stop, 'Continue programming' at the top resumes. Tap 'Generate only, export CSV' instead if you want the ID list.", 5),
    ("Tap-test every sticker", "Tap with an iPhone. 'Meet your new Mivo Spot' means it works. Leave before the last step so it stays unclaimed. Mark duds with a pen on the liner and set them aside.", 3),
    ("Put a clear cover on each sticker", "Keep the sticker on its backing sheet. Peel a clear label off its own backing and lay it sticky side down over the sticker, centred, about 6 mm of rim all round. Press out bubbles. Lift the pair off the backing together.", 5),
    ("Print and cut the cards", "Print home-print.pdf (single) or home-print-3pack.pdf: Letter, landscape, Actual size, two-sided, cardstock. Cut on the dashed lines. Three sheets make 12 cards.", 8),
    ("Press each covered sticker inside its ring", "Press firmly, centred in the ring. Three per card on a 3-pack.", 3),
    ("Pack", "Card in an A6 envelope, face up so the ring is the first thing seen. Seal.", 3),
    ("Weigh one pack from each batch", "At or under 1 oz. If it is heavier, find out why before you stamp the rest.", 1),
]
for i, (step, how, mins) in enumerate(batch):
    rr = 6 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", step, bold=True)
    put(ws, f"C{rr}", how)
    inp(ws, f"D{rr}", mins, "0", align="center")
last_b = 6 + len(batch) - 1
put(ws, f"B{last_b + 1}", "Total for 10 Spots", bold=True)
put(ws, f"D{last_b + 1}", f"=SUM(D6:D{last_b})", num="0", align="center", bold=True)
put(ws, f"B{last_b + 2}", "Per Spot", bold=True)
put(ws, f"D{last_b + 2}", f"=D{last_b + 1}/10", num="0.0", align="center", bold=True)

r0 = last_b + 4
put(ws, f"A{r0}", "B. Per order", bold=True, color=DARK, size=11, fill=SAND, wrap=False)
for col in "BCD":
    ws[f"{col}{r0}"].fill = PatternFill("solid", fgColor=SAND)
header(ws, r0 + 1, ["#", "Step", "How", "Minutes"])
per_order = [
    ("Read the Stripe order email", "Check the address is complete and in the US. Note the product: Single or 3-pack.", 1),
    ("Pull a pack", "Take the next pack. Write the batch letter or sticker IDs on the Orders tab if you want to trace it.", 1),
    ("Address and stamp", "Address by hand. One Forever stamp for up to 1 oz. Add a thank-you note only if the pack stays under 1 oz.", 2),
    ("Mail it", "Blue box or post office. Do it within 2 business days.", 1),
    ("Log it", "One row on the Orders tab.", 1),
]
for i, (step, how, mins) in enumerate(per_order):
    rr = r0 + 2 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", step, bold=True)
    put(ws, f"C{rr}", how)
    inp(ws, f"D{rr}", mins, "0", align="center")
last_o = r0 + 2 + len(per_order) - 1
put(ws, f"B{last_o + 1}", "Total per order", bold=True)
put(ws, f"D{last_o + 1}", f"=SUM(D{r0 + 2}:D{last_o})", num="0", align="center", bold=True)

r1 = last_o + 3
put(ws, f"A{r1}", "C. Quality checklist: tick before sealing", bold=True, color=DARK, size=11, fill=SAND, wrap=False)
for col in "BCD":
    ws[f"{col}{r1}"].fill = PatternFill("solid", fgColor=SAND)
qc = [
    "Sticker read in the tap test",
    "Cover is centred, no big bubbles, rim fully down",
    "Sticker sits inside the ring (3-pack: all three)",
    "Card printed both sides, right way up, no clipped edge",
    "Envelope sealed, A6, card does not rattle",
    "Weighed at or under 1 oz (spot-check one per batch)",
    "Address complete, one stamp",
    "Logged on the Orders tab",
]
for i, t in enumerate(qc):
    rr = r1 + 1 + i
    put(ws, f"A{rr}", "[ ]", align="center")
    put(ws, f"B{rr}", t)
    ws.merge_cells(f"B{rr}:C{rr}")

r2 = r1 + len(qc) + 3
put(ws, f"A{r2}", "D. When something goes wrong", bold=True, color=DARK, size=11, fill=SAND, wrap=False)
for col in "BCD":
    ws[f"{col}{r2}"].fill = PatternFill("solid", fgColor=SAND)
header(ws, r2 + 1, ["#", "Problem", "Do this", ""])
fixes = [
    ("Sticker will not read", "Re-program it once in Admin. If it still fails, bin it and log it. If more than 1 in 20 fail, stop using that source."),
    ("Sticker stays on the backing when you lift the cover", "Press harder in the middle first. If it still stays, try a different clear label."),
    ("Sticker tears the card face when peeled", "Use glossy cardstock, or press a small square of removable tape under each ring."),
    ("Backs print upside down", "Switch long-edge and short-edge in the duplex setting."),
    ("Ink clips at the edge of the sheet", "Raise your printer's margin, or print the 3-pack at 98% scale and re-test."),
    ("Post office adds a surcharge", "The pack is rigid or lumpy. Use thinner cardstock, or ship as a flat ($1.69) and charge more shipping."),
    ("Customer says it does not work", "Check in Admin whether the ID shows 'taken', 'invalid' or 'disabled'. Replace free and log it."),
]
for i, (p, f) in enumerate(fixes):
    rr = r2 + 2 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", p, bold=True)
    put(ws, f"C{rr}", f)
fit_rows(ws, 6, r2 + 2 + len(fixes), skip=(r0, r1, r2, 4))
ws.freeze_panes = "A4"

# --------------------------------------------------------------------------- Orders
ws = ws_ord
title(ws, "Order log", "One row per order. Totals update on their own. Blue cells are for you to fill in.")
widths(ws, {"A": 9, "B": 12, "C": 12, "D": 6, "E": 11, "F": 11, "G": 11, "H": 11, "I": 11, "J": 22, "K": 12, "L": 12, "M": 26, "N": 30})
labels = [("Orders", "=COUNTA(A11:A210)", "0"), ("Collected (price + shipping)", "=SUM(E11:F210)", "$#,##0.00"),
          ("Card fees", "=SUM(H11:H210)", "$#,##0.00"), ("Postage", "=SUM(I11:I210)", "$#,##0.00"),
          ("Left after fees and postage", "=B5-B6-B7", "$#,##0.00")]
for i, (lab, f, fmt) in enumerate(labels):
    put(ws, f"A{4 + i}", lab, bold=True, wrap=False)
ws.column_dimensions["A"].width = 30
for i, (lab, f, fmt) in enumerate(labels):
    put(ws, f"B{4 + i}", f, num=fmt, align="right", bold=True)
put(ws, "C8", "Materials are not in this number: see Hand-Made Unit Cost", italic=True, color=BODY, wrap=False)
header(ws, 10, ["Order #", "Date", "Product", "Qty", "Price", "Shipping", "Tax collected", "Stripe fee", "Postage", "Sticker batch or IDs", "Shipped", "Status", "Problem", "Notes"])
dv1 = DataValidation(type="list", formula1='"Single,3-pack"', allow_blank=True)
dv2 = DataValidation(type="list", formula1='"To pack,Shipped,Delivered,Problem,Refunded"', allow_blank=True)
ws.add_data_validation(dv1)
ws.add_data_validation(dv2)
dv1.add("C11:C210")
dv2.add("L11:L210")
for rr in range(11, 41):
    for col, fmt in (("B", "mmm d"), ("E", "$#,##0.00"), ("F", "$#,##0.00"), ("G", "$#,##0.00"), ("H", "$#,##0.00"), ("I", "$#,##0.00"), ("K", "mmm d")):
        inp(ws, f"{col}{rr}", None, fmt)
    for col in "ACDJLMN":
        inp(ws, f"{col}{rr}", None, align="left")
ws.freeze_panes = "A11"

# --------------------------------------------------------------------------- Upgrade Triggers
ws = ws_up
title(ws, "When to stop doing it by hand", "Switch only when a trigger fires. Costs are what I could verify; 'not researched' means get a quote first.")
widths(ws, {"A": 5, "B": 34, "C": 52, "D": 24, "E": 50, "F": 28})
header(ws, 4, ["#", "Trigger", "Upgrade", "Cost", "What you gain", "Evidence"])
ups = [
    ("About 25 Spots sold and the process runs smoothly", "Buy stickers in bulk: Tagstand roll of 500 (restock needed)", "$170 for 500", "$0.34 each instead of $0.50, about $80 saved per 500", "Tagstand page (out of stock 2026-10-23)"),
    ("About 50 Spots in customers' hands", "Have Claude add tag write-lock to Admin programming", "A coding session", "Stops anyone overwriting a sticker with an NFC app", "App code search 2026-10-23: no lock call found"),
    ("Cover edges lift or stickers peel on real desks", "Ask for factory over-laminate or a different clear label; the drafted TimesKey quote is ready", "Quote needed", "Less hand work and fewer failures", "Packaging notes in this project"),
    ("About 100 Spots a month", "Switch to printed, Mivo-branded stickers from a bulk supplier (see Landed Cost and Suppliers tabs)", "$0.30 to $0.77 landed each", "Brand on the sticker, a lower per-sticker price at volume", "Landed Cost tab"),
    ("About 100 cards at once", "Cut cards 4.0 in tall and move to #10 envelopes", "$20.99 for 500", "Envelope cost falls from about $0.19 to about $0.04", "Staples listing (snapshot)"),
    ("About 50 orders a month and you want a premium look", "Print the dark card at a print shop (files in packaging/print/)", "Not researched: get a quote", "Better finish, no hand cutting", "packaging/print/card-1up.pdf"),
    ("About 100 letters a month", "Postage meter or online postage", "Not researched", "$0.04 less per letter ($0.78 vs $0.82)", "USPS Notice 123"),
    ("About 200 orders a month", "Use a fulfilment service", "About $2 to $3 per order plus a monthly minimum near $500 (Shipping tab)", "Gets you out of the packing", "Your Shipping tab"),
    ("The US runs well", "Sell internationally", "$19 to $25 postage per parcel", "New markets, but only with higher prices", "Your Shipping tab"),
    ("Mivo Plus exists in the app", "Sell the Starter Kit (3 Spots + 1 year Plus)", "A code or in-app redeem flow", "The $49.99 bundle from your pricing plan", "mivo-pricing notes: no paywall yet"),
]
for i, (trig, up, cost, gain, ev) in enumerate(ups):
    rr = 5 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", trig, bold=True)
    put(ws, f"C{rr}", up)
    put(ws, f"D{rr}", cost)
    put(ws, f"E{rr}", gain, color=BODY)
    put(ws, f"F{rr}", ev, color=BODY)
fit_rows(ws, 5, 5 + len(ups) - 1)
ws.freeze_panes = "A5"

# --------------------------------------------------------------------------- Hand-Made Sources
ws = ws_src
title(ws, "Sources for the hand-made tabs", "Accessed 2026-10-23 unless noted. 'Read' means I opened the page; 'Snapshot' means a search result only.")
widths(ws, {"A": 5, "B": 44, "C": 80, "D": 50, "E": 12})
header(ws, 4, ["#", "Source", "Link", "Used for", "How I got it"])
srcs = [
    ("USPS Notice 123 (effective 2026-10-04)", "https://pe.usps.com/text/dmm300/Notice123.htm", "Letter $0.82 stamped, $0.78 metered at 1 oz; flat $1.69", "Read"),
    ("Stripe pricing", "https://stripe.com/pricing", "2.9% + 30 cents, no monthly fee, Payment Links free, custom domain $10 a month", "Read"),
    ("Texas Comptroller: sales tax permit", "https://comptroller.texas.gov/taxes/permit", "Free permit, 2 to 3 weeks, SSN needed", "Snapshot"),
    ("Frisco TX sales tax rate", "https://www.salestaxhandbook.com/texas/rates/frisco", "8.25% combined", "Snapshot"),
    ("Tagstand 25-sticker sample", "https://www.tagstand.com/products/25-sample-stickers-the-25-25-25-roll-of-ntag213-stickers-25mm-circle-25-cents-each", "$12.50, genuine NXP NTAG213, 3M 467MP adhesive", "Read"),
    ("Tagstand 500-count roll", "https://www.tagstand.com/products/500-count-ntag213-25-25-25-stickers-25mm-round/", "$170 per 500 (out of stock)", "Snapshot"),
    ("Amazon TimesKey NFC stickers", "https://www.amazon.com/dp/B09NXXTXHL", "$7.99 for 10, specs, review summary", "Read in your browser 2026-10-22"),
    ("LabelValue 1.5 in clear round labels", "https://www.labelvalue.com/15-round-labels-clear-p-929.html", "$9.60 per 500, bulk breaks, free US shipping", "Read"),
    ("Staples 65 lb cardstock, 250 sheets", "https://www.staples.com/staples-65-lb-cardstock-paper-8-5-x-11-bright-blue-250-sheets-pack-92099/product_24695615", "$28.99 per 250", "Snapshot"),
    ("Staples JAM A6 white envelopes, 100-pack", "https://www.staples.com/jam-paper-a6-booklet-envelope-4-3-4-x-6-1-2-white-100-pack-j0567d/product_24604576", "$18.99 per 100", "Snapshot"),
    ("Staples #10 white envelopes, 500", "https://www.staples.com/Staples-Gummed-10-Envelope-4-1-8-x-9-1-2-White-500-Box-187013NB/product_187013", "$20.99 per 500 (page blocked my check)", "Snapshot"),
    ("Walmart NFC tags category", "https://www.walmart.com/c/kp/nfc-tags", "Generic 100 stickers at about $9.20", "Snapshot"),
    ("Seritag 25 mm NTAG213", "https://seritag.com/nfc-tags/25mm-white-ntag213", "0.23 GBP each; out of stock", "Read"),
    ("GoToTags 25 mm NTAG213", "https://store.gototags.com/nfc-sticker-ntag213-25-mm-circle/", "$0.32 at 10; page says no longer offered", "Read"),
    ("Printer ink cost per page (HP)", "https://www.hp.com/us-en/tech-takes/printers/explainer/cost-per-page-for-ink-tank-printers.html", "Ink-tank cost per page", "Snapshot"),
    ("Printer ink cost per page (Castle Ink)", "https://castleink.com/pages/best-home-small-office-printers-in-2026-top-5-picks-buyers-guide", "Cartridge cost per colour page (a seller: treat as rough)", "Snapshot"),
    ("Shopify vs Etsy fees (NerdWallet)", "https://www.nerdwallet.com/business/software/learn/shopify-vs-etsy", "Etsy and Shopify fees", "Snapshot"),
    ("Shopify vs Etsy fees (Trueprofit)", "https://trueprofit.io/blog/shopify-vs-etsy-fees", "Etsy and Shopify fees (sources disagree on Shopify Starter)", "Snapshot"),
    ("NXP forum: iOS originality check", "https://community.nxp.com/t5/NFC/iOS-IPhone-originality-signature-check/m-p/1322579", "iPhone TagInfo does not reliably verify originality", "Snapshot"),
    ("Mivo Spots README (this project)", "Mivo/Spots/README.md", "How Admin generates and programs Spots; claim flow", "Read"),
]
for i, (name, link, used, how) in enumerate(srcs):
    rr = 5 + i
    put(ws, f"A{rr}", i + 1, align="center")
    put(ws, f"B{rr}", name)
    put(ws, f"C{rr}", link, link=link if link.startswith("http") else None)
    put(ws, f"D{rr}", used, color=BODY)
    put(ws, f"E{rr}", how)
fit_rows(ws, 5, 5 + len(srcs) - 1)
ws.freeze_panes = "A5"

wb._sheets = [ws_start, ws_plan, ws_shop, ws_sop, ws_ord, ws_cost, ws_save, ws_up, ws_src]  # same order as the live Sheet
wb.save(OUT)
print("saved", OUT)
