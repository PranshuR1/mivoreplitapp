#!/usr/bin/env python3
"""Builds the Mivo Spot packaging: HTML sources -> print PDFs and PNG proofs.

Pieces (trim size, plus 1/8 in or 1.5 mm bleed baked into the PDF page):
  card-1up / card-3up  4 x 6 in landscape card, page 1 front, page 2 back
  seal                 2 in round envelope seal sticker
  sticker-<N>mm        the NFC sticker face (N = STICKER_MM)

Run:  python3 make_logo.py   (once, makes assets/logo-*.png)
      python3 build.py       (needs Google Chrome; fonts load from Google Fonts)

Outputs: print/*.pdf (send to the printer), proofs/*.png (look at these).
The proofs show the sticker sitting on the card; the card PDFs do not contain it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
STICKER_MM = 25  # Amazon B09NXXTXHL (TimesKey NTAG213, 25 mm round); the card guides adapt
STICKER_PRINTED = False  # that listing is blank white; True mocks the Mivo-printed face from sticker_face()
COVER_MM = 38.1  # clear round label (1.5 in, the cheap stock size) pressed over the sticker; its rim seals the edge. Home-print rings fit this
BLEED = 0.125  # inches

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Instrument+Serif:ital@0;1&display=swap');
:root{--dark:#161008;--socket:#2A1D14;--cream:#FAF3E8;--ink:#3D2313;--body:#6E5238;--amber:#D4872A;
--amber-lt:#E29A50;--dk-body:#C8B39B;--dk-muted:#A8896F;--sticker:#F6E8C8}
@page{margin:0}
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:#fff}
body{font-family:Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
.page{position:relative;overflow:hidden;break-after:page}
.page:last-child{break-after:auto}
.dark{background:var(--dark);color:var(--cream)}
.light{background:var(--cream);color:var(--ink)}
.art{position:absolute;left:0;top:0;width:100%;height:100%}
.trim{position:absolute;left:.125in;top:.125in}
.abs{position:absolute}
.eyebrow{font-weight:600;font-size:6.6pt;line-height:1;letter-spacing:.22em;text-transform:uppercase}
.serif{font-family:'Instrument Serif',Georgia,serif;font-style:italic;font-weight:400}
.cap{font-weight:600;font-size:6.2pt;line-height:1;letter-spacing:.2em;text-transform:uppercase}
.sub{font-size:9pt;line-height:1.5}
.step .n{font:italic 400 30pt/1 'Instrument Serif',Georgia,serif;color:var(--amber)}
.step h3{font-weight:600;font-size:11pt;line-height:1.2;margin:.1in 0 .05in}
.step p{font-size:8.3pt;line-height:1.5;color:var(--body)}
.fine{font-size:6.4pt;line-height:1.55;color:var(--body)}
.sticker{position:absolute;border-radius:50%;background:var(--sticker);display:grid;place-items:center;
box-shadow:0 .02in .05in rgba(0,0,0,.45)}
.sticker img{width:66%;display:block}
.cell{position:absolute;width:5.5in;height:4.25in}
.cutline{position:absolute;border:0 dashed #BFB3A3}
.hn{font:italic 400 24pt/1 'Instrument Serif',Georgia,serif;color:#B5621E}
.hstep h3{font-weight:600;font-size:9.5pt;line-height:1.2;margin:.07in 0 .04in;color:#3D2313}
.hstep p{font-size:7.1pt;line-height:1.5;color:#6E5238}
.hfine{font-size:5.9pt;line-height:1.55;color:#6E5238}
.guide .trim{outline:1px dashed rgba(255,0,0,.8)}
.guide .safe{position:absolute;left:.25in;top:.25in;right:.25in;bottom:.25in;outline:1px dashed rgba(0,160,255,.8)}
"""


def doc(pages, w, h, guides=False):
    body = "".join(pages)
    cls = " guide" if guides else ""
    return (
        f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}"
        f"@page{{size:{w}in {h}in}}.page{{width:{w}in;height:{h}in}}</style></head>"
        f"<body class='{cls.strip()}'>{body}</body></html>"
    )


def rings(cx, cy, r0, extra, w=6.25, h=4.25):
    """Socket disc + placement ring + fading NFC pulse rings, in trim inches."""
    s = [f"<svg class='art' viewBox='-{BLEED} -{BLEED} {w} {h}' xmlns='http://www.w3.org/2000/svg'>"]
    s.append(f"<circle cx='{cx}' cy='{cy}' r='{r0}' fill='#2A1D14' stroke='#D4872A' stroke-width='.012'/>")
    for i, op in enumerate(extra, 1):
        s.append(
            f"<circle cx='{cx}' cy='{cy}' r='{r0 + 0.2 * i:.3f}' fill='none' stroke='#D4872A' "
            f"stroke-opacity='{op}' stroke-width='.01'/>"
        )
    s.append("</svg>")
    return "".join(s)


def sticker_div(cx, cy, d_in, logo="../assets/logo-light.png"):
    r = d_in / 2
    face = f"<img src='{logo}'>" if STICKER_PRINTED else ""
    bg = "" if STICKER_PRINTED else "background:#F6F4EE;"
    return (
        f"<div class='sticker' style='{bg}left:{cx - r:.3f}in;top:{cy - r:.3f}in;width:{d_in:.3f}in;height:{d_in:.3f}in'>"
        f"{face}</div>"
    )


def card_front_1up(mock=False):
    d = STICKER_MM / 25.4
    r0 = d / 2 + 0.06
    cx, cy = 4.4, 2.0
    page = (
        "<section class='page dark'>"
        + rings(cx, cy, r0, (0.4, 0.22, 0.1))
        + "<div class='trim' style='width:6in;height:4in'>"
        + "<img class='abs' src='../assets/logo-dark.png' style='left:.5in;top:.5in;height:.52in'>"
        + "<div class='abs eyebrow' style='left:.5in;top:1.42in;color:var(--amber-lt)'>Your Mivo Spot</div>"
        + "<h1 class='abs serif' style='left:.5in;top:1.62in;width:2.7in;font-size:33pt;line-height:1.02'>"
        + "Pause before<br>you scroll.</h1>"
        + "<p class='abs sub' style='left:.5in;top:2.72in;width:2.3in;color:var(--dk-body)'>"
        + "Peel it off and stick it where you reach for your phone.</p>"
        + "<div class='abs cap' style='left:.5in;top:3.48in;color:var(--dk-muted)'>Not a block &mdash; a choice.</div>"
        + f"<div class='abs cap' style='left:{cx - 1.4}in;width:2.8in;top:3.48in;text-align:center;color:var(--amber-lt)'>"
        + "Tap here with your iPhone</div>"
        + (sticker_div(cx, cy, d) if mock else "")
        + "<div class='safe'></div></div></section>"
    )
    return page


def card_front_3up(mock=False):
    d = STICKER_MM / 25.4
    r0 = d / 2 + 0.06
    cy = 2.62
    xs = (1.2, 3.0, 4.8)
    art = ["<svg class='art' viewBox='-0.125 -0.125 6.25 4.25' xmlns='http://www.w3.org/2000/svg'>"]
    for x in xs:
        art.append(f"<circle cx='{x}' cy='{cy}' r='{r0}' fill='#2A1D14' stroke='#D4872A' stroke-width='.012'/>")
        art.append(f"<circle cx='{x}' cy='{cy}' r='{r0 + 0.2}' fill='none' stroke='#D4872A' stroke-opacity='.3' stroke-width='.01'/>")
    art.append("</svg>")
    labels = "".join(
        f"<div class='abs cap' style='left:{x - 0.9}in;width:1.8in;top:3.56in;text-align:center;color:var(--dk-muted)'>{t}</div>"
        for x, t in zip(xs, ("Try: Study Desk", "Try: Bedside", "Try: Car"))
    )
    stickers = "".join(sticker_div(x, cy, d) for x in xs) if mock else ""
    return (
        "<section class='page dark'>" + "".join(art)
        + "<div class='trim' style='width:6in;height:4in'>"
        + "<img class='abs' src='../assets/logo-dark.png' style='left:.5in;top:.42in;height:.4in'>"
        + "<div class='abs eyebrow' style='right:.5in;top:.5in;color:var(--amber-lt)'>Three Mivo Spots</div>"
        + "<h1 class='abs serif' style='left:.5in;top:.98in;font-size:27pt;line-height:1;white-space:nowrap'>Pause before you scroll.</h1>"
        + "<p class='abs sub' style='left:.5in;top:1.48in;width:5.5in;color:var(--dk-body)'>"
        + "Tap one with your iPhone to set it up, then stick it where you reach for your phone.</p>"
        + labels + stickers + "</div></section>"
    )


def card_back():
    steps = (
        ("1", "Tap", "Hold the top of your iPhone to the sticker, then tap the banner that appears. Mivo sets it up with you."),
        ("2", "Stick", "Peel it off and press it on a clean, flat surface where you reach for your phone: desk, nightstand, car."),
        ("3", "Tap again", "Tap to start your Spot, tap again to end it. A Spot adds a pause. It never locks you out."),
    )
    cols = "".join(
        f"<div class='abs step' style='left:{x}in;top:1.28in;width:1.5in'><div class='n'>{n}</div><h3>{t}</h3><p>{b}</p></div>"
        for x, (n, t, b) in zip((0.5, 2.25, 4.0), steps)
    )
    return (
        "<section class='page light'><div class='trim' style='width:6in;height:4in'>"
        + "<h2 class='abs serif' style='left:.5in;top:.45in;font-size:26pt;line-height:1;color:var(--ink)'>Set up in a minute.</h2>"
        + cols
        + "<div class='abs' style='left:.5in;right:.5in;top:3.06in;height:0;border-top:.5pt solid rgba(61,35,19,.2)'></div>"
        + "<p class='abs fine' style='left:.5in;top:3.17in;width:4.0in'>Works with iPhone XS or later on iOS 17. "
        + "Not for bare metal. Every Mivo Spot is unique and connects to one Mivo account. "
        + "No Mivo yet? The tap opens a page that links to the App Store. Help: usemivo.app/support</p>"
        + "<img class='abs' src='../assets/logo-light.png' style='right:.5in;top:3.14in;height:.46in'>"
        + "<div class='safe'></div></div></section>"
    )


def seal():
    art = (
        "<svg class='art' viewBox='-0.125 -0.125 2.25 2.25' xmlns='http://www.w3.org/2000/svg'>"
        "<circle cx='1' cy='1' r='.9' fill='none' stroke='#D4872A' stroke-opacity='.7' stroke-width='.008'/></svg>"
    )
    return (
        "<section class='page dark'>" + art
        + "<div class='trim' style='width:2in;height:2in'>"
        + "<img class='abs' src='../assets/logo-dark.png' style='left:.42in;top:.52in;width:1.16in'>"
        + "<div class='abs serif' style='left:0;width:2in;top:1.32in;text-align:center;font-size:8.5pt;color:var(--dk-body)'>"
        + "Your Mivo Spot is inside.</div></div></section>"
    )


def sticker_face():
    k = STICKER_MM / 30
    page_mm = (STICKER_MM + 3)
    c = page_mm / 2
    return (
        f"<section class='page' style='background:var(--sticker)'>"
        f"<svg class='art' viewBox='0 0 {page_mm} {page_mm}' xmlns='http://www.w3.org/2000/svg'>"
        f"<circle cx='{c}' cy='{c}' r='{12.9 * k}' fill='none' stroke='#D4872A' stroke-width='{0.35 * k}'/></svg>"
        f"<img class='abs' src='../assets/logo-light.png' style='left:{c - 9.6 * k}mm;top:{c - 6.2 * k}mm;width:{19.2 * k}mm'>"
        "</section>"
    )


def chrome(args):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    "--hide-scrollbars", "--virtual-time-budget=12000", *args],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def emit(name, pages, w, h, proof_pages=None):
    (ROOT / "print").mkdir(exist_ok=True)
    (ROOT / "proofs").mkdir(exist_ok=True)
    src = ROOT / "print" / f"{name}.html"
    src.write_text(doc(pages, w, h))
    chrome([f"--print-to-pdf={ROOT / 'print' / (name + '.pdf')}", src.as_uri()])
    for i, page in enumerate(proof_pages or pages):
        p = ROOT / "print" / f"{name}-proof{i}.html"
        p.write_text(doc([page], w, h, guides=True))
        chrome([f"--screenshot={ROOT / 'proofs' / f'{name}-{i + 1}.png'}", "--force-device-scale-factor=4",
                f"--window-size={int(w * 96)},{int(h * 96)}", p.as_uri()])
    print("built", name)


def home_front_cell():
    """Light 5.5 x 4.25 in card for a home printer: white paper, nothing within 0.5 in of the sheet edge."""
    r0 = COVER_MM / 25.4 / 2 + 0.04
    cx, cy = 3.95, 2.05
    rings = f"<circle cx='{cx}' cy='{cy}' r='{r0:.3f}' fill='none' stroke='#B5621E' stroke-width='.012'/>"
    for i, op in enumerate((0.5, 0.32, 0.18), 1):
        rings += (f"<circle cx='{cx}' cy='{cy}' r='{r0 + 0.08 * i:.3f}' fill='none' stroke='#D4872A' "
                  f"stroke-opacity='{op}' stroke-width='.01'/>")
    return (
        f"<svg class='art' viewBox='0 0 5.5 4.25' xmlns='http://www.w3.org/2000/svg'>{rings}</svg>"
        "<img class='abs' src='../assets/logo-light.png' style='left:.5in;top:.5in;height:.42in'>"
        "<div class='abs eyebrow' style='left:.5in;top:1.22in;color:#B5621E'>Your Mivo Spot</div>"
        "<h1 class='abs serif' style='left:.5in;top:1.4in;width:2.4in;font-size:25pt;line-height:1.02;color:var(--ink)'>"
        "Pause before<br>you scroll.</h1>"
        "<p class='abs sub' style='left:.5in;top:2.38in;width:2.1in;font-size:8.3pt;color:var(--body)'>"
        "Peel it off and stick it where you reach for your phone.</p>"
        "<div class='abs cap' style='left:.5in;top:3.5in;color:#9C7A56'>Not a block &mdash; a choice.</div>"
        f"<div class='abs cap' style='left:{cx - 0.9}in;width:1.8in;top:3.5in;text-align:center;color:#B5621E'>Tap here with your iPhone</div>"
    )


def home_front3_cell():
    """Three-sticker version of home_front_cell: three rings across the 4.5 in safe width."""
    r0 = COVER_MM / 25.4 / 2 + 0.02
    cy = 2.5
    xs = (1.09, 2.75, 4.41)  # 0.32 in from the sheet edge on the outer cards: check your printer's minimum margin
    rings = "".join(
        f"<circle cx='{x}' cy='{cy}' r='{r0:.3f}' fill='none' stroke='#B5621E' stroke-width='.012'/>" for x in xs
    )
    caps = "".join(
        f"<div class='abs cap' style='left:{x - 0.7}in;width:1.4in;top:3.4in;text-align:center;color:#9C7A56'>{t}</div>"
        for x, t in zip(xs, ("Try: Study Desk", "Try: Bedside", "Try: Car"))
    )
    return (
        f"<svg class='art' viewBox='0 0 5.5 4.25' xmlns='http://www.w3.org/2000/svg'>{rings}</svg>"
        "<img class='abs' src='../assets/logo-light.png' style='left:.5in;top:.5in;height:.4in'>"
        "<div class='abs eyebrow' style='right:.5in;top:.58in;color:#B5621E'>Three Mivo Spots</div>"
        "<h1 class='abs serif' style='left:.5in;top:1.0in;font-size:21pt;line-height:1;white-space:nowrap;color:var(--ink)'>"
        "Pause before you scroll.</h1>"
        "<p class='abs sub' style='left:.5in;top:1.42in;width:4.5in;font-size:7.8pt;color:var(--body)'>"
        "Tap one with your iPhone to set it up, then stick it where you reach for your phone.</p>"
        + caps
    )


def home_back_cell():
    steps = (
        ("1", "Tap", "Hold the top of your iPhone to the sticker, then tap the banner that appears. Mivo sets it up with you."),
        ("2", "Stick", "Peel it off and press it on a clean, flat surface where you reach for your phone. The clear cover keeps the edges down."),
        ("3", "Tap again", "Tap to start your Spot, tap again to end it. A Spot adds a pause. It never locks you out."),
    )
    cols = "".join(
        f"<div class='abs hstep' style='left:{x}in;top:1.15in;width:1.4in'><div class='hn'>{n}</div><h3>{t}</h3><p>{b}</p></div>"
        for x, (n, t, b) in zip((0.5, 2.02, 3.54), steps)
    )
    return (
        "<h2 class='abs serif' style='left:.5in;top:.5in;font-size:21pt;line-height:1;color:var(--ink)'>Set up in a minute.</h2>"
        + cols
        + "<div class='abs' style='left:.5in;width:4.5in;top:2.78in;height:0;border-top:.5pt solid rgba(61,35,19,.2)'></div>"
        + "<p class='abs hfine' style='left:.5in;top:2.88in;width:3.3in'>Works with iPhone XS or later on iOS 17. "
        + "Not for bare metal. Every Mivo Spot is unique and connects to one Mivo account. "
        + "No Mivo yet? The tap opens a page that links to the App Store. Help: usemivo.app/support</p>"
        + "<img class='abs' src='../assets/logo-light.png' style='left:4.4in;top:2.86in;height:.38in'>"
    )


def home_sheet(cell_html, cuts):
    """US Letter landscape, four identical quarter-sheet cards; cut along the centre cross."""
    cells = "".join(
        f"<div class='cell' style='left:{x}in;top:{y}in'>{cell_html}</div>" for x in (0, 5.5) for y in (0, 4.25)
    )
    lines = (
        "<div class='cutline' style='left:5.5in;top:0;height:8.5in;border-left-width:.5pt'></div>"
        "<div class='cutline' style='left:0;top:4.25in;width:11in;border-top-width:.5pt'></div>"
    ) if cuts else ""
    return f"<section class='page' style='background:#fff'>{cells}{lines}</section>"


def home():
    back = home_sheet(home_back_cell(), False)
    emit("home-print", [home_sheet(home_front_cell(), True), back], 11, 8.5)
    emit("home-print-3pack", [home_sheet(home_front3_cell(), True), back], 11, 8.5)
    cover_diagram()


def cover_diagram():
    """Side view of a covered sticker on a surface (not to scale in thickness)."""
    s, c = STICKER_MM * 12, COVER_MM * 12  # 12 px per mm
    x0, x1 = 300 - s / 2, 300 + s / 2
    c0, c1 = 300 - c / 2, 300 + c / 2
    svg = f"""<svg viewBox='0 0 600 300' xmlns='http://www.w3.org/2000/svg' font-family='Inter,sans-serif'>
<rect x='40' y='214' width='520' height='34' rx='3' fill='#D9CDBE'/>
<text x='52' y='236' font-size='13' fill='#6E5238'>Desk, nightstand, car: any clean, flat, non-metal surface</text>
<rect x='{c0}' y='206' width='{c1 - c0}' height='8' fill='#D4872A' fill-opacity='.45'/>
<rect x='{x0}' y='190' width='{x1 - x0}' height='16' rx='2' fill='#F6F4EE' stroke='#8B4E28' stroke-width='1.5'/>
<path d='M{c0},206 L{x0 - 2},206 L{x0 - 2},186 L{x1 + 2},186 L{x1 + 2},206 L{c1},206' fill='none' stroke='#4A6FA5' stroke-width='4' stroke-linejoin='round'/>
<line x1='{c0 + 12}' y1='204' x2='110' y2='142' stroke='#6E5238' stroke-width='1'/>
<text x='40' y='108' font-size='13' fill='#3D2313' font-weight='600'>Clear cover, {COVER_MM:g} mm</text>
<text x='40' y='126' font-size='12' fill='#6E5238'>its rim sticks to the surface</text>
<line x1='330' y1='182' x2='330' y2='142' stroke='#6E5238' stroke-width='1'/>
<text x='330' y='108' font-size='13' fill='#3D2313' font-weight='600'>Sticker, {STICKER_MM} mm</text>
<text x='330' y='126' font-size='12' fill='#6E5238'>chip inside; still reads through the film</text>
</svg>"""
    html = (f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}body{{background:#FAF3E8;width:6.25in;height:3.125in}}"
            f"svg{{width:100%;height:100%;display:block}}</style></head><body>{svg}</body></html>")
    src = ROOT / "print" / "cover-diagram.html"
    src.write_text(html)
    chrome([f"--screenshot={ROOT / 'proofs' / 'cover-diagram.png'}", "--force-device-scale-factor=3",
            f"--window-size={int(6.25 * 96)},{int(3.125 * 96)}", src.as_uri()])
    print("built cover-diagram")


def board():
    """One overview image: every piece at trim size, plus a sealed-envelope mockup."""
    flap = "clip-path:polygon(0 0,100% 0,50% 100%)"
    html = f"""<!doctype html><html><head><meta charset='utf-8'><style>{CSS}
body{{background:#E8E3DA;width:14in}}
.board{{padding:.7in;display:grid;grid-template-columns:6in 6in;gap:.45in .6in}}
.lbl{{font-weight:600;font-size:8.5pt;letter-spacing:.2em;text-transform:uppercase;color:#6E5238;margin-bottom:.12in}}
.crop{{position:relative;width:6in;height:4in;overflow:hidden;border-radius:.05in;box-shadow:0 .04in .16in rgba(61,35,19,.25)}}
.crop .page{{position:absolute;left:-.125in;top:-.125in;width:6.25in;height:4.25in}}
.stage{{position:relative;width:6in;height:4in}}
.env{{position:absolute;left:.25in;top:0;width:5.5in;height:4.02in;background:#C9A77C;border-radius:.04in;box-shadow:0 .05in .18in rgba(61,35,19,.35)}}
.flap{{position:absolute;left:.25in;top:0;width:5.5in;height:2.2in;background:#B8935F;{flap}}}
.seal{{position:absolute;left:2.35in;top:1.55in;width:1.3in;height:1.3in;border-radius:50%;overflow:hidden;box-shadow:0 .03in .08in rgba(0,0,0,.45)}}
.seal > div{{width:2.25in;height:2.25in;transform:scale(.6667);transform-origin:0 0;margin:-.0833in 0 0 -.0833in}}
.seal .page{{width:2.25in;height:2.25in}}
</style></head><body><div class='board'>
<div><div class='lbl'>Single Spot &middot; front</div><div class='crop'>{card_front_1up(mock=True)}</div></div>
<div><div class='lbl'>Back &middot; same on both</div><div class='crop'>{card_back()}</div></div>
<div><div class='lbl'>3-pack &middot; front</div><div class='crop'>{card_front_3up(mock=True)}</div></div>
<div><div class='lbl'>Kraft envelope &middot; round seal</div><div class='stage'>
<div class='env'></div><div class='flap'></div><div class='seal'><div>{seal()}</div></div></div></div>
</div></body></html>"""
    src = ROOT / "print" / "board.html"
    src.write_text(html)
    chrome([f"--screenshot={ROOT / 'proofs' / 'board.png'}", "--force-device-scale-factor=2",
            f"--window-size={int(14 * 96)},{int(10.3 * 96)}", src.as_uri()])
    print("built board")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "board":
        return board()
    if len(sys.argv) > 1 and sys.argv[1] == "home":
        return home()
    cw, ch = 6 + 2 * BLEED, 4 + 2 * BLEED
    home()
    emit("card-1up", [card_front_1up(), card_back()], cw, ch, [card_front_1up(mock=True), card_back()])
    emit("card-3up", [card_front_3up(), card_back()], cw, ch, [card_front_3up(mock=True), card_back()])
    sw = 2 + 2 * BLEED
    emit("seal", [seal()], sw, sw)
    mm = (STICKER_MM + 3) / 25.4
    emit(f"sticker-{STICKER_MM}mm", [sticker_face()], mm, mm)


if __name__ == "__main__":
    main()
