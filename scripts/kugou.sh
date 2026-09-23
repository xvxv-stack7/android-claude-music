#!/data/data/com.termux/files/usr/bin/bash
# kugou.sh — 读你的歌单 / 在【虚拟副屏】上放歌(不占你的屏)
#
# 依赖:本机音乐接口服务(~/kugou-music-api, 127.0.0.1:4000) 已登录你自己的账号
# 配置:见 music.env(照 music.env.example 填)
#
# 用法:
#   kugou.sh list [页] [数量]   列"我喜欢"收藏
#   kugou.sh play               起副屏 → 把 App 丢进去 → 发播放/暂停键(不碰主屏)
#   kugou.sh fav                副屏走到「我喜欢」歌单页
#   kugou.sh like               放整个「我喜欢」收藏夹
#   kugou.sh pick "歌名"        点着名字放某一首
#   kugou.sh stop               听完了收副屏
set -u

SDIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SDIR/music.env" ] && . "$SDIR/music.env"
API="${MUSIC_API:-http://127.0.0.1:4000}"
LIKE_ID="${MUSIC_LIKE_ID:-}"
MUSIC_PKG="${MUSIC_PKG:-com.kugou.android}"
SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
ADB="adb -s $SERIAL"
ADB_CON="adb connect $SERIAL"
VD="$SDIR/vd.sh"

# ══ 屏幕坐标:填你自己的 ══════════════════════════════════════════════
# ⚠️ 下面这些数是我在自己手机上量的(1280x720 副屏)——**你的多半不一样,别照抄**。
#    怎么量、改哪几个:见 README「坐标要自己量一次」。
TAB_HOME_X=492;    TAB_HOME_Y=605      # 底部导航「首页」
TAB_MINE_X=788;    TAB_MINE_Y=605      # 底部导航「我的」
SEARCH_X=572;      SEARCH_Y=161        # 首页顶部的搜索框
IME_DONE_X=1202;   IME_DONE_Y=135      # 输入法提取框右上角的「搜索」(收框用)
HIT_PLAYALL_X=579; HIT_PLAYALL_Y=545   # 搜索结果页「单曲」那排的「全部播放」
LIKE_CARD_X=504;   LIKE_CARD_Y=470     # 「我的」页「我喜欢」卡片**上半部**(下半跟播放条打架)
FAV_PLAYALL_X=517; FAV_PLAYALL_Y=338   # 「我喜欢」歌单页顶部的「播放全部」
# ════════════════════════════════════════════════════════════════════
#
# ── 量尺:从副屏控件树按条件抓控件中心点(坐标漂了用它重新量,别 trial-and-error) ──
#    为什么平时不直接现读:读一次控件树要十几秒,每一步都读等于白等;
#    所以日常走写死的坐标,只有"量一次"和"兜底"的时候才用它。
tree2xy() {   # tree2xy <grep -E 模式>   例:'id=dv8' 或 '"我喜欢'
  timeout 25 bash "$VD" tree 2>/dev/null | command grep -v '^#' \
    | command grep -E "$1" | head -1 \
    | sed -n 's/.* \([0-9][0-9]*\),\([0-9][0-9]*\),\([0-9][0-9]*\),\([0-9][0-9]*\) .*/\1 \2 \3 \4/p' \
    | awk '{print int(($1+$3)/2), int(($2+$4)/2)}'
}
id2xy() { tree2xy "id=$1( |$)"; }

case "${1:-list}" in
  # ── 列出"我喜欢"收藏歌名(可带页) ──
  list)
    page="${2:-1}"
    pagesize="${3:-68}"
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

  # ── 发播放/暂停键给【虚拟副屏】上的酷狗(不占她主屏) ──
  # 2026-09-22 你定：改走虚拟副屏。主屏那套"酷狗不在后台就跳过"作废——
  # 现在冷启动也是丢进副屏，永远不切她的屏。铁律：绝不 am start 把酷狗拉主屏前台。
  play)
    $ADB_CON &>/dev/null; sleep 1
    DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    if [ -z "$DID" ]; then                       # 副屏没开 → 起屏 + 丢酷狗进去
      bash "$VD" dstart >/dev/null 2>&1; sleep 3
      bash "$VD" open $MUSIC_PKG >/dev/null 2>&1; sleep 4
      DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    fi
    [ -z "$DID" ] && { echo "[音乐] 副屏起不来，这次没放"; exit 1; }
    $ADB shell input -d "$DID" keyevent 126 2>>"$SDIR/listen.log"
    sleep 2
    ST=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "state=PlaybackState" | sed -n 's/.*state=\([A-Z]*\)(.*/\1/p')
    NM=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "description=" | sed 's/.*description=//' | tr -d '\r')
    echo "[音乐] 副屏(display $DID) → $ST  $NM"
    ;;

  # ── 走到「我喜欢」歌单页(主页→我的→我喜欢),全在副屏上点 ──
  # 2026-09-22 你要的:放歌得能自己挑,坐标定死。到了这页,选哪首由我读树+点。
  fav)
    $ADB_CON &>/dev/null; sleep 1
    DID=$(bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p')
    [ -z "$DID" ] && { echo "[音乐] 副屏没开，先跑 play 起屏"; exit 1; }
    for _ in 1 2 3 4 5; do                     # 先退回主页(判据:首页搜索框在不在)
      bash "$VD" tree 2>/dev/null | command grep -q 'id=mrs' && break
      $ADB shell input -d "$DID" keyevent 4 >/dev/null 2>&1
      sleep 2
    done
    bash "$VD" tap $TAB_MINE_X $TAB_MINE_Y >/dev/null 2>&1    # 底部导航「我的」
    sleep 2
    # 「我喜欢 N」卡片:点上半部 —— 卡片下半截跟底部播放条打架,
    # 点正中(y≥499)会滚进播放页(这里踩过坑)。
    bash "$VD" tap $LIKE_CARD_X $LIKE_CARD_Y >/dev/null 2>&1
    sleep 2
    if bash "$VD" tree 2>/dev/null | command grep -q '"我喜欢"'; then
      echo "[音乐] 到「我喜欢」了(display $DID) — 读 tree 拿行坐标再点"
    else
      echo "[音乐] 没走到「我喜欢」，读 tree 看卡在哪"
    fi
    ;;

  # ── 挑一首放:歌名 → 副屏搜索 → ★收键盘 → 点结果 ──
  # 2026-09-22 打通。**"收键盘"那步是关键**:输入法的提取框盖着整个上半屏
  # (0,0~1124,270),不收就点不动结果行 —— 点哪儿都被输入法吃掉。
  # 歌名从哪来:先 `kugou.sh list`(纯API,一次拿全部收藏歌名),别在副屏上一个个读。
  pick)
    Q="$2"
    [ -z "$Q" ] && { echo "用法: kugou.sh pick \"歌名\""; exit 1; }
    $ADB_CON &>/dev/null; sleep 1
    did() { bash "$VD" id 2>/dev/null | sed -n 's/.*input→\([0-9]*\).*/\1/p'; }
    DID=$(did)
    if [ -z "$DID" ]; then
      bash "$VD" dstart >/dev/null 2>&1; sleep 3
      bash "$VD" open $MUSIC_PKG >/dev/null 2>&1; sleep 7
      DID=$(did)
    fi
    [ -z "$DID" ] && { echo "[挑歌] 副屏起不来，这次没放"; exit 1; }
    # 放完怎么算数:查一眼**真的在放的是哪首**(media_session 快,一秒出)
    playing_now() {
      $ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "description=" \
        | sed 's/.*description=//' | tr -d '\r'
    }
    hit() { case "$(playing_now)" in *"$Q"*) return 0 ;; *) return 1 ;; esac; }

    # ── 快路径:全按本机实测坐标走,**一次控件树都不读**(读一次十几秒,最贵的就是它) ──
    #    你 2026-09-23 定的:先赌它在首页、点位全中,一遍走完;放错了再回头读树。
    # 先退两层:2026-09-23 实测,从「播放页(+侧边栏)」按 2 次返回才露得出首页,按 1 次不够
    $ADB shell input -d "$DID" keyevent 4 >/dev/null 2>&1; sleep 1
    $ADB shell input -d "$DID" keyevent 4 >/dev/null 2>&1; sleep 1
    bash "$VD" tap $TAB_HOME_X $TAB_HOME_Y >/dev/null 2>&1; sleep 2          # 底部导航「首页」
    bash "$VD" tap $SEARCH_X $SEARCH_Y >/dev/null 2>&1; sleep 3          # 顶部搜索框
    bash "$VD" type "$Q" >/dev/null 2>&1; sleep 3            # 灌歌名
    bash "$VD" tap $IME_DONE_X $IME_DONE_Y >/dev/null 2>&1; sleep 4         # 收输入法提取框
    bash "$VD" tap $HIT_PLAYALL_X $HIT_PLAYALL_Y >/dev/null 2>&1; sleep 5          # 「单曲」那排的「全部播放」
    if hit; then
      echo "[音乐·快] $Q → $(playing_now)"; exit 0
    fi

    # ── 慢路径:快路径没放到对的那首 → 读控件树,一步步纠正重来 ──
    #    归位判据用「首页搜索框在不在」(id=mrs),别用底部导航 —— 播放页也有底部导航,
    #    拿它判会以为已经归位,后面每一下都点在错地方(09-23 实测:点《戒烟》放出来是别的歌)。
    echo "[音乐] 快路径没中，读树重来…"
    for _ in 1 2 3 4 5 6; do
      timeout 25 bash "$VD" tree 2>/dev/null | command grep -q 'id=mrs' && break
      $ADB shell input -d "$DID" keyevent 4 >/dev/null 2>&1; sleep 2
    done
    XY=$(id2xy mrs); [ -z "$XY" ] && XY="572 161"
    bash "$VD" tap $XY >/dev/null 2>&1; sleep 3
    bash "$VD" type "$Q" >/dev/null 2>&1; sleep 3
    XY=$(id2xy inputExtractAction)                    # 输入法各家的键不一样,抓不到就用实测值
    bash "$VD" tap ${XY:-1202 135} >/dev/null 2>&1; sleep 4
    XY=$(id2xy bzu0)                                  # 「单曲」那排的「全部播放」
    [ -z "$XY" ] && { echo "[音乐] 结果里没找到《$Q》"; exit 1; }
    bash "$VD" tap $XY >/dev/null 2>&1; sleep 5
    echo "[音乐·慢] $Q → $(playing_now)"
    hit || echo "[音乐] ⚠️ 还是没中，得人工看一眼副屏"
    ;;

  # ── 放整个「我喜欢」收藏夹(从头排队播) ──
  # 2026-09-23 你要的:一句"放我收藏",整张歌单排上。
  like)
    bash "$0" fav >/dev/null 2>&1; sleep 2
    bash "$VD" tap $FAV_PLAYALL_X $FAV_PLAYALL_Y >/dev/null 2>&1; sleep 5    # 「播放全部」(2026-09-23 实测)
    ST=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "state=PlaybackState" | sed -n 's/.*state=\([A-Z]*\)(.*/\1/p')
    NM=$($ADB shell dumpsys media_session 2>/dev/null | command grep -m1 "description=" | sed 's/.*description=//' | tr -d '\r')
    echo "[音乐] 收藏夹 → $ST  $NM"
    ;;

  # ── 收副屏(听完了收掉,别白占) ──
  stop)
    bash "$VD" dstop 2>&1 | tail -2
    ;;

  *) echo "用法: kugou.sh list [页] [数量] | play | pick \"歌名\" | like(放整个收藏夹) | fav | stop" ;;
esac
