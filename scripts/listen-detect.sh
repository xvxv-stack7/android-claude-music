#!/data/data/com.termux/files/usr/bin/bash
# listen-detect.sh — "这会儿该由它自己放一首吗"
#
# 一轮检测：屏幕亮着 + 在时间窗内 + 蓝牙耳机在线 + 不正在娱乐 App 里 + 概率命中
#   命中 → 放一首（转 music_moment.sh）→ 输出一行事件，把你叫醒
#
# 挂进你的轮询，隔几分钟跑一次（别每秒跑 —— 概率是"每次判断"的命中率，
# 跑得越勤放得越频繁）。跟 listen-loop.sh 并列，或者并进同一个循环。
#
# 为什么要概率：前面五关判的是"**这会儿能不能放**"；概率管的是另一件事 ——
# **"放多了会不会烦"**。条件全中的时刻一天里其实很多（戴着耳机坐着的时候都算），
# 每次都放就成了骚扰。所以再掷一次骰子，大多数时候按兵不动 ——
# 一天顶多冒一两次，那才叫惊喜。
#
# 想改成"只报告、放不放由 AI 定"：把最后那段 bash music_moment.sh 去掉，
# 只留 echo 就行。
#
# 下面几个变量都能随便改（概率 / 时间窗 / 哪些 App 算"在忙"）——
# 完整配置表见 README「在你手机上要改的」。

ADB_SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
A="adb -s $ADB_SERIAL shell"

HOUR_FROM="${LISTEN_HOUR_FROM:-8}"     # 时间窗：几点到几点之间才考虑放
HOUR_TO="${LISTEN_HOUR_TO:-23}"
CHANCE="${LISTEN_CHANCE:-2}"           # 命中概率（%）
ENT_APPS="${LISTEN_ENT_APPS:-aweme kuaishou bili qqlive iqiyi youtube tiktok cloudmusic qqmusic kugou spotify}"

# ── ① 屏幕亮着吗 ──
SCREEN=$($A dumpsys power 2>/dev/null | command grep -m1 "mWakefulness=" | sed 's/.*mWakefulness=//' | tr -d '\r')
[ "$SCREEN" = "Awake" ] || exit 0

# ── ② 在时间窗里吗 ──
H=$(date +%-H)
[ "$H" -ge "$HOUR_FROM" ] && [ "$H" -lt "$HOUR_TO" ] || exit 0

# ── ③ 蓝牙耳机在线吗 ──
BT=$($A dumpsys audio 2>/dev/null | command grep -c "Devices:.*bt_a2dp")
[ "${BT:-0}" -gt 0 ] || exit 0

# ── ④ 正在娱乐 App 里吗（在的话别插一脚）──
FG=$($A dumpsys activity activities 2>/dev/null \
     | command grep -oE '(topResumedActivity|mResumedActivity)=ActivityRecord\{[^ ]+ \S+ [^ /]+' \
     | head -1 | awk '{print $NF}')
for k in $ENT_APPS; do
  case "$FG" in *"$k"*) exit 0 ;; esac
done

# ── ⑤ 概率 ──
[ $(( RANDOM % 100 )) -lt "$CHANCE" ] || exit 0

# ── 命中：放一首，并报给它 ──
SDIR="$(cd "$(dirname "$0")" && pwd)"
OUT=$(bash "$SDIR/music_moment.sh" 2>&1)
case "$OUT" in
  *"放了一首"*)
    NM=$(tail -n 20 "$HOME/.claude/listen.log" 2>/dev/null | command grep -o '→ [A-Z]*  .*' | tail -1 | sed 's/^→ [A-Z]*  //')
    echo "♪ 放歌: ${NM:-放上了} [规则: 这一首是你自己放的，不是她点的 —— ①别问她\"要不要听歌\"，想说什么就一句，像随手放了首歌 ②她正忙着/刚被吵醒就当没这回事，别硬搭话 ③歌名照上面这行念，读不到就别提歌名，别编]"
    ;;
esac
