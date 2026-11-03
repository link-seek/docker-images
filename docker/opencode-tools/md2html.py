#!/usr/bin/env python3
"""md2html：最小 markdown→HTML（只用标准库，无第三方依赖、无字体需求）。

渲染发生在收件端（Outlook/浏览器自带字体），所以容器侧不需要中文字体、
不需要 pandoc/weasyprint。覆盖日常教程文档子集：
标题(#/##/###)、围栏代码块(```)、表格、引用(>)、无序列表(-/*)、
行内 **加粗**/`代码`/[链接](url)。其余原样成段。

用法：python3 md2html.py <in.md> <out.html>
"""
import html
import re
import sys


def inline(s):
    s = html.escape(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return s


def md_to_body(md):
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("```"):
            lang = ln[3:].strip()
            buf = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append(
                f'<pre><code class="{html.escape(lang)}">'
                + html.escape("\n".join(buf))
                + "</code></pre>"
            )
            continue
        if re.match(r"^#{1,3}\s", ln):
            lvl = len(ln) - len(ln.lstrip("#"))
            out.append(f"<h{lvl}>" + inline(ln.strip("# ").strip()) + f"</h{lvl}>")
            i += 1
            continue
        if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:\-|]+\|$", lines[i + 1]):
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            out.append("<table><tr>" + "".join(f"<th>{inline(c)}</th>" for c in cells) + "</tr>")
            i += 2
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells) + "</tr>")
                i += 1
            out.append("</table>")
            continue
        if ln.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].startswith(">"):
                buf.append(lines[i][1:].lstrip())
                i += 1
            out.append("<blockquote>" + "<br>".join(inline(b) for b in buf) + "</blockquote>")
            continue
        if re.match(r"^[-*]\s", ln):
            out.append("<ul>")
            while i < len(lines) and re.match(r"^[-*]\s", lines[i]):
                out.append("<li>" + inline(lines[i][2:]) + "</li>")
                i += 1
            out.append("</ul>")
            continue
        if ln.strip() == "":
            i += 1
            continue
        out.append("<p>" + inline(ln.strip()) + "</p>")
        i += 1
    return "\n".join(out)


CSS = (
    "pre{background:#f4f4f5;padding:12px;border-radius:6px;overflow-x:auto}"
    "code{font-family:Consolas,Menlo,monospace;font-size:13px}"
    "p code{background:#f4f4f5;padding:1px 5px;border-radius:4px}"
    "table{border-collapse:collapse;width:100%;font-size:14px}"
    "th,td{border:1px solid #d4d4d8;padding:6px 10px;text-align:left}"
    "th{background:#f4f4f5}"
    "blockquote{border-left:4px solid #3b82f6;background:#eff6ff;margin:12px 0;padding:10px 14px}"
    "h1{font-size:22px}h2{font-size:18px;margin-top:28px}"
    "body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;"
    "line-height:1.7;max-width:860px;margin:0 auto;color:#222}"
)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        md = f.read()
    doc = (
        '<html><head><meta charset="utf-8"></head>'
        f'<body><style>{CSS}</style>\n{md_to_body(md)}\n</body></html>'
    )
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(doc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
