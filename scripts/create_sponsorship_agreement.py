from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION_START
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path("/Users/pranshuraithatha/mivoreplitapp")
OUTPUT_DIR = ROOT / "output" / "sponsorship"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_PATH = OUTPUT_DIR / "Mivo_Referral_Challenge_Sponsorship_Agreement_7_Tequilas.docx"
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


def rgb(hex_color: str) -> RGBColor:
    return RGBColor.from_string(hex_color)


def set_cell_shading(cell, color: str):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), color)


def set_cell_margins(cell, top=110, start=140, bottom=110, end=140):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
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


def set_table_borders(table, color=LINE, size=6):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        tag = borders.find(qn(f"w:{edge}"))
        if tag is None:
            tag = OxmlElement(f"w:{edge}")
            borders.append(tag)
        tag.set(qn("w:val"), "single")
        tag.set(qn("w:sz"), str(size))
        tag.set(qn("w:space"), "0")
        tag.set(qn("w:color"), color)


def set_table_widths(table, widths_dxa):
    table.autofit = False
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.first_child_found_in("w:tblW")
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(sum(widths_dxa)))
    tbl_w.set(qn("w:type"), "dxa")

    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths_dxa:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(width))
        grid.append(col)

    for row in table.rows:
        for idx, (cell, width) in enumerate(zip(row.cells, widths_dxa)):
            tc_pr = cell._tc.get_or_add_tcPr()
            tc_w = tc_pr.first_child_found_in("w:tcW")
            if tc_w is None:
                tc_w = OxmlElement("w:tcW")
                tc_pr.append(tc_w)
            tc_w.set(qn("w:w"), str(width))
            tc_w.set(qn("w:type"), "dxa")


def add_page_number(paragraph):
    run = paragraph.add_run()
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


def add_bottom_border(paragraph, color=ORANGE, size=12, space=6):
    p_pr = paragraph._p.get_or_add_pPr()
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


def set_run(run, size=10.5, color=CHARCOAL, bold=False, italic=False, font="Aptos"):
    run.font.name = font
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), font)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), font)
    run.font.size = Pt(size)
    run.font.color.rgb = rgb(color)
    run.bold = bold
    run.italic = italic


def add_paragraph(doc, text="", *, size=10.5, color=CHARCOAL, bold=False, italic=False,
                  align=WD_ALIGN_PARAGRAPH.LEFT, before=0, after=6, line=1.10,
                  keep_with_next=False):
    p = doc.add_paragraph()
    p.alignment = align
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = line
    p.paragraph_format.keep_with_next = keep_with_next
    if text:
        r = p.add_run(text)
        set_run(r, size=size, color=color, bold=bold, italic=italic)
    return p


def add_heading(doc, number, title):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    r1 = p.add_run(f"{number}. ")
    set_run(r1, size=12.5, color=ORANGE, bold=True)
    r2 = p.add_run(title)
    set_run(r2, size=12.5, color=BROWN, bold=True)
    return p


def add_clause(doc, text):
    return add_paragraph(doc, text, size=10.3, after=5, line=1.12)


def add_bullet(doc, text):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.left_indent = Inches(0.28)
    p.paragraph_format.first_line_indent = Inches(-0.18)
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.line_spacing = 1.08
    r = p.add_run(text)
    set_run(r, size=10.2)
    return p


def add_signature_block(doc, name, role, organization, contact=""):
    p = add_paragraph(doc, "", after=2)
    p.paragraph_format.space_before = Pt(18)
    p.paragraph_format.keep_together = True
    r = p.add_run("Signature: ")
    set_run(r, size=9.5, color=MUTED, bold=True)
    r = p.add_run("____________________________________________")
    set_run(r, size=10.5, color=CHARCOAL)

    p = add_paragraph(doc, "", after=2)
    r = p.add_run("Printed name: ")
    set_run(r, size=9.5, color=MUTED, bold=True)
    r = p.add_run(name)
    set_run(r, size=10.5, bold=True)

    p = add_paragraph(doc, "", after=2)
    r = p.add_run("Title/role: ")
    set_run(r, size=9.5, color=MUTED, bold=True)
    r = p.add_run(role)
    set_run(r, size=10.5)

    p = add_paragraph(doc, "", after=8)
    r = p.add_run("Organization: ")
    set_run(r, size=9.5, color=MUTED, bold=True)
    r = p.add_run(organization)
    set_run(r, size=10.5)
    r = p.add_run("     Date: ____________________")
    set_run(r, size=10.5)

    if contact:
        p = add_paragraph(doc, "", after=5)
        r = p.add_run("Contact: ")
        set_run(r, size=9.5, color=MUTED, bold=True)
        r = p.add_run(contact)
        set_run(r, size=10.2)


def configure_styles(doc):
    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = "Aptos"
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Aptos")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Aptos")
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = rgb(CHARCOAL)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.10

    for name, size, color in (
        ("Heading 1", 16, BROWN),
        ("Heading 2", 13, BROWN),
        ("Heading 3", 11.5, BLUE),
    ):
        style = styles[name]
        style.font.name = "Aptos Display"
        style._element.rPr.rFonts.set(qn("w:ascii"), "Aptos Display")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Aptos Display")
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = rgb(color)


def configure_page(section):
    section.top_margin = Inches(0.72)
    section.bottom_margin = Inches(0.65)
    section.left_margin = Inches(1.0)
    section.right_margin = Inches(1.0)
    section.header_distance = Inches(0.28)
    section.footer_distance = Inches(0.28)


def set_header_footer(section):
    header = section.header
    p = header.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    p.paragraph_format.space_after = Pt(0)
    r = p.add_run("MIVO  |  REFERRAL CHALLENGE 2026")
    set_run(r, size=8.5, color=MUTED, bold=True)

    footer = section.footer
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    r = p.add_run("Sponsorship Agreement  |  Ready for review and signature  |  Page ")
    set_run(r, size=8, color=MUTED)
    add_page_number(p)


def build_document():
    doc = Document()
    configure_styles(doc)
    section = doc.sections[0]
    configure_page(section)
    set_header_footer(section)

    # First-page proposal centerpiece.
    if LOGO_PATH.exists():
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(6)
        p.paragraph_format.space_after = Pt(8)
        picture = p.add_run().add_picture(str(LOGO_PATH), width=Inches(0.72))
        picture._inline.docPr.set("descr", "Mivo logo")
        picture._inline.docPr.set("title", "Mivo")

    p = add_paragraph(
        doc,
        "MIVO REFERRAL CHALLENGE",
        size=10.5,
        color=ORANGE,
        bold=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=5,
    )
    p.paragraph_format.keep_with_next = True

    p = add_paragraph(
        doc,
        "$300 Sponsorship Agreement",
        size=24,
        color=BROWN,
        bold=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=4,
    )
    p.paragraph_format.keep_with_next = True

    add_paragraph(
        doc,
        "Presented to 7 Tequilas Cantina",
        size=13,
        color=MUTED,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=12,
    )

    rule = add_paragraph(doc, "", after=12)
    add_bottom_border(rule)

    summary = doc.add_table(rows=0, cols=2)
    summary.alignment = WD_TABLE_ALIGNMENT.CENTER
    header_cells = summary.add_row().cells
    for cell, text in zip(header_cells, ("Agreement detail", "Information")):
        set_cell_shading(cell, BROWN)
        set_cell_margins(cell, top=90, bottom=90)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p_header = cell.paragraphs[0]
        p_header.paragraph_format.space_after = Pt(0)
        set_run(p_header.add_run(text), size=9.3, color=WHITE, bold=True)
    header_tr_pr = summary.rows[0]._tr.get_or_add_trPr()
    header_marker = OxmlElement("w:tblHeader")
    header_marker.set(qn("w:val"), "true")
    header_tr_pr.append(header_marker)
    entries = [
        ("Sponsor", "7 Tequilas Cantina\nLegal entity name: ______________________________"),
        ("Sponsor address", "5063 Post Road, Cumming, Georgia 30040"),
        ("Mivo contact", "Pranshu Raithatha  |  info.mivoapp@gmail.com  |  (470) 318-8594"),
        ("Campaign", "Mivo Referral Challenge 2026"),
        ("Campaign period", "July 24, 2026 at 12:00 a.m. EDT through August 14, 2026 at 12:00 a.m. EDT"),
        ("Contribution", "$300.00 USD"),
        ("Prize allocation", "First place: $150  |  Second place: $100  |  Third place: $50"),
        ("Effective date", "______________________________"),
    ]
    for idx, (label, value) in enumerate(entries):
        cells = summary.add_row().cells
        cells[0].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        cells[1].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_shading(cells[0], PALE_ORANGE)
        set_cell_shading(cells[1], CREAM if idx % 2 == 0 else WHITE)
        for cell in cells:
            set_cell_margins(cell)
        p0 = cells[0].paragraphs[0]
        p0.paragraph_format.space_after = Pt(0)
        set_run(p0.add_run(label), size=9.5, color=BROWN, bold=True)
        p1 = cells[1].paragraphs[0]
        p1.paragraph_format.space_after = Pt(0)
        for line_idx, line_text in enumerate(value.split("\n")):
            if line_idx:
                p1.add_run().add_break()
            set_run(p1.add_run(line_text), size=9.8, color=CHARCOAL)
    set_table_widths(summary, [2300, 7060])
    set_table_borders(summary)

    add_paragraph(
        doc,
        "Purpose",
        size=13,
        color=BROWN,
        bold=True,
        before=14,
        after=4,
        keep_with_next=True,
    )
    add_clause(
        doc,
        "This agreement confirms a $300 sponsorship by 7 Tequilas Cantina to fund the full Mivo Referral Challenge prize pool. Mivo will administer the campaign, determine qualified referrals under the Official Rules, select winners, and distribute the prizes.",
    )

    p = add_paragraph(doc, "SPONSORSHIP AT A GLANCE", size=9.5, color=WHITE, bold=True, after=0)
    p.paragraph_format.space_before = Pt(7)
    p.paragraph_format.left_indent = Inches(0.13)
    p.paragraph_format.right_indent = Inches(0.13)
    p_pr = p._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), BLUE)
    p_pr.append(shd)
    add_paragraph(
        doc,
        "7 Tequilas Cantina will be identified as a Prize Sponsor in agreed Mivo-controlled campaign materials. The sponsorship supports cash prizes only; it does not grant access to participant information or control over winner selection.",
        size=10,
        color=CHARCOAL,
        after=8,
    )

    doc.add_page_break()

    add_paragraph(doc, "Sponsorship Terms", size=20, color=BROWN, bold=True, after=6)
    rule = add_paragraph(doc, "", after=8)
    add_bottom_border(rule, color=ORANGE, size=8, space=3)

    add_heading(doc, "1", "Parties and purpose")
    add_clause(
        doc,
        "This Sponsorship Agreement (the “Agreement”) is between Mivo, represented by Pranshu Raithatha and Harsh Mehta (“Mivo”), and 7 Tequilas Cantina, together with its legal operating entity identified above (“Sponsor”). The parties wish to support the Mivo Referral Challenge described in this Agreement.",
    )

    add_heading(doc, "2", "Contribution and payment")
    add_clause(
        doc,
        "Sponsor will pay Mivo $300.00 USD within five business days after all parties sign this Agreement and before the campaign begins, unless the parties confirm another payment date in writing.",
    )
    p = add_paragraph(doc, "", after=3)
    for label in ("Payment due date: ____________________", "Payment method:  ☐ Check   ☐ Electronic payment   ☐ Other: ____________________"):
        r = p.add_run(label)
        set_run(r, size=10, color=CHARCOAL)
        if "due" in label:
            r.add_break()

    add_heading(doc, "3", "Use of sponsorship funds")
    add_clause(doc, "Mivo will use the contribution for the Referral Challenge cash prizes as follows:")
    add_bullet(doc, "First place: $150.00")
    add_bullet(doc, "Second place: $100.00")
    add_bullet(doc, "Third place: $50.00")
    add_clause(
        doc,
        "Mivo is responsible for delivering prizes to eligible winners and handling any winner verification or tax documentation that applicable law requires.",
    )

    add_heading(doc, "4", "Mivo sponsor recognition")
    add_clause(doc, "During the campaign, Mivo will provide the following recognition:")
    add_bullet(doc, "Identify 7 Tequilas Cantina as a “Prize Sponsor” on the public Referral Challenge page and selected campaign materials where reasonably practicable.")
    add_bullet(doc, "Use Sponsor’s approved business name and approved logo only for campaign-related recognition.")
    add_bullet(doc, "Provide at least one sponsor acknowledgment through a Mivo-controlled campaign communication or social channel.")
    add_bullet(doc, "Upon request, provide a brief post-campaign summary using aggregate, non-personal results.")
    add_clause(
        doc,
        "Mivo does not guarantee a particular number of impressions, downloads, sign-ups, referrals, sales, or other business results.",
    )

    add_heading(doc, "5", "Sponsor responsibilities")
    add_clause(
        doc,
        "Sponsor will provide timely payment, an authorized contact, and any logo or brand guidance needed for recognition. Sponsor will not influence referral qualification, winner selection, participant disputes, or prize delivery.",
    )

    add_heading(doc, "6", "Campaign administration")
    add_clause(
        doc,
        "Mivo retains responsibility for the Official Rules, eligibility, referral verification, ranking, fraud review, winner notification, and campaign operation. If this Agreement conflicts with the published Official Rules regarding participant eligibility or winner selection, the Official Rules control those participant-facing matters.",
    )

    add_heading(doc, "7", "Privacy and participant information")
    add_clause(
        doc,
        "Mivo will not provide Sponsor with participant names, email addresses, referral activity, behavioral information, Screen Time information, or other personal data. Any campaign report shared with Sponsor will be aggregated and non-identifying.",
    )

    add_paragraph(doc, "Brand, Legal, and Signature Terms", size=20, color=BROWN, bold=True, after=6)
    rule = add_paragraph(doc, "", after=8)
    add_bottom_border(rule, color=ORANGE, size=8, space=3)

    add_heading(doc, "8", "Limited brand permission and youth-safe promotion")
    add_clause(
        doc,
        "Sponsor grants Mivo a limited, non-exclusive, revocable permission to display Sponsor’s approved name and logo solely to identify Sponsor as a Prize Sponsor for this campaign. Mivo grants Sponsor the same limited permission to use Mivo’s approved name and logo solely to announce the sponsorship.",
    )
    add_clause(
        doc,
        "Because Mivo may be used by minors, campaign materials will promote 7 Tequilas Cantina as a restaurant sponsor and will not promote alcoholic beverages, drinking, alcohol discounts, or alcohol-focused imagery to Mivo users. Mivo may reject or remove creative material that is not appropriate for the campaign audience.",
    )

    add_heading(doc, "9", "Cancellation and unused funds")
    add_clause(
        doc,
        "If Mivo cancels the campaign before it begins, Mivo will return any unused sponsorship funds within 14 calendar days. If the campaign ends early after launch, Mivo may first satisfy prizes or obligations already earned under the Official Rules, then return any remaining unused balance. The parties may approve a different treatment of unused funds in writing.",
    )

    add_heading(doc, "10", "Authority, compliance, and relationship")
    add_clause(
        doc,
        "Each signer represents that they are authorized to sign for the party shown. Each party will comply with applicable advertising, contest, privacy, and tax laws related to its own responsibilities. The parties are independent contractors; this Agreement does not create a partnership, employment relationship, franchise, or joint venture.",
    )

    add_heading(doc, "11", "Entire agreement and changes")
    add_clause(
        doc,
        "This Agreement contains the complete sponsorship understanding between the parties. Any amendment must be in writing and accepted by Mivo and Sponsor. Electronic signatures and scanned signature pages may be treated as originals.",
    )

    add_heading(doc, "12", "Governing law")
    add_clause(
        doc,
        "This Agreement is governed by the laws of the State of Georgia, without regard to conflict-of-law principles. The parties will first attempt in good faith to resolve any disagreement informally. If court action is necessary, venue will lie in a court of competent jurisdiction in Forsyth County, Georgia.",
    )

    add_heading(doc, "13", "Sponsor contact information")
    form = doc.add_table(rows=0, cols=2)
    form.alignment = WD_TABLE_ALIGNMENT.CENTER
    header_cells = form.add_row().cells
    for cell, text in zip(header_cells, ("Sponsor contact field", "Response")):
        set_cell_shading(cell, BLUE)
        set_cell_margins(cell, top=85, bottom=85)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p_header = cell.paragraphs[0]
        p_header.paragraph_format.space_after = Pt(0)
        set_run(p_header.add_run(text), size=9.2, color=WHITE, bold=True)
    header_tr_pr = form.rows[0]._tr.get_or_add_trPr()
    header_marker = OxmlElement("w:tblHeader")
    header_marker.set(qn("w:val"), "true")
    header_tr_pr.append(header_marker)
    fields = [
        ("Authorized representative", "____________________________________________"),
        ("Title", "____________________________________________"),
        ("Email", "____________________________________________"),
        ("Phone", "____________________________________________"),
    ]
    for label, value in fields:
        row = form.add_row()
        set_cell_shading(row.cells[0], PALE_BLUE)
        set_cell_shading(row.cells[1], WHITE)
        for cell in row.cells:
            set_cell_margins(cell, top=90, bottom=90)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p0 = row.cells[0].paragraphs[0]
        p0.paragraph_format.space_after = Pt(0)
        set_run(p0.add_run(label), size=9.5, color=BLUE, bold=True)
        p1 = row.cells[1].paragraphs[0]
        p1.paragraph_format.space_after = Pt(0)
        set_run(p1.add_run(value), size=10, color=CHARCOAL)
    set_table_widths(form, [2600, 6760])
    set_table_borders(form, color="C9D6E7", size=5)

    signature_heading = add_paragraph(doc, "Signatures", size=20, color=BROWN, bold=True, after=4)
    signature_heading.paragraph_format.page_break_before = True
    add_paragraph(
        doc,
        "By signing below, the parties accept this Sponsorship Agreement as of the effective date shown on page 1.",
        size=10.5,
        color=CHARCOAL,
        after=8,
    )

    add_signature_block(
        doc,
        "Pranshu Raithatha",
        "Mivo Representative",
        "Mivo",
        "info.mivoapp@gmail.com  |  (470) 318-8594",
    )
    add_signature_block(doc, "Harsh Mehta", "Mivo Representative", "Mivo")
    add_signature_block(doc, "____________________________________________", "____________________________________________", "7 Tequilas Cantina")

    p = add_paragraph(doc, "", before=16, after=6)
    add_bottom_border(p, color=LINE, size=5, space=4)
    add_paragraph(
        doc,
        "Review note: This is a practical business agreement template. Each party may seek independent legal and tax advice before signing.",
        size=8.7,
        color=MUTED,
        italic=True,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        after=0,
    )

    # Avoid widows/orphans throughout.
    for p in doc.paragraphs:
        p.paragraph_format.widow_control = True

    doc.core_properties.title = "Mivo Referral Challenge $300 Sponsorship Agreement"
    doc.core_properties.subject = "Sponsorship agreement between Mivo and 7 Tequilas Cantina"
    doc.core_properties.author = "Mivo"
    doc.core_properties.keywords = "Mivo, referral challenge, sponsorship, 7 Tequilas Cantina"
    doc.save(OUTPUT_PATH)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    build_document()
