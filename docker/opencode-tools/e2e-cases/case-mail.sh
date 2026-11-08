#!/bin/bash
# CASE-ID: case-mail
# CASE-DESC: 收发信链可用（fetch-mail 真登录 list/unread/show 只读，防 163 Unsafe Login 回归）
# CASE-COST: medium
# CASE-SUGGEST: fetch-mail.py/IMAP 链动了就跑；需 canary 内生产 .env 凭证（SMTP_*/IMAP_*）；只读不断言内容，无模型。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }

# 1) list：覆盖 login→ID→EXAMINE→SEARCH→PEEK 全链（ID 缺失会在 163 上 NO Unsafe Login）
timeout 90 docker exec "$CANARY" fetch-mail list --limit 3 > /tmp/case-mail-list.out 2>/tmp/case-mail-list.err \
  || { echo "FAIL: fetch-mail list 失败（ID/SELECT 回归？）"; cat /tmp/case-mail-list.err 2>/dev/null || true; exit 1; }
grep -q . /tmp/case-mail-list.out \
  || { echo "FAIL: list 输出为空"; exit 1; }
echo "CASE-INFO: list 首行: $(head -n1 /tmp/case-mail-list.out | cut -c1-120)"

# 2) unread：只读复查
timeout 90 docker exec "$CANARY" fetch-mail unread --limit 3 > /tmp/case-mail-unread1.out 2>/tmp/case-mail-unread.err \
  || { echo "FAIL: fetch-mail unread 失败"; cat /tmp/case-mail-unread.err 2>/dev/null || true; exit 1; }

# 3) 只读证明：unread 跑两遍必须完全一致（PEEK+EXAMINE 没打 \Seen）
timeout 90 docker exec "$CANARY" fetch-mail unread --limit 3 > /tmp/case-mail-unread2.out 2>/dev/null \
  || { echo "FAIL: 第二遍 unread 失败"; exit 1; }
cmp -s /tmp/case-mail-unread1.out /tmp/case-mail-unread2.out \
  || { echo "FAIL: 两遍 unread 结果不一致（读操作改了已读状态？）"; exit 1; }

# 4) show：取 list 首个序号全文（PEEK），空邮箱则跳过
if grep -qx '(空)' /tmp/case-mail-list.out; then
  echo "CASE-INFO: 邮箱为空，跳过 show"
else
  UID1="$(head -n1 /tmp/case-mail-list.out | cut -f1)"
  timeout 90 docker exec "$CANARY" fetch-mail show "$UID1" > /tmp/case-mail-show.out 2>/tmp/case-mail-show.err \
    || { echo "FAIL: fetch-mail show $UID1 失败"; cat /tmp/case-mail-show.err 2>/dev/null || true; exit 1; }
  grep -q '^Subject: ' /tmp/case-mail-show.out \
    || { echo "FAIL: show 输出缺 Subject 头"; exit 1; }
  # show 之后未读集合仍不变（三次一致）
  timeout 90 docker exec "$CANARY" fetch-mail unread --limit 3 > /tmp/case-mail-unread3.out 2>/dev/null \
    || { echo "FAIL: 第三遍 unread 失败"; exit 1; }
  cmp -s /tmp/case-mail-unread1.out /tmp/case-mail-unread3.out \
    || { echo "FAIL: show 改了已读状态（非 PEEK？）"; exit 1; }
fi

echo "CASE OK: case-mail（收信链可用且只读）"
