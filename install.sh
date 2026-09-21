#!/data/data/com.termux/files/usr/bin/bash
# install.sh — 把"一起听"铺到这台手机上
#
#   bash <(curl -sL https://gitee.com/xvxv663/android-claude-music/raw/master/install.sh)
#   或者 clone 下来跑:  bash install.sh
#
# 铺完还要你亲手做两件事(脚本会提示): 登录你自己的音乐账号、填歌单 id。
set -u

REPO="https://gitee.com/xvxv663/android-claude-music"
SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
DST_SKILLS="$HOME/.claude/skills"
DST_SCRIPTS="$HOME/.claude/scripts"
DEX_DIR="/data/local/tmp/agent-mobile-use"

ok()   { printf '  ✅ %s\n' "$*"; }
warn() { printf '  ⚠️  %s\n' "$*"; }
say()  { printf '%s\n' "$*"; }

say "🎵 android-claude-music · 安装"
say ""

# ── 0. 找源:本地 clone 优先,否则拉一份 ──
SDIR="$(cd "$(dirname "$0" 2>/dev/null || echo .)" 2>/dev/null && pwd || echo "")"
if [ -n "$SDIR" ] && [ -f "$SDIR/scripts/lyric_now.py" ]; then
  SRC="$SDIR"
elif [ -n "$SDIR" ] && [ -f "$SDIR/../scripts/lyric_now.py" ]; then
  SRC="$(cd "$SDIR/.." && pwd)"
else
  SRC="${TMPDIR:-${PREFIX:-/tmp}/tmp}/acm-$$"
  say "→ 拉取仓库到 $SRC"
  rm -rf "$SRC"
  git clone --depth 1 "$REPO" "$SRC" >/dev/null 2>&1 || {
    warn "拉取失败 —— 检查网络,或先把仓库 clone 下来再跑本脚本"; exit 1; }
fi
say "→ 源: $SRC"
say ""

# ── 1. 环境 ──
say "环境自检"
command -v python3 >/dev/null && ok "python3 $(python3 -V 2>&1 | cut -d' ' -f2)" || { warn "没有 python3"; exit 1; }
command -v node    >/dev/null && ok "node $(node -v)" || warn "没有 node —— 装: pkg install nodejs（跑接口服务要用）"
command -v git     >/dev/null && ok "git" || warn "没有 git —— 装: pkg install git"
command -v adb     >/dev/null && ok "adb" || warn "没有 adb —— 见 android-claude-agent 仓库"
if adb -s "$SERIAL" shell echo ok >/dev/null 2>&1; then
  ok "adb 回环在线（$SERIAL）"
  ADB_OK=1
else
  warn "adb 回环不通 —— 副屏放歌先装不了,先看 android-claude-agent 仓库"
  ADB_OK=0
fi
say ""

# ── 2. 铺技能与脚本 ──
say "铺文件"
mkdir -p "$DST_SKILLS" "$DST_SCRIPTS"
for d in "$SRC"/skills/*/; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  rm -rf "$DST_SKILLS/$n"
  cp -r "$d" "$DST_SKILLS/$n"
done
ok "技能 → $DST_SKILLS/（kugou-music / listen-together / music-control）"

cp "$SRC"/scripts/*.sh "$SRC"/scripts/*.py "$DST_SCRIPTS/" 2>/dev/null
chmod +x "$DST_SCRIPTS"/*.sh 2>/dev/null
ok "脚本 → $DST_SCRIPTS/（lyric_now.py / listen-loop.sh / listen-detect.sh / kugou.sh / vd.sh / music_moment.sh）"

if [ -f "$DST_SCRIPTS/music.env" ]; then
  ok "配置已存在，没动它：$DST_SCRIPTS/music.env"
else
  cp "$SRC/scripts/music.env.example" "$DST_SCRIPTS/music.env"
  warn "配置已生成，**还差一步**：填 $DST_SCRIPTS/music.env 里的 MUSIC_LIKE_ID"
fi
say ""

# ── 3. 副屏 dex ──
if [ "$ADB_OK" = "1" ]; then
  say "铺虚拟副屏"
  adb -s "$SERIAL" shell mkdir -p "$DEX_DIR" >/dev/null 2>&1
  for f in "$SRC"/assets/*.dex; do
    [ -f "$f" ] || continue
    adb -s "$SERIAL" push "$f" "$DEX_DIR/" >/dev/null 2>&1 && ok "$(basename "$f")"
  done
  say ""
fi

# ── 4. 收尾 ──
say "装完了。接下来三件事："
say ""
say "  ① 起本地音乐接口服务（默认是酷狗那套；用别的音乐 App 要另找对应的，见 TUTORIAL 第一步）"
say "     git clone https://github.com/MakcRe/KuGouMusicApi ~/kugou-music-api"
say "     cd ~/kugou-music-api && npm install"
say "     PORT=4000 nohup node index.js > ~/kugou-api.log 2>&1 &"
say ""
say "  ② 登录你自己的账号（要收验证码，只能你来）"
say "     curl \"http://127.0.0.1:4000/captcha/sent?mobile=你的手机号\""
say "     curl \"http://127.0.0.1:4000/login/cellphone?mobile=你的手机号&code=验证码\""
say "     记下返回里的 userid，填进 $DST_SCRIPTS/music.env"
say ""
say "  ③ 验证 + 接轮询"
say "     python3 $DST_SCRIPTS/lyric_now.py     # 先在手机上放首歌"
say "     bash $DST_SCRIPTS/listen-loop.sh      # 看它怎么递话"
say ""
say "详见 TUTORIAL.md"
