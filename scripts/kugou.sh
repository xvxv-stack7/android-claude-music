#!/data/data/com.termux/files/usr/bin/bash
# kugou.sh — 读你的歌单 / 在【虚拟副屏】上放歌(不占你的屏)
#
# 依赖:本机音乐接口服务(~/kugou-music-api, 127.0.0.1:4000) 已登录你自己的账号
# 配置:见 ~/.claude/scripts/music.env(照 music.env.example 填)
#
# 用法:
#   kugou.sh list [页] [数量]   列"我喜欢"收藏
#   kugou.sh play               起副屏 → 把 App 丢进去 → 发播放/暂停键（不碰主屏）
#   kugou.sh stop               听完了收副屏
set -u

SDIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SDIR/music.env" ] && . "$SDIR/music.env"
API="${MUSIC_API:-http://127.0.0.1:4000}"
LIKE_ID="${MUSIC_LIKE_ID:-}"
MUSIC_PKG="${MUSIC_PKG:-com.kugou.android}"
SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
ADB="adb -s $SERIAL"
VD="$SDIR/vd.sh"

case "${1:-list}" in
  # ── 列出"我喜欢"收藏 ──
  list)
    [ -z "$LIKE_ID" ] && { echo "先配 MUSIC_LIKE_ID（见 TUTORIAL 第四步）"; exit 1; }
    page="${2:-1}"; pagesize="${3:-100}"
    curl -s -m 25 "$API/playlist/track/all?id=$LIKE_ID&page=$page&pagesize=$pagesize" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if d.get('status')!=1:
        print('[音乐] 读收藏失败 err',d.get('error_code'),str(d.get('data'))[:60]);sys.exit()
    st=(d.get('data') or {}).get('songs') or []
    if not st: print('收藏为空');sys.exit()
    print('「我喜欢」共 %s 首:'%len(st))
    for i,s in enumerate(st,1):
        nm=(s.get('audio_name') or s.get('filename') or s.get('name') or '?')
        print('  %s. %s'%(i,nm))
except Exception as e:
    print('[音乐] 解析失败',e)
"
    ;;

  # ── 发播放/暂停键给【虚拟副屏】上的 App（不占你的屏）──
  # 铁律:绝不 am start / monkey 把音乐 App 拉到主屏前台 —— 那会当场切走你的屏。
  # 冷启动也走副屏:自己起屏 → 丢 app → input -d <副屏id> 发键。
  play)
    $ADB connect "$SERIAL" &>/dev/null; sleep 1
    DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    if [ -z "$DID" ]; then                       # 副屏没开 → 起屏 + 把 App 丢进去
      bash "$VD" dstart >/dev/null 2>&1; sleep 3
      bash "$VD" open "$MUSIC_PKG" >/dev/null 2>&1; sleep 4
      DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    fi
    [ -z "$DID" ] && { echo "[音乐] 副屏起不来，这次没放"; exit 1; }
    $ADB shell input -d "$DID" keyevent 126 2>>"$HOME/.claude/listen.log"
    sleep 2
    ST=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "state=PlaybackState" | sed -n 's/.*state=\([A-Z]*\)(.*/\1/p')
    NM=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "description=" | sed 's/.*description=//' | tr -d '\r')
    echo "[音乐] 副屏(display $DID) → $ST  $NM"
    ;;

  # ── 挑一首放：歌名 → 副屏搜索 → ★收键盘 → 点结果 ──
  # 歌名从哪来：先 `kugou.sh list`（纯 API，一次拿全部收藏歌名），别在副屏上一个个读树。
  # ⚠️ 下面这几个坐标是**别人手机上量的**，你必须自己重量（见 README「在你手机上要改的」）：
  #    我的 / 我喜欢 / 搜索 / 输入法「完成」 / 搜索结果第一行
  pick)
    Q="${2:-}"
    [ -z "$Q" ] && { echo "用法: kugou.sh pick \"歌名\""; exit 1; }
    NAV_MINE_X="${NAV_MINE_X:-788}"; NAV_MINE_Y="${NAV_MINE_Y:-605}"    # 底部「我的」
    CARD_FAV_X="${CARD_FAV_X:-504}"; CARD_FAV_Y="${CARD_FAV_Y:-470}"    # 「我喜欢」卡片
    BTN_SRCH_X="${BTN_SRCH_X:-729}"; BTN_SRCH_Y="${BTN_SRCH_Y:-94}"     # 右上「搜索」
    BTN_DONE_X="${BTN_DONE_X:-1202}"; BTN_DONE_Y="${BTN_DONE_Y:-135}"   # 输入法的「完成」（收键盘）
    ROW1_X="${ROW1_X:-490}"; ROW1_Y="${ROW1_Y:-237}"                    # 结果第一行的**歌名区**
    $ADB connect "$SERIAL" &>/dev/null; sleep 1
    DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    if [ -z "$DID" ]; then
      bash "$VD" dstart >/dev/null 2>&1; sleep 3
      bash "$VD" open "$MUSIC_PKG" >/dev/null 2>&1; sleep 7
      DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    fi
    [ -z "$DID" ] && { echo "[挑歌] 副屏起不来，这次没放"; exit 1; }
    bash "$VD" tap "$NAV_MINE_X" "$NAV_MINE_Y" >/dev/null 2>&1; sleep 3   # 「我的」
    bash "$VD" tap "$CARD_FAV_X" "$CARD_FAV_Y" >/dev/null 2>&1; sleep 3   # 「我喜欢」
    bash "$VD" tap "$BTN_SRCH_X" "$BTN_SRCH_Y" >/dev/null 2>&1; sleep 3   # 「搜索」
    bash "$VD" type "$Q" >/dev/null 2>&1; sleep 2                         # 灌歌名（结果自动出）
    $ADB shell input -d "$DID" tap "$BTN_DONE_X" "$BTN_DONE_Y" >/dev/null 2>&1; sleep 2  # ★收键盘
    # 点结果第一行的**歌名区**（靠左）—— 点行中间容易落到歌手名上，跳进歌手页（踩过）
    bash "$VD" tap "$ROW1_X" "$ROW1_Y" >/dev/null 2>&1; sleep 5
    ST=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "state=PlaybackState" | sed -n 's/.*state=\([A-Z]*\)(.*/\1/p')
    NM=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "description=" | sed 's/.*description=//' | tr -d '\r')
    echo "[挑歌] $Q → $ST  $NM"
    ;;

  # ── 收副屏(听完了收掉，别白占性能) ──
  stop)
    bash "$VD" dstop 2>&1 | tail -2
    ;;

  *) echo "用法: kugou.sh list [页] [数量] | play | stop" ;;
esac
