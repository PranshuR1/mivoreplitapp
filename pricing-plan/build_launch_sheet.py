"""Builds Mivo-Spots-Launch-Plan.xlsx: the simplified replacement for the Pricing Model v2 Sheet.

Rules baked in:
- The three "cost to make" cells on Inputs hold the text LOGAN INFO until Logan Bishop sends numbers.
- Every formula that touches them goes through N(), which turns text into 0, so no sum ever errors.
  Status cells say plainly when a result is still "before Logan's cost".
- Every price outside Mivo's own decisions was read on a real page on 2026-10-26 (see Sources).
"""
from datetime import date
from openpyxl import Workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.properties import PageSetupProperties

OUT = "/Users/pranshuraithatha/mivoreplitapp/pricing-plan/Mivo-Spots-Launch-Plan.xlsx"
LOGAN = "LOGAN INFO"

DARK, TAN, PAPER = "2B1D0E", "F3E6D0", "FFFFFF"
INPUT_FILL, LOGAN_FILL = "FFF7D1", "FFC25C"
GRAY, BLUE, GREEN, RED, LINK = "6B6258", "0B3D91", "1E7B3A", "B3261E", "1155CC"
FONT = "Arial"

thin = Side(style="thin", color="E2D8C6")
BOX = Border(left=thin, right=thin, top=thin, bottom=thin)
USD, USD0, PCT, DATE = '"$"#,##0.00', '"$"#,##0', "0.0%", "mmm d, yyyy"


def f(bold=False, color="000000", size=10, italic=False):
    return Font(name=FONT, bold=bold, color=color, size=size, italic=italic)


def fill(c):
    return PatternFill("solid", start_color=c, end_color=c)


wb = Workbook()


def sheet(title, widths, first=False):
    ws = wb.active if first else wb.create_sheet()
    ws.title = title
    ws.sheet_view.showGridLines = False
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    return ws


def title(ws, text, sub, span):
    ws["A1"] = text
    ws["A1"].font = f(True, DARK, 18)
    ws.row_dimensions[1].height = 30
    ws["A2"] = sub
    ws["A2"].font = f(False, GRAY, 10, True)
    ws["A2"].alignment = Alignment(wrap_text=True, vertical="top")
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=span)
    ws.row_dimensions[2].height = 30


def section(ws, row, text, span):
    for c in range(1, span + 1):
        ws.cell(row, c).fill = fill(TAN)
    ws.cell(row, 1, text).font = f(True, DARK, 11)
    ws.row_dimensions[row].height = 22
    ws.cell(row, 1).alignment = Alignment(vertical="center")


def header(ws, row, labels):
    for i, t in enumerate(labels, 1):
        c = ws.cell(row, i, t)
        c.font = f(True, "FFFFFF")
        c.fill = fill(DARK)
        c.alignment = Alignment(vertical="center", wrap_text=True, horizontal="left" if i == 1 else "center" if i == 2 else "left")
    ws.row_dimensions[row].height = 22


def put(ws, addr, value, fmt=None, font=None, wrap=False, align=None, fill_c=None, border=True):
    c = ws[addr]
    c.value = value
    c.font = font or f()
    if fmt:
        c.number_format = fmt
    c.alignment = Alignment(wrap_text=wrap, vertical="center", horizontal=align)
    if fill_c:
        c.fill = fill(fill_c)
    if border:
        c.border = BOX
    return c


def link(ws, addr, url, text=None):
    c = ws[addr]
    c.value = f'=HYPERLINK("{url}","{text or url}")'
    c.font = Font(name=FONT, size=10, color=LINK, underline="single")
    c.alignment = Alignment(wrap_text=True, vertical="center")
    c.border = BOX


def status_rules(ws, rng):
    first = rng.split(":")[0]
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'ISNUMBER(SEARCH("WAITING",{first}))'], font=Font(name=FONT, bold=True, color="9A5B00"), fill=fill("FFE9C2")))
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'ISNUMBER(SEARCH("BEFORE LOGAN",{first}))'], font=Font(name=FONT, bold=True, color="9A5B00"), fill=fill("FFE9C2")))
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'ISNUMBER(SEARCH("NOT DONE",{first}))'], font=Font(name=FONT, bold=True, color=RED), fill=fill("FBD9D5")))
    ws.conditional_formatting.add(rng, FormulaRule(formula=[f'OR(ISNUMBER(SEARCH("FINAL",{first})),ISNUMBER(SEARCH("ALL IN",{first})),ISNUMBER(SEARCH("ENTERED",{first})),{first}="Done")'], font=Font(name=FONT, bold=True, color=GREEN), fill=fill("DDF1E3")))


# ---------------------------------------------------------------- sheets (order = tab order)
ws_start = sheet("START HERE", [58, 22, 24, 70], first=True)
ws_in = sheet("Inputs", [54, 16, 16, 74, 30])
ws_pr = sheet("Profit", [44, 16, 16, 78])
ws_fc = sheet("Forecast", [34] + [12] * 12 + [15])
ws_sup = sheet("Supplies", [8, 40, 18, 12, 10, 12, 46, 12, 58])
ws_ck = sheet("Launch Checklist", [14, 62, 10, 14, 16, 78])
ws_cp = sheet("Competitors", [24, 34, 22, 46, 12, 52])
ws_src = sheet("Sources", [6, 46, 70, 70, 12])

# ================================================================ INPUTS
ws = ws_in
title(ws, "Inputs: every number you can change lives here",
      "Yellow cells are yours to type in. Orange LOGAN INFO cells are waiting on Logan Bishop: type his number over the text and every other tab updates by itself.", 5)
R = {}  # key -> absolute reference on Inputs


def inp(row, key, label, value, fmt, unit, note, status, kind="input"):
    put(ws, f"A{row}", label, wrap=True)
    c = put(ws, f"B{row}", value, fmt, f(True, BLUE), align="center", fill_c=INPUT_FILL)
    put(ws, f"C{row}", unit, font=f(color=GRAY), align="center")
    put(ws, f"D{row}", note, font=f(color=GRAY), wrap=True)
    put(ws, f"E{row}", status, font=f(color=GRAY), align="center")
    R[key] = f"Inputs!$B${row}"
    ws.row_dimensions[row].height = 30


section(ws, 4, "A.  What it costs to make a Spot   (from Logan Bishop)", 5)
header(ws, 5, ["Item", "Value", "Unit", "What to ask Logan", "Status"])
inp(6, "c_sticker", "NFC sticker, per Spot", LOGAN, USD, "$ per sticker", "Price of one NTAG213 sticker, delivered to you. Ask for the price at your first order size.", '=IF(ISNUMBER(B6),"ENTERED","WAITING ON LOGAN")')
inp(7, "c_pack", "Card, cover label and envelope, per order", LOGAN, USD, "$ per order", "Everything that goes in the envelope except the sticker. One card and one envelope ship per order, whether it holds 1 or 3 stickers.", '=IF(ISNUMBER(B7),"ENTERED","WAITING ON LOGAN")')
inp(8, "c_labor", "Assembly and packing, per order", LOGAN, USD, "$ per order", "Logan's charge (or your own time) to stick, cover, pack and label one order. Enter 0 if it is free.", '=IF(ISNUMBER(B8),"ENTERED","WAITING ON LOGAN")')
for r in (6, 7, 8):
    ws[f"B{r}"].fill = fill(LOGAN_FILL)
    ws[f"B{r}"].font = f(True, DARK)
ws.conditional_formatting.add("B6:B8", FormulaRule(formula=["ISNUMBER(B6)"], font=Font(name=FONT, bold=True, color=BLUE), fill=fill(INPUT_FILL)))
status_rules(ws, "E6:E8")
# calculated rows
put(ws, "A9", "Make cost of one Single Spot order  (calculated)", font=f(True))
put(ws, "B9", "=N(B6)+N(B7)+N(B8)", USD, f(True), align="center")
put(ws, "C9", "$ per order", font=f(color=GRAY), align="center")
put(ws, "D9", "Sticker + card/cover/envelope + assembly. Text such as LOGAN INFO counts as $0 until a number replaces it.", font=f(color=GRAY), wrap=True)
put(ws, "E9", '=IF(COUNT(B6:B8)=3,"FINAL","BEFORE LOGAN: "&COUNT(B6:B8)&" of 3 in")', font=f(color=GRAY), align="center")
R["make_single"] = "Inputs!$B$9"
put(ws, "A10", "Make cost of one 3-pack order  (calculated)", font=f(True))
put(ws, "B10", "=3*N(B6)+N(B7)+N(B8)", USD, f(True), align="center")
put(ws, "C10", "$ per order", font=f(color=GRAY), align="center")
put(ws, "D10", "Three stickers, but still one card, one envelope and one pack-out.", font=f(color=GRAY), wrap=True)
put(ws, "E10", '=IF(COUNT(B6:B8)=3,"FINAL","BEFORE LOGAN: "&COUNT(B6:B8)&" of 3 in")', font=f(color=GRAY), align="center")
R["make_pack"] = "Inputs!$B$10"
R["logan_in"] = "Inputs!$B$11"
put(ws, "A11", "Logan numbers received", font=f(True))
put(ws, "B11", '=COUNT(B6:B8)&" of 3"', font=f(True), align="center")
put(ws, "C11", "", border=True)
put(ws, "D11", "Goes to 3 of 3 when all three orange cells hold numbers.", font=f(color=GRAY))
put(ws, "E11", '=IF(COUNT(B6:B8)=3,"ALL IN","WAITING ON LOGAN")', font=f(True), align="center")
status_rules(ws, "E9:E11")
for r in (9, 10, 11):
    ws.row_dimensions[r].height = 30

section(ws, 13, "B.  What you charge customers", 5)
header(ws, 14, ["Item", "Value", "Unit", "Where it comes from", "Status"])
inp(15, "p_single", "Single Spot price", 14.99, USD, "$", "Your earlier plan (Pricing Model v2). Brick, the closest hardware rival, is $59 on getbrick.com.", "Your decision")
inp(16, "s_single", "Shipping charged on a Single", 2.99, USD, "$", "Singles lose most of their profit to postage, so a small charge is added.", "Your decision")
inp(17, "p_pack", "3-pack price", 34.99, USD, "$", "Your earlier plan. Desk, bedside, car.", "Your decision")
inp(18, "s_pack", "Shipping charged on a 3-pack", 0, USD, "$", "Free shipping on the 3-pack.", "Your decision")
inp(19, "target", "Profit you want to keep per order", 5, USD, "$", "Used only to work out the most you can pay Logan. My default, change it.", "Estimate")
inp(20, "launch", "Launch date", date(2026, 11, 1), DATE, "date", "Selling starts here.", "Your decision")

section(ws, 22, "C.  Costs that are real   (read on a live page 2026-10-26, see Sources)", 5)
header(ws, 23, ["Item", "Value", "Unit", "Where it comes from", "Status"])
inp(24, "stripe_pct", "Stripe card fee, percent", 0.029, PCT, "% of charge", "stripe.com/pricing: 2.9% + 30 cents per successful US card payment. Payment Links and Checkout add nothing. No monthly fee.", "Real")
inp(25, "stripe_fix", "Stripe card fee, fixed", 0.30, USD, "$ per charge", "Same page.", "Real")
inp(26, "postage", "Postage per order: letter, 1 oz, stamped", 0.82, USD, "$ per order", "USPS Notice 123, effective 2026-10-04: First-Class letter, 1 oz, stamped $0.82 (metered $0.78, 2 oz $1.11, large envelope $1.69).", "Real")
inp(27, "surcharge", "Non-machinable surcharge", 0.49, USD, "$ per order", "Same Notice 123: letters with non-machinable traits (rigid, lumpy) pay $0.49 extra.", "Real")
inp(28, "use_surcharge", "Add the surcharge to postage?", "Yes", None, "Yes or No", "Yes until the post office weighs and accepts a packed test envelope. Then set No if they take it at $0.82.", "Your decision")
dv = DataValidation(type="list", formula1='"Yes,No"', allow_blank=False)
ws.add_data_validation(dv)
dv.add("B28")
inp(29, "returns", "Returns and re-sends allowance", 0.03, PCT, "% of price", "My estimate for refunds, lost letters and stickers that do not scan. Replace after your first 50 orders.", "Estimate")
inp(30, "tax", "Sales tax rate you collect in Georgia", 0.07, PCT, "% of order", "Forsyth County base is 7% (4% state + 3% county) per Avalara; some places inside the county add more (Cumming is listed at 8%). Tax is collected from the buyer and passed on, so it is not profit.", "Real, check address")

section(ws, 32, "D.  Mivo Plus (the subscription inside the app)", 5)
header(ws, 33, ["Item", "Value", "Unit", "Where it comes from", "Status"])
inp(34, "plus_m", "Plus monthly price", 6.99, USD, "$ per month", "Your decision on 2026-10-25. Clearspace charges $6.99 a month (App Store listing).", "Your decision")
inp(35, "plus_y", "Plus annual price (7-day trial)", 39.99, USD, "$ per year", "Your decision on 2026-10-25. Clearspace $44.99, Opal $99.99.", "Your decision")
inp(36, "plus_l", "Plus lifetime price", 79.99, USD, "$ one time", "Your decision on 2026-10-25. Opal lifetime is $399.", "Your decision")
inp(37, "apple", "Apple's cut", 0.15, PCT, "% of price", "Apple Small Business Program: 15% while proceeds stay under $1 million a year. You must be enrolled in App Store Connect.", "Real")
inp(38, "mix_y", "Share of payers who pick annual", 0.65, PCT, "% of payers", "Guess until you have data.", "Estimate")
inp(39, "mix_m", "Share of payers who pick monthly", 0.30, PCT, "% of payers", "Guess until you have data.", "Estimate")
inp(40, "mix_l", "Share of payers who pick lifetime", 0.05, PCT, "% of payers", "Guess until you have data.", "Estimate")
put(ws, "A41", "Check: the three shares add up to 100%")
put(ws, "B41", '=IF(ABS(B38+B39+B40-1)<0.0001,"OK","FIX THE SHARES")', font=f(True), align="center")
put(ws, "C41", "")
put(ws, "D41", "Shows FIX THE SHARES if they do not total 100%.", font=f(color=GRAY))
put(ws, "E41", "")
inp(42, "churn", "Monthly payers who cancel each month", 0.08, PCT, "% per month", "Guess. Only applies to monthly payers in this model.", "Estimate")
inp(43, "installs", "New app installs in month 1", 2000, "#,##0", "installs", "Guess. Replace with App Store Connect numbers.", "Estimate")
inp(44, "inst_g", "Install growth per month", 0.05, PCT, "% per month", "Guess.", "Estimate")
inp(45, "conv", "Installs that become payers", 0.021, PCT, "% of installs", "Guess (2.1% was the freemium median in earlier research; not rechecked today).", "Estimate")

section(ws, 47, "E.  Spot sales guesses", 5)
header(ws, 48, ["Item", "Value", "Unit", "Where it comes from", "Status"])
inp(49, "o_single", "Single orders in month 1", 15, "#,##0", "orders", "Guess. Replace after the first week.", "Estimate")
inp(50, "o_pack", "3-pack orders in month 1", 10, "#,##0", "orders", "Guess.", "Estimate")
inp(51, "o_g", "Order growth per month", 0.05, PCT, "% per month", "Guess.", "Estimate")
ws.freeze_panes = "A4"

# ================================================================ PROFIT
ws = ws_pr
title(ws, "Profit: what one order earns you",
      "Everything here calculates from Inputs. While Logan's numbers are missing the profit is shown BEFORE his cost, so it is too high; the Status row says which case you are in.", 4)
header(ws, 4, ["Line", "Single Spot", "3-pack", "How it is calculated"])
rows = [
    (5, "Price", f"={R['p_single']}", f"={R['p_pack']}", USD, "From Inputs", False),
    (6, "Shipping you charge", f"={R['s_single']}", f"={R['s_pack']}", USD, "From Inputs", False),
    (7, "You receive (before tax)", "=B5+B6", "=C5+C6", USD, "Price + shipping charged", True),
    (8, "Sales tax collected (passed on to Georgia)", f"=B7*{R['tax']}", f"=C7*{R['tax']}", USD, "Order total x tax rate. Not your money.", False),
    (9, "Customer pays at checkout", "=B7+B8", "=C7+C8", USD, "What appears on the customer's card", True),
]
for r, lab, b, c, fmt, note, bold in rows:
    put(ws, f"A{r}", lab, font=f(bold))
    put(ws, f"B{r}", b, fmt, f(bold), align="center")
    put(ws, f"C{r}", c, fmt, f(bold), align="center")
    put(ws, f"D{r}", note, font=f(color=GRAY), wrap=True)
section(ws, 10, "What it costs you", 4)
cost_rows = [
    (11, "Stripe card fee", f"=B9*{R['stripe_pct']}+{R['stripe_fix']}", f"=C9*{R['stripe_pct']}+{R['stripe_fix']}", "2.9% + $0.30 of the full amount charged (Stripe also takes its cut of the tax)"),
    (12, "Postage", f'={R["postage"]}+IF({R["use_surcharge"]}="Yes",{R["surcharge"]},0)', f'={R["postage"]}+IF({R["use_surcharge"]}="Yes",{R["surcharge"]},0)', "Stamped 1 oz letter, plus the surcharge if Inputs says Yes"),
    (13, "Returns and re-sends allowance", f"=B5*{R['returns']}", f"=C5*{R['returns']}", "Price x allowance %"),
    (14, "Cost to make (from Logan)", f"={R['make_single']}", f"={R['make_pack']}", "From Inputs. Counts as $0 while it says LOGAN INFO."),
]
for r, lab, b, c, note in cost_rows:
    put(ws, f"A{r}", lab)
    put(ws, f"B{r}", b, USD, align="center")
    put(ws, f"C{r}", c, USD, align="center")
    put(ws, f"D{r}", note, font=f(color=GRAY), wrap=True)
put(ws, "A15", "Total costs", font=f(True))
put(ws, "B15", "=SUM(B11:B14)", USD, f(True), align="center")
put(ws, "C15", "=SUM(C11:C14)", USD, f(True), align="center")
put(ws, "D15", "Rows above added up", font=f(color=GRAY))
for col in "ABCD":
    ws[f"{col}16"].fill = fill("EAF4EC")
put(ws, "A16", "PROFIT per order", font=f(True, GREEN, 12), fill_c="EAF4EC")
put(ws, "B16", "=B7-B15", USD, f(True, GREEN, 12), align="center", fill_c="EAF4EC")
put(ws, "C16", "=C7-C15", USD, f(True, GREEN, 12), align="center", fill_c="EAF4EC")
put(ws, "D16", "What you receive minus total costs. Before your own time and before income tax.", font=f(color=GRAY), wrap=True, fill_c="EAF4EC")
put(ws, "A17", "Margin")
put(ws, "B17", "=IF(B7=0,0,B16/B7)", PCT, align="center")
put(ws, "C17", "=IF(C7=0,0,C16/C7)", PCT, align="center")
put(ws, "D17", "Profit / what you receive", font=f(color=GRAY))
put(ws, "A18", "Profit per Spot")
put(ws, "B18", "=B16/1", USD, align="center")
put(ws, "C18", "=C16/3", USD, align="center")
put(ws, "D18", "Profit / number of Spots in the order", font=f(color=GRAY))
put(ws, "A19", "Status", font=f(True))
stat = '=IF(COUNT(Inputs!$B$6:$B$8)=3,"FINAL: includes Logan\'s costs","BEFORE LOGAN\'S COST: "&COUNT(Inputs!$B$6:$B$8)&" of 3 numbers in, so profit is too high")'
put(ws, "B19", stat, font=f(True), wrap=True, align="center")
put(ws, "C19", stat, font=f(True), wrap=True, align="center")
put(ws, "D19", "Turns green and says FINAL when all three orange cells on Inputs hold numbers.", font=f(color=GRAY), wrap=True)
ws.row_dimensions[19].height = 44
status_rules(ws, "B19:C19")
section(ws, 21, "Use this when you talk to Logan", 4)
put(ws, "A22", "Profit before the make cost")
put(ws, "B22", "=B7-SUM(B11:B13)", USD, align="center")
put(ws, "C22", "=C7-SUM(C11:C13)", USD, align="center")
put(ws, "D22", "Everything you keep before paying to make the Spots", font=f(color=GRAY))
put(ws, "A23", "Profit you want to keep")
put(ws, "B23", f"={R['target']}", USD, align="center")
put(ws, "C23", f"={R['target']}", USD, align="center")
put(ws, "D23", "From Inputs", font=f(color=GRAY))
put(ws, "A24", "Most Logan can charge per order", font=f(True))
put(ws, "B24", "=MAX(0,B22-B23)", USD, f(True), align="center")
put(ws, "C24", "=MAX(0,C22-C23)", USD, f(True), align="center")
put(ws, "D24", "Sticker + card/cover/envelope + assembly together. Above this you earn less than your target.", font=f(color=GRAY), wrap=True)
put(ws, "A25", "Orders to sell to earn back $100 of supplies")
put(ws, "B25", '=IF(B16>0,ROUNDUP(100/B16,0),"n/a")', "0", align="center")
put(ws, "C25", '=IF(C16>0,ROUNDUP(100/C16,0),"n/a")', "0", align="center")
put(ws, "D25", "$100 / profit per order. A feel for how fast a small first buy pays back.", font=f(color=GRAY), wrap=True)
for r in range(5, 26):
    if ws.row_dimensions[r].height is None:
        ws.row_dimensions[r].height = 22
ws.freeze_panes = "B5"

# ================================================================ FORECAST
ws = ws_fc
title(ws, "Forecast: the next 12 months",
      "Spots and Mivo Plus together. Orders and installs are guesses from Inputs: replace them with real numbers after week one. Annual plans renew after month 12, so they pay once here.", 14)
header(ws, 4, ["Month"] + [""] * 12 + ["12 months"])
for i in range(12):
    col = get_column_letter(2 + i)
    c = ws[f"{col}4"]
    c.value = f"=EDATE({R['launch']},{i})"
    c.number_format = "mmm yy"
    c.font = f(True, "FFFFFF")
    c.fill = fill(DARK)
    c.alignment = Alignment(horizontal="center", vertical="center")


def line(row, label, fn, fmt, bold=False, total=True, fill_c=None):
    put(ws, f"A{row}", label, font=f(bold), fill_c=fill_c)
    for i in range(12):
        col = get_column_letter(2 + i)
        put(ws, f"{col}{row}", fn(i, col), fmt, f(bold), align="center", fill_c=fill_c)
    put(ws, f"N{row}", f"=SUM(B{row}:M{row})" if total else "", fmt, f(True), align="center", fill_c=fill_c)


section(ws, 5, "Spots", 14)
line(6, "Single orders", lambda i, c: f"=ROUND({R['o_single']}*(1+{R['o_g']})^{i},0)", "#,##0")
line(7, "3-pack orders", lambda i, c: f"=ROUND({R['o_pack']}*(1+{R['o_g']})^{i},0)", "#,##0")
line(8, "Spot revenue (before tax)", lambda i, c: f"={c}6*Profit!$B$7+{c}7*Profit!$C$7", USD0)
line(9, "Stripe fees", lambda i, c: f"={c}6*Profit!$B$11+{c}7*Profit!$C$11", USD0)
line(10, "Postage", lambda i, c: f"={c}6*Profit!$B$12+{c}7*Profit!$C$12", USD0)
line(11, "Returns and re-sends", lambda i, c: f"={c}6*Profit!$B$13+{c}7*Profit!$C$13", USD0)
line(12, "Cost to make (Logan)", lambda i, c: f"={c}6*Profit!$B$14+{c}7*Profit!$C$14", USD0)
line(13, "SPOT PROFIT", lambda i, c: f"={c}8-SUM({c}9:{c}12)", USD0, True, True, "EAF4EC")
section(ws, 15, "Mivo Plus", 14)
line(16, "New installs", lambda i, c: f"=ROUND({R['installs']}*(1+{R['inst_g']})^{i},0)", "#,##0")
line(17, "New payers", lambda i, c: f"={c}16*{R['conv']}", "#,##0.0")


def active(i, c):
    if i == 0:
        return f"={c}17*{R['mix_m']}"
    prev = get_column_letter(1 + i)
    return f"={prev}18*(1-{R['churn']})+{c}17*{R['mix_m']}"


line(18, "Monthly payers still active", active, "#,##0.0", total=False)
line(19, "Plus cash received", lambda i, c: f"={c}17*{R['mix_y']}*{R['plus_y']}+{c}17*{R['mix_l']}*{R['plus_l']}+{c}18*{R['plus_m']}", USD0)
line(20, "Apple's cut", lambda i, c: f"={c}19*{R['apple']}", USD0)
line(21, "PLUS NET", lambda i, c: f"={c}19-{c}20", USD0, True, True, "EAF4EC")
section(ws, 23, "Together", 14)
line(24, "TOTAL PROFIT", lambda i, c: f"={c}13+{c}21", USD0, True, True, "EAF4EC")
line(25, "Running total", lambda i, c: f"=SUM($B24:{c}24)", USD0, False, False)
put(ws, "A26", "Status", font=f(True))
ws["B26"] = '=IF(COUNT(Inputs!$B$6:$B$8)=3,"FINAL: includes Logan\'s costs","BEFORE LOGAN\'S COST: Spot profit is too high until the 3 orange cells on Inputs hold numbers")'
ws["B26"].font = f(True)
ws.merge_cells("B26:N26")
status_rules(ws, "B26:N26")
ws.freeze_panes = "B5"

# ================================================================ SUPPLIES
ws = ws_sup
title(ws, "Supplies: real products, real prices, real links",
      "Every row was opened on a live page on 2026-10-26. This tab is a reference: nothing here feeds the Profit tab, because cost to make comes from Logan.", 9)
header(ws, 4, ["#", "Item", "Seller", "Price", "Pack", "Each", "Link", "Checked", "What I saw"])
sup = [
    ("NFC stickers: TimesKey NTAG213, 25 mm, white", "Amazon (TimesKey-US)", 7.99, 10, "https://www.amazon.com/dp/B09NXXTXHL",
     "In stock, free delivery Wed Oct 28. 4.4 stars from 496 ratings; 9% are 1-star and a few reviews say weak signal or a non-NXP chip, so test all 10 before selling. 144 bytes, PET, 0.2 mm thick. Not for metal."),
    ("NFC stickers: Tagstand 25-sticker sample, NTAG213, 25 mm", "Tagstand", 12.50, 25, "https://www.tagstand.com/products/25-sample-stickers-the-25-25-25-roll-of-ntag213-stickers-25mm-circle-25-cents-each",
     "'3 in stock'. Page says NXP chip and 3M 467MP adhesive. Shipping cost not shown on the product page."),
    ("Clear cover labels, 1.5 in round, permanent adhesive (LV-WS1.5)", "LabelValue", 9.60, 500, "https://www.labelvalue.com/15-round-labels-clear-p-929.html",
     "In stock. Free US shipping on in-stock orders. 2+ rolls $8.10, 6+ $7.53, 12+ $6.95, 50+ $5.77 per roll."),
    ("Cardstock, 65 lb, 8.5 x 11, 96 bright white", "Amazon Basics (Amazon)", 10.63, 250, "https://www.amazon.com/dp/B0DSH5V1TT",
     "Price on the product page. Four 5.5 x 4.25 in cards fit on one sheet."),
    ("Cardstock, Hammermill Premium Color Copy 80 lb, 8.5 x 11, white", "Hammermill (Amazon)", 16.57, 250, "https://www.amazon.com/dp/B000J0C47S",
     "Heavier option. Price on the product page."),
    ("Envelopes: JAM Paper A6 booklet, 4 3/4 x 6 1/2 in, white (J0567D)", "Staples", 18.99, 100, "https://www.staples.com/jam-paper-a6-booklet-envelope-4-3-4-x-6-1-2-white-100-pack-j0567d/product_24604576",
     "Price on the product page. A6 fits a 5.5 x 4.25 in card."),
]
r = 5
for i, (item, seller, price, pack, url, seen) in enumerate(sup, 1):
    put(ws, f"A{r}", i, align="center")
    put(ws, f"B{r}", item, wrap=True)
    put(ws, f"C{r}", seller, wrap=True)
    put(ws, f"D{r}", price, USD, align="center")
    put(ws, f"E{r}", pack, "#,##0", align="center")
    put(ws, f"F{r}", f"=D{r}/E{r}", '"$"#,##0.000', align="center")
    link(ws, f"G{r}", url, "Open listing")
    put(ws, f"H{r}", date(2026, 10, 26), "mmm d", align="center")
    put(ws, f"I{r}", seen, font=f(color=GRAY), wrap=True)
    ws.row_dimensions[r].height = 62
    r += 1
section(ws, r + 1, "Postage (USPS Notice 123, effective 2026-10-04)", 9)
r += 2
header(ws, r, ["#", "Service", "Weight", "Price", "", "", "Link", "Checked", "Note"])
post = [
    ("First-Class letter, stamped", "1 oz", 0.82, "Default for a card in an envelope. Metered is $0.78."),
    ("First-Class letter, stamped", "2 oz", 1.11, "Use if a packed 3-pack weighs more than 1 oz."),
    ("Non-machinable surcharge", "per letter", 0.49, "Added when a letter is rigid or lumpy. Ask the post office about a card with stickers."),
    ("First-Class large envelope (flat), stamped", "1 oz", 1.69, "Fallback if the post office will not take the card as a letter."),
    ("Ground Advantage, retail, zones 1-2", "up to 4 oz", 8.40, "Tracked parcel. Too expensive for a $14.99 product."),
]
r += 1
for i, (svc, wt, price, note) in enumerate(post, 1):
    put(ws, f"A{r}", i, align="center")
    put(ws, f"B{r}", svc, wrap=True)
    put(ws, f"C{r}", wt, align="center")
    put(ws, f"D{r}", price, USD, align="center")
    put(ws, f"E{r}", "")
    put(ws, f"F{r}", "")
    link(ws, f"G{r}", "https://pe.usps.com/text/dmm300/Notice123.htm", "USPS Notice 123")
    put(ws, f"H{r}", date(2026, 10, 26), "mmm d", align="center")
    put(ws, f"I{r}", note, font=f(color=GRAY), wrap=True)
    ws.row_dimensions[r].height = 32
    r += 1
section(ws, r + 1, "Fees and registrations", 9)
r += 2
header(ws, r, ["#", "What", "Who", "Cost", "", "", "Link", "Checked", "What I saw"])
fees = [
    ("Stripe card processing, US cards", "Stripe", "2.9% + $0.30", "https://stripe.com/pricing", "No setup or monthly fee. Payment Links and Checkout cost nothing extra. Stripe Tax is 0.5% per transaction where you are registered. Disputes cost $15."),
    ("Georgia sales and use tax account", "Georgia Dept. of Revenue", "No fee mentioned", "https://dor.georgia.gov/node/57496", "Register on the Georgia Tax Center (gtc.dor.ga.gov): Register a New Georgia Business, then Sales & Use Tax. Sole proprietors skip the officer step. Do it before the first taxable sale."),
    ("Forsyth County occupational tax certificate", "Forsyth County Business License", "$87.50 (1 owner)", "https://www.forsythco.com/DepartmentsOffices/BusinessLicenses/Applications", "Fee from the county's own 3.30.2026 application PDF, read 2026-10-23. The county site blocked my fetch today, so confirm on (678) 455-9888 or the page."),
    ("Apple Small Business Program", "Apple", "15% commission", "https://developer.apple.com/app-store/small-business-program/", "For developers under $1 million in proceeds. Enroll in App Store Connect."),
]
r += 1
for i, (what, who, cost, url, seen) in enumerate(fees, 1):
    put(ws, f"A{r}", i, align="center")
    put(ws, f"B{r}", what, wrap=True)
    put(ws, f"C{r}", who, wrap=True)
    put(ws, f"D{r}", cost, align="center", wrap=True)
    put(ws, f"E{r}", "")
    put(ws, f"F{r}", "")
    link(ws, f"G{r}", url, "Open page")
    put(ws, f"H{r}", date(2026, 10, 26) if i != 3 else date(2026, 10, 23), "mmm d", align="center")
    put(ws, f"I{r}", seen, font=f(color=GRAY), wrap=True)
    ws.row_dimensions[r].height = 62
    r += 1
ws.freeze_panes = "A5"

# ================================================================ LAUNCH CHECKLIST
ws = ws_ck
title(ws, "Launch checklist: now to Nov 1",
      "Change the Status dropdown as you go. Rows marked Yes under Needed for Nov 1 must be Done before you sell.", 6)
header(ws, 4, ["Date", "Task", "Who", "Status", "Needed for Nov 1?", "Details and links"])
tasks = [
    (date(2026, 10, 26), "Ask Logan for the 3 cost numbers on Inputs (sticker each, card + cover + envelope per order, assembly per order)", "You", "Not started", "Yes", "Profit stays 'before Logan's cost' until all three orange cells hold numbers."),
    (date(2026, 10, 26), "Type Logan's numbers into the orange cells on Inputs", "You", "Not started", "Yes", "Everything else in this workbook recalculates by itself."),
    (date(2026, 10, 26), "Stripe: create a Stripe account for Mivo, then finish activation (business details, identity, bank account for payouts)", "You", "Done", "Yes", "Mivo Scrolling (acct_1UUt2ERZs3vYxTPL) is live. Website usemivo.app, descriptor MIVO APP. Category still says Other educational services: update it in Stripe settings."),
    (date(2026, 10, 27), "Register a Georgia sales and use tax account on the Georgia Tax Center", "You", "Not started", "Yes", "https://gtc.dor.ga.gov. Guide: https://dor.georgia.gov/node/57496. Do it before the first taxable sale."),
    (date(2026, 10, 27), "Forsyth County: Business Location Verification, then the Occupational Tax Certificate application", "You", "Not started", "Yes", "County Business License Division (678) 455-9888. Fee on the 3.30.2026 application was $87.50 for one owner."),
    (date(2026, 10, 27), "Order the 10 test stickers (Amazon TimesKey, $7.99)", "You", "Not started", "Yes", "https://www.amazon.com/dp/B09NXXTXHL. Delivery was quoted as Wed Oct 28."),
    (date(2026, 10, 28), "Put the Stripe Payment Links for the Single and 3-pack on usemivo.app", "Claude + You", "Done", "Yes", "Live links are in data/shop.ts and deployed on Oct 27. Buttons stay disabled until Nov 1. Still to do: turn on automatic tax after the Georgia registration."),
    (date(2026, 10, 29), "Test stickers: program 10 with Mivo Admin, tap each three times through the clear cover, peel and re-stick one", "You", "Not started", "Yes", "Any sticker that needs more than two taps goes to the replacement pile."),
    (date(2026, 10, 29), "Take one packed envelope to the post office: confirm 1 oz and whether they call it non-machinable", "You", "Not started", "Yes", "Then set 'Add the surcharge' on Inputs to Yes or No."),
    (date(2026, 10, 29), "Submit the app update that contains physical Spots to App Store review", "You", "Not started", "Yes", "BLOCKER. The live app is still version 3.0 from Aug 26, 2026 and has no physical Spots (App Store lookup on 2026-10-26). A sticker that opens only a web page is a refund."),
    (date(2026, 10, 30), "Create the three Mivo Plus products in App Store Connect and test a sandbox purchase", "You", "Not started", "No", "Ids in the app: app.mivo.plus.monthly, app.mivo.plus.annual, app.mivo.plus.lifetime. Not needed to sell Spots."),
    (date(2026, 10, 30), "Place one test order on usemivo.app with a Stripe test card, then refund it", "You", "Not started", "Yes", "Test card 4242 4242 4242 4242, any future date, any CVC."),
    (date(2026, 10, 31), "Pack five practice orders and time one", "You", "Not started", "No", "Put the real minutes into your own notes; this workbook does not use them."),
    (date(2026, 11, 1), "LAUNCH: Spots on sale at usemivo.app/shop", "You", "Not started", "Yes", ""),
    (date(2026, 11, 3), "Ship every paid order within 2 business days", "You", "Not started", "No", "Letters have no tracking. Say so on the shipping page (done) and keep a list of what you mailed."),
    (date(2026, 11, 15), "File Georgia sales tax on the schedule the Department of Revenue assigns you", "You", "Not started", "No", "The Georgia Tax Center shows your filing frequency after registration."),
]
dv = DataValidation(type="list", formula1='"Not started,In progress,Done,Blocked"', allow_blank=False)
ws.add_data_validation(dv)
for i, (d, task, who, st, need, det) in enumerate(tasks):
    r = 5 + i
    put(ws, f"A{r}", d, "ddd mmm d", align="center")
    put(ws, f"B{r}", task, wrap=True, font=f(need == "Yes" and "BLOCKER" in det))
    put(ws, f"C{r}", who, align="center", wrap=True)
    put(ws, f"D{r}", st, align="center", font=f(True, BLUE))
    put(ws, f"E{r}", need, align="center")
    put(ws, f"F{r}", det, font=f(color=GRAY), wrap=True)
    dv.add(f"D{r}")
    ws.row_dimensions[r].height = 46
last = 4 + len(tasks)
ws.conditional_formatting.add(f"D5:D{last}", FormulaRule(formula=['D5="Done"'], font=Font(name=FONT, bold=True, color=GREEN), fill=fill("DDF1E3")))
ws.conditional_formatting.add(f"D5:D{last}", FormulaRule(formula=['D5="Blocked"'], font=Font(name=FONT, bold=True, color=RED), fill=fill("FBD9D5")))
ws.conditional_formatting.add(f"D5:D{last}", FormulaRule(formula=['D5="In progress"'], font=Font(name=FONT, bold=True, color="9A5B00"), fill=fill("FFE9C2")))
ws.conditional_formatting.add(f"A5:A{last}", FormulaRule(formula=['AND($D5<>"Done",$A5<TODAY())'], font=Font(name=FONT, bold=True, color=RED)))


def row_of(prefix):
    return 5 + next(i for i, t in enumerate(tasks) if t[1].startswith(prefix))


app_row, stripe_row = row_of("Submit the app update"), row_of("Stripe: create")
tax_row, test_row = row_of("Register a Georgia"), row_of("Place one test order")
ws.freeze_panes = "A5"

# ================================================================ COMPETITORS
ws = ws_cp
title(ws, "Competitors: what others charge",
      "Only prices I could read on a live page on 2026-10-26. One Sec, Jomo and similar apps do not publish prices on their sites, so they are left out rather than guessed.", 6)
header(ws, 4, ["Product", "Plan", "Price", "Link", "Checked", "Note"])
comp = [
    ("Brick", "Brick device (one time)", 59.00, "https://getbrick.com/", "Closest hardware rival. Free shipping over $75. The page does not mention a subscription."),
    ("Brick", "Brick Night device (one time)", 129.00, "https://getbrick.com/", "Bundle with Brick is $169."),
    ("Opal", "Yearly", 99.99, "https://opalapp.com/pricing", "Page also shows $8.29 a month on the yearly plan."),
    ("Opal", "Monthly", 19.99, "https://opalapp.com/pricing", "The page's monthly card also says '$239 billed annually', which looks inconsistent."),
    ("Opal", "Lifetime", 399.00, "https://opalapp.com/pricing", ""),
    ("Clearspace", "Monthly", 6.99, "https://apps.apple.com/us/app/clearspace-reduce-screen-time/id1572515807", "In-app purchase list on the App Store. 4.7 stars from 8.9K ratings."),
    ("Clearspace", "Annual", 44.99, "https://apps.apple.com/us/app/clearspace-reduce-screen-time/id1572515807", "Same listing."),
]
r = 5
for prod, plan, price, url, note in comp:
    put(ws, f"A{r}", prod, font=f(True))
    put(ws, f"B{r}", plan)
    put(ws, f"C{r}", price, USD, align="center")
    link(ws, f"D{r}", url, url)
    put(ws, f"E{r}", date(2026, 10, 26), "mmm d", align="center")
    put(ws, f"F{r}", note, font=f(color=GRAY), wrap=True)
    ws.row_dimensions[r].height = 32
    r += 1
section(ws, r + 1, "Mivo, for comparison (live from Inputs)", 6)
r += 2
mivo = [("Mivo Spot, single", f"={R['p_single']}", "One time, plus the shipping on Inputs"),
        ("Mivo Spot, 3-pack", f"={R['p_pack']}", "One time, free shipping"),
        ("Mivo Plus, monthly", f"={R['plus_m']}", "In the app"),
        ("Mivo Plus, annual", f"={R['plus_y']}", "In the app, 7-day trial"),
        ("Mivo Plus, lifetime", f"={R['plus_l']}", "In the app")]
for name, val, note in mivo:
    put(ws, f"A{r}", "Mivo", font=f(True, GREEN))
    put(ws, f"B{r}", name)
    put(ws, f"C{r}", val, USD, align="center")
    put(ws, f"D{r}", "")
    put(ws, f"E{r}", "")
    put(ws, f"F{r}", note, font=f(color=GRAY))
    r += 1
ws.freeze_panes = "A5"

# ================================================================ SOURCES
ws = ws_src
title(ws, "Sources: every link behind a number",
      "Opened or searched on 2026-10-26 unless the Checked column says otherwise. 'Read' means the page loaded and I took the number from it.", 5)
header(ws, 4, ["#", "Source", "Link", "What it supports", "Checked"])
srcs = [
    ("Amazon: TimesKey NTAG213 25 mm, 10 pcs", "https://www.amazon.com/dp/B09NXXTXHL", "$7.99 for 10, in stock, ratings, specs", date(2026, 10, 26)),
    ("Tagstand: 25 sample NTAG213 stickers", "https://www.tagstand.com/products/25-sample-stickers-the-25-25-25-roll-of-ntag213-stickers-25mm-circle-25-cents-each", "$12.50 for 25, NXP chip, 3M 467MP, 3 in stock", date(2026, 10, 26)),
    ("LabelValue: 1.5 in clear round labels", "https://www.labelvalue.com/15-round-labels-clear-p-929.html", "$9.60 per roll of 500, bulk tiers, free US shipping", date(2026, 10, 26)),
    ("Amazon: Amazon Basics 65 lb cardstock, 250 sheets", "https://www.amazon.com/dp/B0DSH5V1TT", "$10.63", date(2026, 10, 26)),
    ("Amazon: Hammermill 80 lb cardstock, 250 sheets", "https://www.amazon.com/dp/B000J0C47S", "$16.57", date(2026, 10, 26)),
    ("Staples: JAM Paper A6 white envelopes, 100", "https://www.staples.com/jam-paper-a6-booklet-envelope-4-3-4-x-6-1-2-white-100-pack-j0567d/product_24604576", "$18.99", date(2026, 10, 26)),
    ("USPS Notice 123 (prices effective 2026-10-04)", "https://pe.usps.com/text/dmm300/Notice123.htm", "Letter $0.82 / $1.11, flat $1.69, $0.49 surcharge, Ground Advantage $8.40", date(2026, 10, 26)),
    ("Stripe pricing", "https://stripe.com/pricing", "2.9% + 30 cents, no monthly fee, Payment Links free, Stripe Tax 0.5%, disputes $15", date(2026, 10, 26)),
    ("Georgia DOR: how to register a sales and use tax account", "https://dor.georgia.gov/node/57496", "Steps on the Georgia Tax Center, sole proprietor path", date(2026, 10, 26)),
    ("Georgia Tax Center", "https://gtc.dor.ga.gov", "Where you register and file", date(2026, 10, 26)),
    ("Avalara: Forsyth County GA sales tax", "https://www.avalara.com/us/en/taxrates/state-rates/georgia/counties/forsyth.html", "7% minimum combined (4% state + 3% county); search result, page not opened", date(2026, 10, 26)),
    ("Forsyth County: Business License applications", "https://www.forsythco.com/DepartmentsOffices/BusinessLicenses/Applications", "Where the certificate application lives; my fetch was blocked, open it in a browser", date(2026, 10, 26)),
    ("Forsyth County: New Business License Application (PDF)", "https://www.forsythco.com/Portals/0/DeptDoc/Business%20License/Applications/New%20Business%20License%20Application.pdf", "$87.50 fee for one owner on the 3.30.2026 edition, read 2026-10-23", date(2026, 10, 23)),
    ("Apple: App Store Small Business Program", "https://developer.apple.com/app-store/small-business-program/", "15% commission under $1 million in proceeds", date(2026, 10, 26)),
    ("Brick", "https://getbrick.com/", "$59 Brick, $129 Brick Night, $169 bundle", date(2026, 10, 26)),
    ("Opal pricing", "https://opalapp.com/pricing", "$99.99 yearly, $19.99 monthly, $399 lifetime", date(2026, 10, 26)),
    ("Clearspace on the App Store", "https://apps.apple.com/us/app/clearspace-reduce-screen-time/id1572515807", "$6.99 monthly, $44.99 annual", date(2026, 10, 26)),
    ("Apple iTunes lookup: Mivo Scrolling", "https://itunes.apple.com/lookup?id=6762094544&country=us", "Live app is version 3.0 from 2026-08-26; release notes list Mac, not Spots", date(2026, 10, 26)),
]
for i, (name, url, what, d) in enumerate(srcs, 1):
    r = 4 + i
    put(ws, f"A{r}", i, align="center")
    put(ws, f"B{r}", name, wrap=True)
    link(ws, f"C{r}", url, url)
    put(ws, f"D{r}", what, font=f(color=GRAY), wrap=True)
    put(ws, f"E{r}", d, "mmm d", align="center")
    ws.row_dimensions[r].height = 34
ws.freeze_panes = "A5"

# ================================================================ START HERE
ws = ws_start
title(ws, "Mivo Spots and Plus: launch workbook",
      "Selling starts Nov 1, 2026. Prices on Supplies, Competitors and Sources were read on live pages on Oct 26, 2026. Change numbers only on Inputs.", 4)
section(ws, 4, "Where you stand", 4)
put(ws, "A5", "Days until launch", font=f(True))
put(ws, "B5", f"={R['launch']}-TODAY()", "0", f(True, DARK, 14), align="center")
put(ws, "C5", "", border=True)
put(ws, "D5", f'="Launch is "&TEXT({R["launch"]},"dddd, mmmm d, yyyy")', font=f(color=GRAY))
put(ws, "A6", "Logan's cost numbers received", font=f(True))
put(ws, "B6", f"={R['logan_in']}", font=f(True), align="center")
put(ws, "C6", '=IF(COUNT(Inputs!$B$6:$B$8)=3,"ALL IN","WAITING ON LOGAN")', font=f(True), align="center")
put(ws, "D6", "Type them over the orange LOGAN INFO cells on the Inputs tab.", font=f(color=GRAY))
put(ws, "A7", f'="Profit on one Single Spot ("&TEXT({R["p_single"]},"$0.00")&" + "&TEXT({R["s_single"]},"$0.00")&" shipping)"', font=f(True))
put(ws, "B7", "=Profit!B16", USD, f(True, GREEN, 12), align="center")
put(ws, "C7", "=IF(COUNT(Inputs!$B$6:$B$8)=3,\"FINAL\",\"BEFORE LOGAN\")", font=f(True), align="center")
put(ws, "D7", "Too high until Logan's cost is in, because the make cost counts as $0 for now.", font=f(color=GRAY), wrap=True)
put(ws, "A8", f'="Profit on one 3-pack ("&TEXT({R["p_pack"]},"$0.00")&", free shipping)"', font=f(True))
put(ws, "B8", "=Profit!C16", USD, f(True, GREEN, 12), align="center")
put(ws, "C8", "=IF(COUNT(Inputs!$B$6:$B$8)=3,\"FINAL\",\"BEFORE LOGAN\")", font=f(True), align="center")
put(ws, "D8", "", font=f(color=GRAY))
put(ws, "A9", "Most Logan can charge per Single order", font=f(True))
put(ws, "B9", "=Profit!B24", USD, f(True), align="center")
put(ws, "C9", "", border=True)
put(ws, "D9", f'="Still leaves you "&TEXT({R["target"]},"$0.00")&" profit. Change the target on Inputs."', font=f(color=GRAY))
put(ws, "A10", "Most Logan can charge per 3-pack order", font=f(True))
put(ws, "B10", "=Profit!C24", USD, f(True), align="center")
put(ws, "C10", "", border=True)
put(ws, "D10", "Same idea for three stickers in one envelope.", font=f(color=GRAY))
put(ws, "A11", "Profit over the next 12 months (Spots + Plus)", font=f(True))
put(ws, "B11", "=Forecast!N24", USD0, f(True, GREEN, 12), align="center")
put(ws, "C11", "=IF(COUNT(Inputs!$B$6:$B$8)=3,\"FINAL\",\"BEFORE LOGAN\")", font=f(True), align="center")
put(ws, "D11", "Built on guessed orders and installs (Inputs, sections D and E).", font=f(color=GRAY), wrap=True)
for rr in range(5, 12):
    ws.row_dimensions[rr].height = 30
status_rules(ws, "C6:C11")

section(ws, 13, "Profit split: type each person's share", 4)
header(ws, 14, ["Person", "Share of profit", "Gets in 12 months", "Also gets"])
for i, person in enumerate(["Pranshu", "Harsh", "Logan"]):
    r = 15 + i
    put(ws, f"A{r}", person, font=f(True))
    put(ws, f"B{r}", None, PCT, f(True, BLUE), align="center", fill_c=INPUT_FILL)
    put(ws, f"C{r}", f"=N(B{r})*Forecast!$N$24", USD0, f(True, GREEN, 12), align="center")
    put(ws, f"D{r}", f'="Per Single order "&TEXT(N(B{r})*Profit!$B$16,"$0.00")&"  |  per 3-pack "&TEXT(N(B{r})*Profit!$C$16,"$0.00")&"  |  first month "&TEXT(N(B{r})*Forecast!$B$24,"$#,##0")', font=f(color=GRAY), wrap=True)
    ws.row_dimensions[r].height = 30
dv = DataValidation(type="decimal", operator="between", formula1="0", formula2="1", allow_blank=True, showErrorMessage=True,
                    errorTitle="Share of profit", error="Type a percent from 0% to 100%.")
ws.add_data_validation(dv)
dv.add("B15:B17")
put(ws, "A18", "Total", font=f(True))
put(ws, "B18", "=SUM(B15:B17)", PCT, f(True), align="center")
put(ws, "C18", "=SUM(C15:C17)", USD0, f(True), align="center")
put(ws, "D18", '=IF(ABS(B18-1)<0.0001,"OK: the shares add up to 100%",IF(B18=0,"Type each person\'s share. They must add up to 100%.","FIX: the shares add up to "&TEXT(B18,"0.##%")&", not 100%"))', font=f(True), wrap=True)
put(ws, "A19", "Based on", font=f(True))
put(ws, "B19", '=IF(COUNT(Inputs!$B$6:$B$8)=3,"FINAL","BEFORE LOGAN")', font=f(True), align="center")
put(ws, "C19", "", border=True)
put(ws, "D19", "The next 12 months of profit from Spots and Mivo Plus, before income tax. Too high until Logan's costs are in.", font=f(color=GRAY), wrap=True)
for rr in (18, 19):
    ws.row_dimensions[rr].height = 30
ws.conditional_formatting.add("D18", FormulaRule(formula=['LEFT(D18,2)="OK"'], font=Font(name=FONT, bold=True, color=GREEN), fill=fill("DDF1E3")))
ws.conditional_formatting.add("D18", FormulaRule(formula=['LEFT(D18,2)<>"OK"'], font=Font(name=FONT, bold=True, color="9A5B00"), fill=fill("FFE9C2")))
status_rules(ws, "B19")

section(ws, 21, "What still stands between you and Nov 1", 4)
put(ws, "A22", "App update with physical Spots is live on the App Store", font=f(True))
put(ws, "B22", f"='Launch Checklist'!D{app_row}", font=f(True), align="center")
put(ws, "C22", '=IF(B22="Done","DONE","NOT DONE")', font=f(True), align="center")
put(ws, "D22", "The live app is still 3.0 from Aug 26 and has no physical Spots. Customers who tap a sticker would land on a web page.", font=f(color=GRAY), wrap=True)
put(ws, "A23", "Stripe account activated", font=f(True))
put(ws, "B23", f"='Launch Checklist'!D{stripe_row}", font=f(True), align="center")
put(ws, "C23", "", border=True)
put(ws, "D23", "Identity and bank details have to be entered by you.", font=f(color=GRAY))
put(ws, "A24", "Georgia sales tax account registered", font=f(True))
put(ws, "B24", f"='Launch Checklist'!D{tax_row}", font=f(True), align="center")
put(ws, "C24", "", border=True)
put(ws, "D24", "Free on the Georgia Tax Center. Do it before the first sale.", font=f(color=GRAY))
put(ws, "A25", "Test order placed and refunded", font=f(True))
put(ws, "B25", f"='Launch Checklist'!D{test_row}", font=f(True), align="center")
put(ws, "C25", "", border=True)
put(ws, "D25", "Use Stripe's 4242 test card.", font=f(color=GRAY))
for rr in range(22, 26):
    ws.row_dimensions[rr].height = 34
ws.conditional_formatting.add("B22:B25", FormulaRule(formula=['B22="Done"'], font=Font(name=FONT, bold=True, color=GREEN), fill=fill("DDF1E3")))
ws.conditional_formatting.add("B22:B25", FormulaRule(formula=['B22<>"Done"'], font=Font(name=FONT, bold=True, color="9A5B00"), fill=fill("FFE9C2")))
ws.conditional_formatting.add("C22", FormulaRule(formula=['B22<>"Done"'], font=Font(name=FONT, bold=True, color=RED), fill=fill("FBD9D5")))

section(ws, 27, "The tabs", 4)
guide = [
    ("Inputs", "Every number you can change. The three orange LOGAN INFO cells live here."),
    ("Profit", "What one Single and one 3-pack order earn, and the most Logan can charge."),
    ("Forecast", "12 months of Spots and Mivo Plus together."),
    ("Supplies", "Real products, prices and links, plus postage and fees."),
    ("Launch Checklist", "Dated tasks from today to Nov 1, with a status dropdown."),
    ("Competitors", "What Brick, Opal and Clearspace charge, next to Mivo."),
    ("Sources", "Every link behind a number."),
]
for i, (tab, desc) in enumerate(guide):
    r = 28 + i
    put(ws, f"A{r}", tab, font=f(True, DARK))
    put(ws, f"B{r}", desc, font=f(color=GRAY))
    ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
ws.freeze_panes = "A4"

# print setup
for w in wb.worksheets:
    w.page_setup.orientation = "landscape"
    w.page_setup.fitToWidth = 1
    w.page_setup.fitToHeight = 0
    w.sheet_properties.pageSetUpPr = PageSetupProperties(fitToPage=True)
    w.sheet_properties.tabColor = {"START HERE": "2B1D0E", "Inputs": "FFC25C", "Profit": "1E7B3A", "Forecast": "1E7B3A"}.get(w.title, "A89F91")

wb.save(OUT)
print("saved", OUT)
