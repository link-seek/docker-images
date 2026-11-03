#!/usr/bin/env python3
"""md2html：markdown→邮件安全 HTML（烘焙依赖：markdown + premailer，goss 门禁）。

社区标准配方：python-markdown 转 HTML → premailer 内联 CSS。
内联是关键：桌面版 Outlook 会 strip <style> 标签，只有内联样式全客户端兼容。
无 fallback：依赖缺失直接报错，goss 转换冒烟不过则镜像不发版（fail-closed）。

用法：python3 md2html.py <in.md> <out.html>
"""
import sys

import markdown
from premailer import transform

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
    body = markdown.markdown(md, extensions=["tables", "fenced_code"])
    doc = (
        '<html><head><meta charset="utf-8">'
        f"<style>{CSS}</style></head><body>{body}</body></html>"
    )
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(transform(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
