#!/usr/bin/env python3
"""Render docs/DBE-INTEGRATION-PLAN.md as a styled, searchable PDF."""

from __future__ import annotations

import re
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "DBE-INTEGRATION-PLAN.md"
OUTPUT = ROOT / "output" / "pdf" / "DBE-integration-plan.pdf"
NAVY = colors.HexColor("#14233B")
TEAL = colors.HexColor("#00BFA5")
INK = colors.HexColor("#202A37")
MUTED = colors.HexColor("#66758A")
PALE = colors.HexColor("#EAF7F5")


def inline_markup(text: str) -> str:
    result = escape(text)
    result = re.sub(r"`([^`]+)`", r'<font name="Courier" color="#245D71">\1</font>', result)
    result = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", result)
    result = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<link href="\2" color="#087F73">\1</link>', result)
    return result


def make_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle("DBETitle", parent=base["Title"], fontName="Helvetica-Bold", fontSize=24, leading=29, alignment=TA_LEFT, textColor=NAVY, spaceAfter=8),
        "h2": ParagraphStyle("DBEH2", parent=base["Heading2"], fontName="Helvetica-Bold", fontSize=15, leading=19, textColor=NAVY, spaceBefore=12, spaceAfter=6, keepWithNext=True),
        "h3": ParagraphStyle("DBEH3", parent=base["Heading3"], fontName="Helvetica-Bold", fontSize=11, leading=14, textColor=colors.HexColor("#087F73"), spaceBefore=8, spaceAfter=4, keepWithNext=True),
        "body": ParagraphStyle("DBEBody", parent=base["BodyText"], fontName="Helvetica", fontSize=8.9, leading=12.2, textColor=INK, spaceAfter=5, alignment=TA_LEFT),
        "bullet": ParagraphStyle("DBEBullet", parent=base["BodyText"], fontName="Helvetica", fontSize=8.7, leading=11.8, textColor=INK, leftIndent=13, firstLineIndent=-8, bulletIndent=0, spaceAfter=3),
        "meta": ParagraphStyle("DBEMeta", parent=base["BodyText"], fontName="Helvetica", fontSize=8.5, leading=12, textColor=MUTED, spaceAfter=3),
        "callout": ParagraphStyle("DBECallout", parent=base["BodyText"], fontName="Helvetica-Bold", fontSize=9.2, leading=13, textColor=NAVY, backColor=PALE, borderColor=TEAL, borderWidth=0.8, borderPadding=8, spaceBefore=5, spaceAfter=8),
        "code": ParagraphStyle("DBECode", parent=base["Code"], fontName="Courier", fontSize=7.8, leading=10, textColor=INK, leftIndent=12, spaceAfter=5),
    }


def parse_markdown(markdown: str, styles: dict[str, ParagraphStyle]) -> list[object]:
    story: list[object] = []
    in_code = False
    code_lines: list[str] = []
    for raw_line in markdown.splitlines():
        line = raw_line.rstrip()
        if line.startswith("```"):
            if in_code:
                story.append(Paragraph(escape("\n".join(code_lines)).replace("\n", "<br/>"), styles["code"]))
                code_lines = []
            in_code = not in_code
            continue
        if in_code:
            code_lines.append(line)
            continue
        if not line or line == "---":
            continue
        if line.startswith("# "):
            story.append(Paragraph(inline_markup(line[2:]), styles["title"]))
        elif line.startswith("## "):
            story.append(Paragraph(inline_markup(line[3:]), styles["h2"]))
        elif line.startswith("### "):
            story.append(Paragraph(inline_markup(line[4:]), styles["h3"]))
        elif line.startswith("- "):
            story.append(Paragraph("• " + inline_markup(line[2:]), styles["bullet"]))
        elif line.startswith("**") and line.endswith("  "):
            story.append(Paragraph(inline_markup(line), styles["meta"]))
        elif line.startswith("**Nome:**") or line.startswith("**Base de engenharia:**") or line.startswith("**Base de jogo pretendida:**") or line.startswith("**Atualizado:**"):
            story.append(Paragraph(inline_markup(line), styles["meta"]))
        elif line.startswith("**Esta implementação"):
            story.append(Paragraph(inline_markup(line), styles["callout"]))
        else:
            story.append(Paragraph(inline_markup(line), styles["body"]))
    return story


def decorate(canvas, doc) -> None:
    canvas.saveState()
    page_width, page_height = A4
    canvas.setFillColor(NAVY)
    canvas.rect(0, page_height - 5 * mm, page_width, 5 * mm, fill=1, stroke=0)
    canvas.setStrokeColor(colors.HexColor("#D9E2EC"))
    canvas.setLineWidth(0.5)
    canvas.line(18 * mm, 14 * mm, page_width - 18 * mm, 14 * mm)
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(18 * mm, 9.5 * mm, "DBE (Debug Engine) | Plano de integração FNF 0.8.7")
    canvas.drawRightString(page_width - 18 * mm, 9.5 * mm, f"{doc.page}")
    canvas.restoreState()


def main() -> None:
    markdown = SOURCE.read_text(encoding="utf-8")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    page_width, page_height = A4
    doc = BaseDocTemplate(str(OUTPUT), pagesize=A4, title="DBE - Plano de integração FNF 0.8.7", author="DBE project", leftMargin=18 * mm, rightMargin=18 * mm, topMargin=18 * mm, bottomMargin=20 * mm)
    frame = Frame(doc.leftMargin, doc.bottomMargin, page_width - doc.leftMargin - doc.rightMargin, page_height - doc.topMargin - doc.bottomMargin, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=decorate)])
    doc.build(parse_markdown(markdown, make_styles()))
    print(OUTPUT)


if __name__ == "__main__":
    main()
