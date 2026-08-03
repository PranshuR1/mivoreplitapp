from pathlib import Path

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path("/Users/pranshuraithatha/mivoreplitapp")
OUTPUT_DIR = ROOT / "output" / "partnership"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_PATH = OUTPUT_DIR / "Studies_Timer_Mivo_Partnership_Agreement_Draft.docx"
LOGO_PATH = ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png"

ORANGE = "D8891F"
BROWN = "6B321A"
CREAM = "FFF8ED"
PALE_ORANGE = "F7E8CA"
PALE_BLUE = "EAF0F8"
BLUE = "4D76B3"
CHARCOAL = "2A211D"
MUTED = "74665C"
WHITE = "FFFFFF"
LINE = "D8C6AA"
RED = "9B2C2C"


def rgb(value):
    return RGBColor.from_string(value)


def set_run(run, size=10.2, color=CHARCOAL, bold=False, italic=False, font="Aptos"):
    run.font.name = font
    rpr = run._element.get_or_add_rPr()
    rpr.rFonts.set(qn("w:ascii"), font)
    rpr.rFonts.set(qn("w:hAnsi"), font)
    run.font.size = Pt(size)
    run.font.color.rgb = rgb(color)
    run.bold = bold
    run.italic = italic


def paragraph(
    doc,
    text="",
    *,
    size=10.2,
    color=CHARCOAL,
    bold=False,
    italic=False,
    align=WD_ALIGN_PARAGRAPH.LEFT,
    before=0,
    after=5,
    line=1.10,
    keep=False,
):
    p = doc.add_paragraph()
    p.alignment = align
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = line
    p.paragraph_format.keep_with_next = keep
    p.paragraph_format.widow_control = True
    if text:
        set_run(p.add_run(text), size=size, color=color, bold=bold, italic=italic)
    return p


def heading(doc, number, title):
    p = doc.add_paragraph(style="Heading 2")
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    p.paragraph_format.widow_control = True
    p.clear()
    set_run(p.add_run(f"{number}. "), size=12.2, color=ORANGE, bold=True)
    set_run(p.add_run(title), size=12.2, color=BROWN, bold=True)
    return p


def clause(doc, text, *, after=5):
    return paragraph(doc, text, size=10.1, after=after, line=1.12)


def bullet(doc, text):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.left_indent = Inches(0.33)
    p.paragraph_format.first_line_indent = Inches(-0.20)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.line_spacing = 1.08
    p.paragraph_format.widow_control = True
    set_run(p.add_run(text), size=10.0)
    return p


def set_cell_shading(cell, color):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), color)


def set_cell_margins(cell, top=105, start=140, bottom=105, end=140):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for edge, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_geometry(table, widths):
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.first_child_found_in("w:tblW")
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(sum(widths)))
    tbl_w.set(qn("w:type"), "dxa")
    tbl_ind = tbl_pr.first_child_found_in("w:tblInd")
    if tbl_ind is None:
        tbl_ind = OxmlElement("w:tblInd")
        tbl_pr.append(tbl_ind)
    tbl_ind.set(qn("w:w"), "120")
    tbl_ind.set(qn("w:type"), "dxa")
    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(width))
        grid.append(col)
    for row in table.rows:
        for cell, width in zip(row.cells, widths):
            tc_pr = cell._tc.get_or_add_tcPr()
            tc_w = tc_pr.first_child_found_in("w:tcW")
            if tc_w is None:
                tc_w = OxmlElement("w:tcW")
                tc_pr.append(tc_w)
            tc_w.set(qn("w:w"), str(width))
            tc_w.set(qn("w:type"), "dxa")


def set_table_borders(table, color=LINE, size=5):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        node = borders.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            borders.append(node)
        node.set(qn("w:val"), "single")
        node.set(qn("w:sz"), str(size))
        node.set(qn("w:space"), "0")
        node.set(qn("w:color"), color)


def repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    marker = OxmlElement("w:tblHeader")
    marker.set(qn("w:val"), "true")
    tr_pr.append(marker)


def add_page_number(paragraph_obj):
    run = paragraph_obj.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = "PAGE"
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.extend([begin, instr, separate, end])


def bottom_border(p, color=ORANGE, size=10, space=5):
    p_pr = p._p.get_or_add_pPr()
    p_bdr = p_pr.find(qn("w:pBdr"))
    if p_bdr is None:
        p_bdr = OxmlElement("w:pBdr")
        p_pr.append(p_bdr)
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), str(size))
    bottom.set(qn("w:space"), str(space))
    bottom.set(qn("w:color"), color)
    p_bdr.append(bottom)


def add_summary_table(doc):
    table = doc.add_table(rows=0, cols=2)
    header = table.add_row()
    repeat_table_header(header)
    for cell, text in zip(header.cells, ("Agreement detail", "Term")):
        set_cell_shading(cell, BROWN)
        set_cell_margins(cell, top=85, bottom=85)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        set_run(p.add_run(text), size=9.1, color=WHITE, bold=True)
    rows = [
        ("Parties", "Studies Timer and Mivo Scrolling"),
        ("Effective date", "August 1, 2026"),
        ("Initial term", "August 1, 2026 through January 31, 2027"),
        ("Paying party", "Studies Timer"),
        ("Receiving party", "Mivo Scrolling"),
        ("Payment", "$150 down payment plus six monthly payments of $200"),
        ("Total commitment", "$1,350 USD"),
        ("Primary purpose", "Cross-promotion, product placement, audience growth, and Mivo website optimization"),
    ]
    for idx, (label, value) in enumerate(rows):
        row = table.add_row()
        for cell in row.cells:
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_shading(row.cells[0], PALE_ORANGE)
        set_cell_shading(row.cells[1], CREAM if idx % 2 == 0 else WHITE)
        p = row.cells[0].paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        set_run(p.add_run(label), size=9.3, color=BROWN, bold=True)
        p = row.cells[1].paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        set_run(p.add_run(value), size=9.6)
    set_table_geometry(table, [2400, 6960])
    set_table_borders(table)


def add_payment_schedule(doc):
    table = doc.add_table(rows=0, cols=3)
    header = table.add_row()
    repeat_table_header(header)
    for cell, text in zip(header.cells, ("Payment", "Due date", "Amount")):
        set_cell_shading(cell, BLUE)
        set_cell_margins(cell, top=85, bottom=85)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(0)
        set_run(p.add_run(text), size=9.2, color=WHITE, bold=True)
    schedule = [
        ("Down payment", "Upon signing; no later than August 1, 2026", "$150"),
        ("Month 1", "August 1, 2026", "$200"),
        ("Month 2", "September 1, 2026", "$200"),
        ("Month 3", "October 1, 2026", "$200"),
        ("Month 4", "November 1, 2026", "$200"),
        ("Month 5", "December 1, 2026", "$200"),
        ("Month 6", "January 1, 2027", "$200"),
        ("Total", "", "$1,350"),
    ]
    for idx, values in enumerate(schedule):
        row = table.add_row()
        for col_idx, (cell, text) in enumerate(zip(row.cells, values)):
            set_cell_margins(cell, top=85, bottom=85)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            if idx == len(schedule) - 1:
                set_cell_shading(cell, PALE_ORANGE)
            elif idx % 2:
                set_cell_shading(cell, CREAM)
            p = cell.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if col_idx == 2 else WD_ALIGN_PARAGRAPH.LEFT
            set_run(
                p.add_run(text),
                size=9.5,
                color=BROWN if idx == len(schedule) - 1 else CHARCOAL,
                bold=idx == len(schedule) - 1,
            )
    set_table_geometry(table, [2400, 4800, 2160])
    set_table_borders(table)


def signature_block(doc, name, role, organization):
    p = paragraph(doc, "", before=16, after=2)
    set_run(p.add_run("Signature: "), size=9.4, color=MUTED, bold=True)
    set_run(p.add_run("____________________________________________"), size=10.2)
    p = paragraph(doc, "", after=2)
    set_run(p.add_run("Printed name: "), size=9.4, color=MUTED, bold=True)
    set_run(p.add_run(name), size=10.2, bold=True)
    p = paragraph(doc, "", after=2)
    set_run(p.add_run("Title: "), size=9.4, color=MUTED, bold=True)
    set_run(p.add_run(role), size=10.2)
    p = paragraph(doc, "", after=6)
    set_run(p.add_run("Organization: "), size=9.4, color=MUTED, bold=True)
    set_run(p.add_run(organization), size=10.2)
    set_run(p.add_run("     Date: ____________________"), size=10.2)


def configure(doc):
    section = doc.sections[0]
    section.top_margin = Inches(0.72)
    section.bottom_margin = Inches(0.68)
    section.left_margin = Inches(1.0)
    section.right_margin = Inches(1.0)
    section.header_distance = Inches(0.28)
    section.footer_distance = Inches(0.30)

    normal = doc.styles["Normal"]
    normal.font.name = "Aptos"
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Aptos")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Aptos")
    normal.font.size = Pt(10.2)
    normal.font.color.rgb = rgb(CHARCOAL)
    normal.paragraph_format.space_after = Pt(5)
    normal.paragraph_format.line_spacing = 1.10

    for style_name, size, color in (
        ("Heading 1", 16, BROWN),
        ("Heading 2", 12.2, BROWN),
        ("Heading 3", 11.2, BLUE),
    ):
        style = doc.styles[style_name]
        style.font.name = "Aptos Display"
        style._element.rPr.rFonts.set(qn("w:ascii"), "Aptos Display")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Aptos Display")
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = rgb(color)

    header = section.header.paragraphs[0]
    header.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    header.paragraph_format.space_after = Pt(0)
    set_run(header.add_run("MIVO SCROLLING  |  STUDIES TIMER"), size=8.3, color=MUTED, bold=True)

    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
    footer.paragraph_format.space_after = Pt(0)
    set_run(footer.add_run("Partnership Agreement  |  Draft for legal review  |  Page "), size=8, color=MUTED)
    add_page_number(footer)


def build():
    doc = Document()
    configure(doc)

    if LOGO_PATH.exists():
        p = paragraph(doc, "", align=WD_ALIGN_PARAGRAPH.CENTER, before=4, after=7)
        pic = p.add_run().add_picture(str(LOGO_PATH), width=Inches(0.72))
        pic._inline.docPr.set("descr", "Mivo logo")
        pic._inline.docPr.set("title", "Mivo")

    paragraph(
        doc,
        "STRATEGIC PARTNERSHIP",
        size=10.2,
        color=ORANGE,
        bold=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=4,
        keep=True,
    )
    paragraph(
        doc,
        "Studies Timer × Mivo Scrolling",
        size=23,
        color=BROWN,
        bold=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=4,
        keep=True,
    )
    paragraph(
        doc,
        "Cross-Promotion and Growth Partnership Agreement",
        size=13,
        color=MUTED,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=10,
    )
    rule = paragraph(doc, "", after=11)
    bottom_border(rule)

    notice = paragraph(
        doc,
        "DRAFT FOR REVIEW — Complete each party’s legal entity name and address before signing.",
        size=9.4,
        color=RED,
        bold=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=10,
    )
    notice.paragraph_format.keep_with_next = True

    add_summary_table(doc)
    paragraph(
        doc,
        "Commercial understanding",
        size=13,
        color=BROWN,
        bold=True,
        before=12,
        after=4,
        keep=True,
    )
    clause(
        doc,
        "Studies Timer will pay Mivo Scrolling for the partnership package described below. The parties will work together on audience growth, cross-promotion, product placement, and website improvement while retaining control of their own products, brands, and users.",
    )
    p = paragraph(doc, "", size=9.5, color=CHARCOAL, after=8)
    p.paragraph_format.left_indent = Inches(0.14)
    p.paragraph_format.right_indent = Inches(0.14)
    p_pr = p._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), PALE_BLUE)
    p_pr.append(shd)
    set_run(
        p.add_run(
            "No guaranteed results. References to approximately 500 Mivo users and approximately 24,000 recent Instagram views describe reported audience context only. They are not warranties of future reach, downloads, sales, views, or conversions."
        ),
        size=9.5,
        color=BLUE,
        bold=True,
    )

    doc.add_page_break()
    paragraph(doc, "Partnership Terms", size=19, color=BROWN, bold=True, after=5)
    line = paragraph(doc, "", after=7)
    bottom_border(line, size=7, space=3)

    heading(doc, "1", "Parties")
    clause(
        doc,
        "This Cross-Promotion and Growth Partnership Agreement (the “Agreement”) is entered into by (a) Studies Timer, legal entity name: ______________________________, with an address at ______________________________ (“Studies Timer”), and (b) Mivo Scrolling, legal entity name: ______________________________, with an address at ______________________________ (“Mivo”). Studies Timer and Mivo are each a “Party” and together the “Parties.”",
    )

    heading(doc, "2", "Effective date and term")
    clause(
        doc,
        "The Agreement becomes effective on August 1, 2026 (the “Effective Date”) and continues through January 31, 2027 (the “Initial Term”), unless earlier terminated under this Agreement. Any extension must be in a written amendment signed by both Parties.",
    )

    heading(doc, "3", "Studies Timer payment obligation")
    clause(
        doc,
        "Studies Timer will pay Mivo a $150.00 USD down payment and six monthly payments of $200.00 USD, for a total commitment of $1,350.00 USD. Payments are due according to Exhibit A. The down payment is earned when Mivo begins scheduling, preparing, or placing the partnership deliverables. Monthly payments are contingent on Mivo remaining materially ready and willing to perform its applicable deliverables and on the Parties’ continued compliance with this Agreement.",
    )
    clause(
        doc,
        "Unless otherwise agreed in writing, payments will be made electronically using payment instructions supplied separately by Mivo. Studies Timer is responsible for transaction fees charged by its payment provider. An undisputed payment more than ten calendar days late may pause Mivo’s future deliverables until the account is current.",
    )

    heading(doc, "4", "Mivo promotional deliverables")
    clause(doc, "During the Initial Term, Mivo will provide the following commercially reasonable promotional support:")
    bullet(
        doc,
        "Tech Square opportunity: pursue and coordinate a Studies Timer shoutout or feature through the Tech Square opportunity identified by Mivo. Publication, timing, format, and editorial approval remain controlled by the applicable third party.",
    )
    bullet(
        doc,
        "Young Founders podcast opportunity: pursue and coordinate a Studies Timer shoutout on the Young Founders podcast. Appearance, timing, format, and approval remain subject to the podcast producer or host.",
    )
    bullet(
        doc,
        "Mivo audience shoutout: deliver at least one Studies Timer promotion through a Mivo-controlled channel reasonably capable of reaching Mivo’s user or follower audience.",
    )
    bullet(
        doc,
        "Instagram collaboration: reasonably cooperate on at least one joint Instagram collaboration post, Reel, or equivalent co-branded publication during the Initial Term, with creative and publication timing approved by both Parties.",
    )
    clause(
        doc,
        "Mivo does not breach this Agreement solely because an independent outlet declines, edits, delays, reschedules, or cancels a Tech Square or podcast placement, provided Mivo made timely good-faith efforts and promptly informed Studies Timer.",
    )

    doc.add_page_break()
    heading(doc, "5", "Mutual product and website placement")
    bullet(
        doc,
        "Mivo placement: Mivo will feature or link Studies Timer in a relevant Mivo Focus Mode, focus-resource, partner, or equivalent area selected by Mivo.",
    )
    bullet(
        doc,
        "Studies Timer placement: Studies Timer will feature or link Mivo on its website or product through a visible navigation or resource entry labeled substantially as “Combat Doomscrolling,” linking to https://usemivo.app or another Mivo-approved destination.",
    )
    bullet(
        doc,
        "Timing and continuity: each placement will be implemented within 30 calendar days after the Effective Date and maintained for the rest of the Initial Term, subject to reasonable product changes, maintenance, security, platform policy, and legal requirements.",
    )

    heading(doc, "6", "Studies Timer website-optimization support")
    clause(
        doc,
        "Studies Timer will help Mivo optimize the Mivo website by providing commercially reasonable design, conversion, messaging, usability, or technical recommendations. Unless the Parties agree otherwise in writing, this includes one review session or written review per month and reasonable follow-up clarification. Implementation work beyond recommendations, material development work, paid tools, advertising spend, hosting, or third-party fees requires separate written approval.",
    )

    heading(doc, "7", "Coordination and approvals")
    clause(
        doc,
        "Each Party will designate a contact, provide requested brand assets and approvals within five business days when reasonably possible, and avoid unreasonably delaying agreed deliverables. No public statement may materially misrepresent the other Party’s product, performance, relationship, or endorsement.",
    )

    heading(doc, "8", "Contingency, review, and cure")
    clause(
        doc,
        "The commercial terms are contingent on substantial performance by both Parties. If a Party believes the other has missed a material obligation, it must provide written notice describing the issue. The receiving Party has ten business days to cure or present a reasonable cure plan. During that period, the Parties will continue unaffected obligations where practical.",
    )
    clause(
        doc,
        "If Mivo fails to cure a material missed deliverable, Studies Timer may suspend the next unpaid monthly installment until cure or terminate under Section 14. If Studies Timer fails to cure a payment, placement, cooperation, or optimization obligation, Mivo may suspend unperformed promotional deliverables or terminate under Section 14. Properly earned payments for completed work are not refundable, and no Party may recover speculative audience or revenue losses.",
    )

    doc.add_page_break()
    paragraph(doc, "Brand, Data, and Legal Terms", size=19, color=BROWN, bold=True, after=5)
    line = paragraph(doc, "", after=7)
    bottom_border(line, size=7, space=3)

    heading(doc, "9", "Brand ownership and limited license")
    clause(
        doc,
        "Each Party retains all ownership of its names, logos, trademarks, products, software, content, and other intellectual property. During the Initial Term, each Party grants the other a limited, non-exclusive, non-transferable, revocable license to use approved brand assets only to perform this Agreement. Brand use must follow supplied guidelines and stop promptly after expiration or termination, except for archival records.",
    )

    heading(doc, "10", "Advertising disclosures and lawful content")
    clause(
        doc,
        "Each Party will ensure that paid, sponsored, reciprocal, or otherwise materially connected promotions are truthful, not misleading, and include any clear and conspicuous disclosure required by law or platform policy. The Parties will not make unsupported performance claims or represent the relationship as an endorsement by Tech Square, the Young Founders podcast, Instagram, Apple, or another third party without authorization.",
    )

    heading(doc, "11", "User data and analytics")
    clause(
        doc,
        "Neither Party receives access to the other Party’s user accounts, personal information, private messages, behavioral data, Screen Time data, passwords, or confidential product analytics under this Agreement. The Parties may share aggregate, non-identifying metrics reasonably available for evaluating the partnership, such as link clicks, attributed sign-ups, or campaign reach. Each Party remains responsible for its own privacy notices, consent, security, and data practices.",
    )

    heading(doc, "12", "Confidentiality")
    clause(
        doc,
        "A Party receiving non-public business, technical, financial, product, or campaign information will use it only for this partnership and protect it with reasonable care. Confidential information does not include information that is public through no breach, already lawfully known, independently developed, or lawfully received from a third party. Required legal disclosures are permitted after reasonable advance notice when legally allowed.",
    )

    heading(doc, "13", "Independent contractors; no exclusivity")
    clause(
        doc,
        "The Parties are independent contractors. This Agreement does not create an employment relationship, legal partnership, joint venture, fiduciary duty, agency, franchise, or authority for either Party to bind the other. The arrangement is non-exclusive unless the Parties later agree otherwise in writing.",
    )

    doc.add_page_break()
    heading(doc, "14", "Termination")
    clause(
        doc,
        "Either Party may terminate this Agreement for an uncured material breach after the notice-and-cure process in Section 8. The Parties may also terminate at any time by mutual written agreement. Upon termination, Studies Timer must pay amounts due for periods and deliverables already earned through the termination date. Sections concerning payment obligations already accrued, intellectual property, data, confidentiality, limitations, dispute resolution, and general terms survive.",
    )

    heading(doc, "15", "Disclaimer and limitation")
    clause(
        doc,
        "Except for express obligations in this Agreement, each Party’s products, channels, placements, advice, and services are provided without a guarantee of audience size, publication, platform availability, downloads, users, revenue, rankings, investment, or media coverage. To the maximum extent permitted by law, neither Party is liable to the other for indirect, incidental, special, punitive, or consequential damages, or for lost profits or lost opportunities arising from this Agreement.",
    )

    heading(doc, "16", "General terms")
    clause(
        doc,
        "This Agreement is governed by Georgia law, without regard to conflict-of-law rules. Before filing a claim, the Parties will attempt in good faith for at least ten business days to resolve the dispute informally. This Agreement and its exhibits are the entire understanding on this subject and replace prior discussions. Any amendment or waiver must be in writing and accepted by both Parties. If one provision is unenforceable, the remainder stays effective. Neither Party may assign this Agreement without the other’s written consent, except in connection with a merger, acquisition, or sale of substantially all relevant assets. Notices may be delivered by email to the contacts designated by the Parties. Electronic signatures and counterparts are effective as originals.",
    )

    doc.add_page_break()
    paragraph(doc, "Exhibit A — Payment Schedule", size=19, color=BROWN, bold=True, after=5)
    paragraph(
        doc,
        "Studies Timer pays Mivo Scrolling. The schedule below is part of the Agreement.",
        size=10.2,
        color=MUTED,
        after=9,
    )
    add_payment_schedule(doc)
    paragraph(
        doc,
        "Payment method/instructions: ________________________________________________________________",
        size=9.8,
        before=10,
        after=3,
    )
    paragraph(
        doc,
        "Mivo payment contact: info.mivoapp@gmail.com",
        size=9.8,
        color=MUTED,
        after=10,
    )

    paragraph(doc, "Exhibit B — Delivery Checkpoints", size=16, color=BROWN, bold=True, before=12, after=5)
    checkpoint_table = doc.add_table(rows=0, cols=3)
    header = checkpoint_table.add_row()
    repeat_table_header(header)
    for cell, text in zip(header.cells, ("Checkpoint", "Target timing", "Responsible party")):
        set_cell_shading(cell, BROWN)
        set_cell_margins(cell, top=85, bottom=85)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        set_run(p.add_run(text), size=9.1, color=WHITE, bold=True)
    checkpoints = [
        ("Exchange brand assets and contacts", "Within 5 business days", "Both"),
        ("Launch reciprocal product/site placements", "Within 30 calendar days", "Both"),
        ("Instagram collaboration", "During Initial Term; date jointly approved", "Both"),
        ("Tech Square placement effort", "During Initial Term; third-party timing applies", "Mivo"),
        ("Young Founders podcast placement effort", "During Initial Term; third-party timing applies", "Mivo"),
        ("Mivo-controlled audience shoutout", "During Initial Term", "Mivo"),
        ("Website optimization review", "One per month", "Studies Timer"),
    ]
    for idx, values in enumerate(checkpoints):
        row = checkpoint_table.add_row()
        for cell, text in zip(row.cells, values):
            set_cell_margins(cell, top=85, bottom=85)
            set_cell_shading(cell, CREAM if idx % 2 else WHITE)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = cell.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            set_run(p.add_run(text), size=9.2)
    set_table_geometry(checkpoint_table, [4200, 3000, 2160])
    set_table_borders(checkpoint_table)

    doc.add_page_break()
    paragraph(doc, "Signatures", size=19, color=BROWN, bold=True, after=5)
    line = paragraph(doc, "", after=7)
    bottom_border(line, size=7, space=3)
    clause(
        doc,
        "By signing below, each signer confirms authority to bind the identified organization and accepts this Agreement, including Exhibits A and B.",
        after=8,
    )

    signature_block(
        doc,
        "Hussien Gazouini",
        "CEO and Founder",
        "Studies Timer",
    )
    signature_block(
        doc,
        "Pranshu Raithatha",
        "CEO and Co-Founder",
        "Mivo Scrolling",
    )
    signature_block(
        doc,
        "Harsh Mehta",
        "COO and Co-Founder",
        "Mivo Scrolling",
    )

    paragraph(doc, "Primary contacts", size=13, color=BROWN, bold=True, before=13, after=4)
    paragraph(doc, "Studies Timer email: ______________________________________________", size=9.8, after=3)
    paragraph(doc, "Mivo email: info.mivoapp@gmail.com", size=9.8, after=3)
    paragraph(doc, "Additional notice address: ________________________________________", size=9.8, after=8)

    p = paragraph(doc, "", before=12, after=5)
    bottom_border(p, color=LINE, size=4, space=4)
    paragraph(
        doc,
        "Review note: This draft is a practical business template, not legal or tax advice. The parties should complete their legal entity details and consider review by independent counsel before signing.",
        size=8.6,
        color=MUTED,
        italic=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=0,
    )

    doc.core_properties.title = "Studies Timer and Mivo Scrolling Partnership Agreement"
    doc.core_properties.subject = "Cross-promotion and growth partnership agreement"
    doc.core_properties.author = "Mivo Scrolling"
    doc.core_properties.keywords = "Mivo, Studies Timer, partnership, cross-promotion, growth"
    doc.save(OUTPUT_PATH)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    build()
