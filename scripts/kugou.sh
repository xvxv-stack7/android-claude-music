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

[ -z "$LIKE_ID" ] && { echo "先配 MUSIC_LIKE_ID（见 TUTORIAL 第四步）"; exit 1; }

case "${1:-list}" in
  # ── 列出"我喜欢"收藏 ──
  list)
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

  # ── 收副屏(听完了收掉，别白占性能) ──
  stop)
    bash "$VD" dstop 2>&1 | tail -2
    ;;

  *) echo "用法: kugou.sh list [页] [数量] | play | stop" ;;
esac
