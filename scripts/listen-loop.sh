#!/data/data/com.termux/files/usr/bin/bash
# listen-loop.sh — "一起听"的轮询
#
# 隔一段【随机】时间瞟一眼你此刻正唱到哪句,把这一行递出去。
# 脚本只递话,不判断 —— 接不接、聊什么,是 AI 自己的事(规则随行到它眼前)。
#
# 三种用法:
#   ① 直接跑(看效果):      bash listen-loop.sh
#   ② 挂成常驻监听:        你的 Agent 若支持"外部输入即唤醒",把它挂上去
#   ③ 抄进已有的轮询:      把下面的 while 段整段搬进你那个常驻循环里
#      (跟别的检查共用一条循环,比单开一个省事,也不会互相顶掉)
#
# 调参在下面三行 —— 为什么是这三个数,见 README「第三层」。

GAP_MIN=30        # 两次之间最少隔几秒
GAP_MAX=80        # 最多隔几秒(随机取,不要固定间隔)
MAX_PER_SONG=2    # 同一首歌最多递几句(多了吵)

SDIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.claude/listen.state"     # 格式: 歌名|本首已递次数

while true; do
  LP=$(python3 "$SDIR/lyric_now.py" --auto 2>/dev/null)
  if [ -n "$LP" ]; then
    # 取歌名,按歌计数(换歌归零)
    T=$(printf '%s' "$LP" | sed -n 's/^《\([^》]*\)》.*/\1/p')
    if [ -n "$T" ]; then
      st_t=""; st_c=0
      IFS='|' read -r st_t st_c _ < "$STATE" 2>/dev/null || true
      [ "$T" != "$st_t" ] && st_c=0
      if [ "${st_c:-0}" -lt "$MAX_PER_SONG" ]; then
        printf '%s|%s\n' "$T" $(( ${st_c:-0} + 1 )) > "$STATE" 2>/dev/null
        echo "♪ 歌词: $LP [规则: 有意思就接一句聊，没感觉就放着不吭声；一首歌最多 $MAX_PER_SONG 句]"
      fi
    fi
  fi
  sleep $(( RANDOM % (GAP_MAX - GAP_MIN + 1) + GAP_MIN ))
done
