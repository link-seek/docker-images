#!/usr/bin/env python3
# fetch-mail：IMAP 只读薄客户端（标准库 imaplib，无额外依赖）。
# 配置全走环境变量（不进镜像），缺配即报错说明缺哪个变量：
#   IMAP_HOST（默认 imap.163.com） IMAP_PORT（默认 993，SSL 隐式）
#   IMAP_USER（缺省回落 SMTP_USER） IMAP_PASS（缺省回落 SMTP_PASS，163 收发共用同一授权码）
#   IMAP_FOLDER（默认 INBOX）
# 用法：
#   fetch-mail --help
#   fetch-mail list [--limit N] [--folder F] [--unseen]
#   fetch-mail unread [--limit N] [--folder F]
#   fetch-mail show <uid> [--folder F]
# 只读：EXAMINE 打开邮箱，不改已读状态；不删信、不标记。
import argparse
import email
import email.header
import email.utils
import imaplib
import os
import socket
import sys


def env(name, default=""):
    v = os.environ.get(name, "")
    return v if v != "" else default


def resolve_creds():
    host = env("IMAP_HOST", "imap.163.com")
    port_s = env("IMAP_PORT", "993")
    user = env("IMAP_USER", "") or env("SMTP_USER", "")
    pw = env("IMAP_PASS", "") or env("SMTP_PASS", "")
    folder = env("IMAP_FOLDER", "INBOX")
    missing = []
    if not host:
        missing.append("IMAP_HOST")
    if not user:
        missing.append("IMAP_USER(可复用SMTP_USER)")
    if not pw:
        missing.append("IMAP_PASS(可复用SMTP_PASS)")
    try:
        port = int(port_s)
    except ValueError:
        print(f"fetch-mail: IMAP_PORT 非法: {port_s!r}", file=sys.stderr)
        sys.exit(2)
    if missing:
        print(f"fetch-mail: 缺少邮件配置:{' '.join(missing)}（检查 compose .env，容器需重建/重启生效）", file=sys.stderr)
        sys.exit(2)
    return host, port, user, pw, folder


def decode_hdr(msg, name, default=""):
    v = msg.get(name, default)
    if v is None:
        return default
    parts = []
    try:
        for text, charset in email.header.decode_header(v):
            if isinstance(text, bytes):
                parts.append(text.decode(charset or "utf-8", errors="replace"))
            else:
                parts.append(text)
    except Exception:
        return str(v)
    return "".join(parts)


def connect(host, port, user, pw):
    try:
        m = imaplib.IMAP4_SSL(host, port, timeout=15)
    except (socket.timeout, TimeoutError):
        print(f"fetch-mail: 连接超时 {host}:{port}（15s）", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"fetch-mail: 连接失败 {host}:{port}: {e}", file=sys.stderr)
        sys.exit(1)
    try:
        m.login(user, pw)
    except imaplib.IMAP4.error as e:
        print(f"fetch-mail: 登录失败 {user}@{host}（检查授权码是否为客户端授权密码）: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"fetch-mail: 登录异常: {e}", file=sys.stderr)
        sys.exit(1)
    return m


def pick_uids(m, folder, unseen, limit):
    typ, _ = m.select(folder, readonly=True)
    if typ != "OK":
        # 163 文件夹名大小写敏感，INBOX 以外按原样试一次
        print(f"fetch-mail: 打开邮箱失败: {folder}", file=sys.stderr)
        sys.exit(1)
    crit = "UNSEEN" if unseen else "ALL"
    typ, data = m.search(None, crit)
    if typ != "OK":
        print("fetch-mail: 检索失败", file=sys.stderr)
        sys.exit(1)
    nums = data[0].split() if data and data[0] else []
    return nums[-limit:] if limit > 0 else nums


def cmd_list(args):
    host, port, user, pw, def_folder = resolve_creds()
    folder = args.folder or def_folder
    m = connect(host, port, user, pw)
    try:
        nums = pick_uids(m, folder, args.unseen, args.limit)
        if not nums:
            print("(空)")
            return
        for n in nums:
            typ, data = m.fetch(n, "(UID RFC822.HEADER)")
            if typ != "OK" or not data or not data[0]:
                continue
            raw = data[0][1] if isinstance(data[0], tuple) else data[0]
            msg = email.message_from_bytes(raw)
            uid = n.decode() if isinstance(n, bytes) else str(n)
            frm = decode_hdr(msg, "From")
            subj = decode_hdr(msg, "Subject")
            date = decode_hdr(msg, "Date")
            print(f"{uid}\t{date}\t{frm}\t{subj}")
    finally:
        try:
            m.logout()
        except Exception:
            pass


def cmd_show(args):
    host, port, user, pw, def_folder = resolve_creds()
    folder = args.folder or def_folder
    m = connect(host, port, user, pw)
    try:
        typ, _ = m.select(folder, readonly=True)
        if typ != "OK":
            print(f"fetch-mail: 打开邮箱失败: {folder}", file=sys.stderr)
            sys.exit(1)
        typ, data = m.fetch(args.uid.encode() if isinstance(args.uid, str) else args.uid, "(RFC822)")
        if typ != "OK" or not data or not data[0]:
            print(f"fetch-mail: 取信失败: {args.uid}", file=sys.stderr)
            sys.exit(1)
        raw = data[0][1] if isinstance(data[0], tuple) else data[0]
        msg = email.message_from_bytes(raw)
        print(f"From: {decode_hdr(msg, 'From')}")
        print(f"To: {decode_hdr(msg, 'To')}")
        print(f"Date: {decode_hdr(msg, 'Date')}")
        print(f"Subject: {decode_hdr(msg, 'Subject')}")
        print()
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_maintype() == "multipart":
                    continue
                ctype = part.get_content_type()
                if ctype != "text/plain":
                    continue
                try:
                    payload = part.get_payload(decode=True) or b""
                    body = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
                    break
                except Exception:
                    continue
        else:
            try:
                payload = msg.get_payload(decode=True)
                if isinstance(payload, bytes):
                    body = payload.decode(msg.get_content_charset() or "utf-8", errors="replace")
                else:
                    body = str(payload or "")
            except Exception:
                body = ""
        if len(body) > 8000:
            body = body[:8000] + "\n…(截断 8000 字)"
        print(body if body else "(无文本正文)")
    finally:
        try:
            m.logout()
        except Exception:
            pass


def main():
    p = argparse.ArgumentParser(prog="fetch-mail", description="IMAP 只读取信（EXAMINE，不改已读；配置走 IMAP_*，缺省回落 SMTP_*）")
    p.add_argument("--folder", default="", help="邮箱文件夹（默认 $IMAP_FOLDER 或 INBOX）")
    sub = p.add_subparsers(dest="cmd")
    pl = sub.add_parser("list", help="列出邮件（UID/日期/发件人/主题）")
    pl.add_argument("--limit", type=int, default=10)
    pl.add_argument("--unseen", action="store_true")
    pl.add_argument("--folder", default="")
    pu = sub.add_parser("unread", help="只列未读（list --unseen 的别名）")
    pu.add_argument("--limit", type=int, default=10)
    pu.add_argument("--folder", default="")
    ps = sub.add_parser("show", help="看一封全文（只读）")
    ps.add_argument("uid", help="list 第一列的序号")
    ps.add_argument("--folder", default="")
    args = p.parse_args()
    if args.cmd in ("list", "unread"):
        if args.cmd == "unread":
            args.unseen = True
        cmd_list(args)
    elif args.cmd == "show":
        cmd_show(args)
    else:
        p.print_help()
        sys.exit(0)


if __name__ == "__main__":
    main()
