#!/data/data/com.termux/files/usr/bin/bash
# music_moment.sh — "该放歌了"的那一刻,放一首（带冷却,别连环放）
#
# 它自己不看耳机状态 —— **什么时候叫它,由你的触发决定**:
#   · 检测到耳机连上时调它
#   · 出门 / 到家 / 睡前定时调它
#   · 或者让 AI 自己判断"这会儿该给她放首歌",然后调它
#
# 放歌动作转给 kugou.sh play(走虚拟副屏,不占屏)。
# 冷却期内(默认 40 分钟)直接退出 —— 防止反复触发把歌切来切去。

COOLDOWN=$(( ${MUSIC_COOLDOWN_MIN:-40} * 60 ))
STATE="$HOME/.claude/listen.last_play"
LOG="$HOME/.claude/listen.log"
NOW=$(date +%s)

if [ -f "$STATE" ]; then
  LAST=$(cat "$STATE" 2>/dev/null || echo 0)
  [ $(( NOW - LAST )) -lt "$COOLDOWN" ] && exit 0
fi

SDIR="$(cd "$(dirname "$0")" && pwd)"
if bash "$SDIR/kugou.sh" play >>"$LOG" 2>&1; then
  echo "$NOW" > "$STATE"
  echo "[$(date '+%m-%d %H:%M')] 放了一首 ✓"
else
  echo "[$(date '+%m-%d %H:%M')] 没放成（副屏起不来）"
  exit 1
fi
