#!/data/data/com.termux/files/usr/bin/bash
# vd.sh — 虚拟副屏:让 App 在另一块屏上跑,你的主屏一点不动
#
# 建屏两条路(都在**无 root**下验过):
#   dstart [宽 高 dpi]   ← 推荐:用 DaemonMain,不带视频编码,轻
#   start  [包名]          备用:用 scrcpy(要个录制文件当视频出口)
# 其余:
#   open <包名>         把 App 丢进当前副屏(内部先 force-stop,这一步不能省)
#   id                  看两个 id（input 用逻辑 id / screencap 用 64 位 id）
#   tree [屏号]         读控件树(坐标/文字/可点性)
#   click "文字" [屏号] 按文字点
#   type "文字" [屏号]  灌字,不弹输入法
#   shot [文件]  tap X Y  swipe X1 Y1 X2 Y2 [毫秒]  stop  dstop
#
# dex 来自 AcidGr/agent-mobile-use(MIT,含我们的免 root 修改),见 assets/
set -u
S="${ADB_SERIAL:-127.0.0.1:5555}"; A="adb -s $S shell"
DEX="${VD_DEX:-/data/local/tmp/agent-mobile-use}"

# input/ToolMain 要 DisplayManager 的逻辑 id(int);
# screencap 要 SurfaceFlinger 的 64 位 id,而且每次查都在变 → 现取现用
lid() { $A 'dumpsys display' 2>/dev/null | command grep -oE '"(scrcpy|AgentVirtualDisplay)", displayId [0-9]*' | head -1 | command grep -o '[0-9]*$'; }
sid() { $A 'dumpsys SurfaceFlinger --display-id' 2>/dev/null | command grep -E 'scrcpy|AgentVirtualDisplay' | head -1 | cut -d' ' -f2; }
tool() { $A "CLASSPATH='$DEX/agent_tools.dex' app_process /system/bin com.agent.ToolMain $1"; }

case "${1:-}" in
  dstart)
    $A "nohup sh -c \"CLASSPATH=$DEX/agent_vd_fixed.dex app_process /system/bin com.agent.DaemonMain ${2:-1280} ${3:-720} ${4:-240}\" >/data/local/tmp/vd_run.log 2>&1 &"
    echo "副屏(轻量)起来了" ;;
  dstop)
    # 先杀掉副屏上的 app:否则收屏时它们的 task 会被系统迁到主屏,把你正在看的东西顶掉
    D=$(lid)
    if [ -n "$D" ]; then
      for pkg in $($A 'dumpsys activity activities' 2>/dev/null | command grep "displayId=$D" \
                     | command grep -oE 'A=[0-9]+:[A-Za-z0-9_.]+' | cut -d: -f2 | sort -u); do
        $A "am force-stop $pkg" >/dev/null 2>&1; echo "  先收了 $pkg"
      done
    fi
    $A 'touch /data/local/tmp/vd_stop'; echo "副屏收了" ;;
  start)
    nohup scrcpy -s "$S" -N --no-window -r "${VD_REC:-$PREFIX/tmp/vd.mp4}" --no-audio \
      --new-display="${3:-1280x720/240}" ${2:+--start-app=$2} \
      --time-limit="${4:-1800}" >/dev/null 2>&1 & disown
    echo "副屏(scrcpy)起来了${2:+（$2 已丢进去）}" ;;
  open)
    PKG="$2"; $A "am force-stop $PKG"
    ACT=$($A "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $PKG" 2>/dev/null | tail -1)
    $A "am start --display $(lid) -n $ACT" ;;
  id)    echo "input→$(lid)   screencap→$(sid)" ;;
  tree)  tool "tree ${2:-$(lid)}" ;;
  click) tool "clicknode ${3:-$(lid)} '$2' contains" ;;
  type)  tool "type ${3:-$(lid)} '$2'" ;;
  shot)  F="${2:-$PREFIX/tmp/vd.png}"
         $A "screencap -d $(sid) /sdcard/vd.png" >/dev/null 2>&1 &&
         adb -s "$S" pull /sdcard/vd.png "$F" >/dev/null 2>&1
         # 校验完整性:pull 中途断链会留半张图,拿它去做视觉识别会出错
         if [ -s "$F" ] && tail -c 8 "$F" | command grep -q IEND; then
           echo "$F $(stat -c%s "$F")字节"
         else echo "❌ 图不完整,别用:$F"; exit 1; fi ;;
  tap)   $A "input -d $(lid) tap $2 $3" && echo "点了 $2 $3" ;;
  swipe) $A "input -d $(lid) swipe $2 $3 $4 $5 ${6:-300}" && echo "划了" ;;
  stop)  pkill -f "[s]crcpy -s $S" && echo "scrcpy 屏收了" || echo "本来就没开 scrcpy 屏" ;;
  *)     sed -n '2,20p' "$0" ;;
esac
