#!/usr/bin/env python3
# lyric_now.py — "此刻唱到哪一句"
#
# 做法：读 media_session 的当前歌 + 播放进度 → 在歌单里配到这首歌 → 取 LRC
#       → 按时间轴对齐 → 报出"你耳朵里正在唱的那句"
#
# 用法:
#   python3 lyric_now.py            报当前歌 + 进度 + 那句(带 8 秒提前量)
#   python3 lyric_now.py 0          同上,但提前量为 0(拿"此刻"真实那句)
#   python3 lyric_now.py 12         提前量改成 12 秒
#   python3 lyric_now.py --auto     给轮询用:单行报"此刻那句";暂停/没放歌时静默
#   python3 lyric_now.py --pick     从这首里随机抽一句没递过的(手动挑着聊时用)
#
# 配置(见 TUTORIAL 第四步):
#   MUSIC_LIKE_ID   你的"我喜欢"歌单 id(形如 collection_3_<userid>_2_0)
#                   也可以写进 ~/.claude/scripts/music.env
#   ADB_SERIAL      adb 设备,默认 127.0.0.1:5555
#   MUSIC_API       本地音乐接口服务,默认 http://127.0.0.1:4000
import base64, json, os, random, re, subprocess, sys, urllib.request

API = os.environ.get("MUSIC_API", "http://127.0.0.1:4000")
ADB = ["adb", "-s", os.environ.get("ADB_SERIAL", "127.0.0.1:5555")]
SEEN = os.path.expanduser("~/.claude/listen.seen")        # 递过的句子:歌名|句子(--pick 用)

# 配置文件兜底(让没设环境变量的人也能用)
_cfg = os.path.expanduser("~/.claude/scripts/music.env")
if os.path.exists(_cfg):
    for _ln in open(_cfg, encoding="utf-8"):
        _ln = _ln.strip()
        if _ln and not _ln.startswith("#") and "=" in _ln:
            _k, _v = _ln.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip().strip('"').strip("'"))
LIKE = os.environ.get("MUSIC_LIKE_ID", "")

# 制作信息行(词：/曲：/编曲：…)也带时间轴,但不是歌词,不能当成"唱到哪句"报给人
META = re.compile(
    r"^(作词|作曲|词|曲|编曲|混音|和声|制作人|制作|录音|吉他|贝斯|鼓|键盘|弦乐|"
    r"SP|OP|出品|发行|宣发|推广|营销|版权|监制|母带|统筹|企划|策划|总监|"
    r"演唱|原唱|配唱|封面|文案|视觉|设计|插画|摄影|导演)\s*[:：]"
)


def sh(cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""      # adb 卡住/超时 → 当成读不到,别让轮询整个挂住


def get(url):
    with urllib.request.urlopen(url, timeout=20) as r:
        return r.read().decode("utf-8", "ignore")


MODE = sys.argv[1] if len(sys.argv) > 1 else ""

# ── 1. 当前歌 + 进度 ────────────────────────────────────────────────
ms = sh(ADB + ["shell", "dumpsys", "media_session"], timeout=25)
m = re.search(r"description=([^,\n]+),", ms)
title = m.group(1).strip() if m else ""
if not title:
    if MODE == "--auto":
        sys.exit(0)                     # 轮询场景:没在放歌,静默
    print("没在放歌"); sys.exit(1)

m = re.search(r"state=PlaybackState \{state=(\w+)\(\d+\), position=(\d+).*?updated=(\d+)", ms)
state = m.group(1) if m else "?"
raw_pos = int(m.group(2)) if m else 0
updated = int(m.group(3)) if m else 0

# dumpsys 给的是**快照**,得补上"快照到现在"这段漂移(实测差过 39 秒)
up = sh(ADB + ["shell", "cat", "/proc/uptime"]).split()
now_ms = float(up[0]) * 1000 if up else 0
drift = max(0, now_ms - updated) if updated else 0
pos = (raw_pos + drift) / 1000.0

if MODE != "--pick":
    if state != "PLAYING":
        if MODE == "--auto":
            sys.exit(0)                 # 轮询场景:暂停/停了就静默,别把"没在放歌"递到眼前
        print(f"当前是 {state}(不是播放中)")
    # 提前量:AI 打完字递到眼前时,歌已经又走了几秒 —— 默认顶 8 秒,报的才是"你会听到的那句"
    try:
        pos += float(MODE) if MODE and not MODE.startswith("--") else 8.0
    except ValueError:
        pos += 8.0

# ── 2. 歌单里配 hash(按歌名匹配) ──────────────────────────────────
if not LIKE:
    if MODE == "--auto":
        sys.exit(0)
    print("还没配歌单 id —— 把 MUSIC_LIKE_ID 写进 ~/.claude/scripts/music.env(见 TUTORIAL 第四步)")
    sys.exit(1)

pl = json.loads(get(f"{API}/playlist/track/all?id={LIKE}&page=1&pagesize=200"))
songs = (pl.get("data") or {}).get("songs") or []
h = None
for s in songs:
    nm = s.get("audio_name") or s.get("filename") or s.get("name") or ""
    if title and (title[:6] in nm or nm[:6] in title):
        h = s.get("hash"); break
if not h:
    if MODE == "--auto":
        sys.exit(0)                     # 不在你的歌单里 → 轮询场景静默
    print(f"歌单里没配到《{title}》(可能不在收藏里)"); sys.exit(1)

# ── 3. 取 LRC ──────────────────────────────────────────────────────
cands = json.loads(get(f"{API}/search/lyric?hash={h}"))
c = (cands.get("candidates") or [{}])[0]
if not c.get("id"):
    if MODE == "--auto":
        sys.exit(0)
    print(f"《{title}》没找到歌词"); sys.exit(1)
ly = json.loads(get(f"{API}/lyric?id={c['id']}&accesskey={c['accesskey']}&decode=true&fmt=lrc"))
text = ly.get("lyrics") or ly.get("decodeContent") or ""
if not text and ly.get("content"):          # 有的歌只给 base64 的 content
    try:
        text = base64.b64decode(ly["content"]).decode("utf-8", "ignore")
    except Exception:
        pass

# ── 4. 按时间轴对齐 ────────────────────────────────────────────────
lines = []
for ln in text.split("\n"):
    mm = re.match(r"\[(\d+):(\d+)[.:](\d+)\](.*)", ln)
    if not mm:
        continue
    t = int(mm.group(1)) * 60 + int(mm.group(2)) + int(mm.group(3)) / 100.0
    s = mm.group(4).strip()
    if not s or META.match(s) or "未经著作权" in s:
        continue
    # 开头那行歌名("歌名 - 歌手" / "歌手 - 歌名",两侧都可能是歌名)
    if title and any(p.strip() == title for p in s.split(" - ")):
        continue
    lines.append((t, s))
if not lines:
    if MODE in ("--auto", "--pick"):
        sys.exit(0)
    print("歌词是空的"); sys.exit(1)

# --auto:报"此刻正好唱到的那句"(单行,给轮询递话用)
# 时机由轮询那边随机控(30~80 秒一次)——所以同一首歌每次听撞上的句子都不同,
# 不是从固定池子里抽,是"你这会儿正好唱到哪儿"
if MODE == "--auto":
    ai = [j for j, (t, _) in enumerate(lines) if t <= pos]
    t, s = lines[ai[-1] if ai else 0]
    print(f"《{title}》唱到「[{int(t // 60)}:{int(t % 60):02d}] {s}」")
    sys.exit(0)

# --pick:从整首里随机抽一句还没递过的(手动挑着聊时用)
if MODE == "--pick":
    pool, dup = [], set()
    for t, s in lines:
        if len(s) < 5 or s in dup:      # 太碎的、同一句唱好几遍的(副歌),只留一次
            continue
        dup.add(s); pool.append((t, s))
    hist = set()
    try:
        for row in open(SEEN, encoding="utf-8"):
            p = row.rstrip("\n").split("|", 1)
            if len(p) == 2 and p[0] == title:
                hist.add(p[1])
    except Exception:
        pass
    pool = [x for x in pool if x[1] not in hist]
    if not pool:
        sys.exit(0)                     # 这首的句子都聊过了
    t, s = random.choice(pool)
    try:
        with open(SEEN, "a", encoding="utf-8") as f:
            f.write(f"{title}|{s}\n")
    except Exception:
        pass
    print(f"[{int(t // 60)}:{int(t % 60):02d}] {s}")
    sys.exit(0)

# 默认:报"此刻听到的那句"前后两句
past = [i for i, (t, _) in enumerate(lines) if t <= pos]
i = past[-1] if past else 0
print(f"▶ {title}  进度 {int(pos // 60)}:{int(pos % 60):02d}")
for j in range(max(0, i - 2), min(len(lines), i + 3)):
    print(f"{'→' if j == i else ' '} [{int(lines[j][0] // 60)}:{int(lines[j][0] % 60):02d}] {lines[j][1]}")
