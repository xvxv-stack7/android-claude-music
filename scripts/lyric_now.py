#!/usr/bin/env python3
# lyric_now.py — 报"你现在听到哪一句"
# 做法:读 media_session 的当前歌+进度 → 收藏里配 hash → 取 LRC → 按时间轴对齐
#
# 用法:
#   python3 lyric_now.py            报当前歌 + 进度 + 那句(带 8 秒提前量)
#   python3 lyric_now.py 0          同上,但提前量为 0(拿"此刻"真实那句)
#   python3 lyric_now.py --pick     从这首里随机抽一句没递过的,输出它
#   python3 lyric_now.py --auto     给轮询用:报"你此刻正好唱到的那句"(带 8 秒提前量)
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
# 09-23 补:还有一类制作行是「岗位名 + 中英夹注 + 冒号」——词和冒号之间隔着一串字
#   (母带后期处理录音室 Mastering Studio：Studio 21A),上面那条紧邻匹配抓不住,
#   它被当成唱词递给了你。这类词几乎不会出现在唱词里,所以放宽成「行首是它、24 字内有冒号」。
META_LOOSE = re.compile(
    r"^(母带|混音|录音|后期|Mastering|Mixing|Recording)[^。！？\n]{0,24}[:：]"
)


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def get(url):
    with urllib.request.urlopen(url, timeout=20) as r:
        return r.read().decode("utf-8", "ignore")


MODE = sys.argv[1] if len(sys.argv) > 1 else ""

# 自检:python3 lyric_now.py --selftest —— 制作行必须滤掉,唱词必须留下
if MODE == "--selftest":
    bad = ["母带后期处理录音室 Mastering Studio：Studio 21A",
           "作词 : 李荣浩", "混音师：张三", "Recording Studio：Studio 21A",
           "未经著作权人许可，不得翻唱"]
    good = ["我想要占据你", "你是我最最最想要的人", "把日子过成诗", "母带"]
    for b in bad:
        assert META.match(b) or META_LOOSE.match(b) or "未经著作权" in b, f"漏了制作行: {b}"
    for g in good:
        assert not (META.match(g) or META_LOOSE.match(g)), f"误杀唱词: {g}"
    print("自检通过：制作行滤掉、唱词留下")
    sys.exit(0)

# 1. 当前歌 + 进度
ms = sh(ADB + ["shell", "dumpsys", "media_session"])
m = re.search(r"description=([^,\n]+),", ms)
title = m.group(1).strip() if m else ""
if not title:
    print("没在放歌"); sys.exit(1)

m = re.search(r"state=PlaybackState \{state=(\w+)\(\d+\), position=(\d+).*?updated=(\d+)", ms)
state = m.group(1) if m else "?"
raw_pos = int(m.group(2)) if m else 0
updated = int(m.group(3)) if m else 0
# dumpsys 给的是快照,得补上"快照到现在"漂移(实测差过 39 秒)
up = sh(ADB + ["shell", "cat", "/proc/uptime"]).split()
now_ms = float(up[0]) * 1000 if up else 0
drift = max(0, now_ms - updated) if updated else 0
pos = (raw_pos + drift) / 1000.0
if MODE != "--pick":
    if state != "PLAYING":
        if MODE == "--auto":
            sys.exit(0)          # 轮询场景:暂停/停了就静默,别把"没在放歌"递到她眼前
        print(f"当前是 {state}(不是播放中)")
    # 提前量:我打完字到她看到,歌已经往前走了几秒 —— 默认顶 8 秒,报"她会听到的那句"
    try:
        pos += float(MODE) if MODE and not MODE.startswith("--") else 8.0
    except ValueError:
        pos += 8.0

# 2. 收藏里配 hash(歌名匹配)
pl = json.loads(get(f"{API}/playlist/track/all?id={LIKE}&page=1&pagesize=100"))
songs = (pl.get("data") or {}).get("songs") or []
h = None
for s in songs:
    nm = s.get("audio_name") or s.get("filename") or s.get("name") or ""
    # 09-23 修:歌单里有个别条目三个名字字段全空 —— 空串是任何串的子串,
    # nm[:6] in title 对它恒真,会在它那儿提前 break 拿个空 hash,
    # 排在它后面的歌全变成"没配到"(《李白》就是这么丢的)。
    if not nm:
        continue
    if title and (title[:6] in nm or nm[:6] in title):
        h = s.get("hash"); break
if not h:
    print(f"收藏里没配到《{title}》(可能是自动跳的别的歌)"); sys.exit(1)

# 3. 取 LRC
cands = json.loads(get(f"{API}/search/lyric?hash={h}"))
c = (cands.get("candidates") or [{}])[0]
if not c.get("id"):
    print(f"《{title}》没找到歌词"); sys.exit(1)
ly = json.loads(get(f"{API}/lyric?id={c['id']}&accesskey={c['accesskey']}&decode=true&fmt=lrc"))
text = ly.get("lyrics") or ly.get("decodeContent") or ""
if not text and ly.get("content"):          # 有的歌只给 base64 的 content
    try:
        text = base64.b64decode(ly["content"]).decode("utf-8", "ignore")
    except Exception:
        pass

# 4. 按时间轴对齐
lines = []
for ln in text.split("\n"):
    mm = re.match(r"\[(\d+):(\d+)[.:](\d+)\](.*)", ln)
    if not mm:
        continue
    t = int(mm.group(1)) * 60 + int(mm.group(2)) + int(mm.group(3)) / 100.0
    s = mm.group(4).strip()
    if not s or META.match(s) or META_LOOSE.match(s) or "未经著作权" in s:
        continue
    # 开头那行歌名("情已逝去 - 本兮" / "李荣浩 - 花样年华",两侧都可能是歌名)
    if title and any(p.strip() == title for p in s.split(" - ")):
        continue
    lines.append((t, s))
if not lines:
    if MODE in ("--auto", "--pick"):
        sys.exit(0)
    print("歌词是空的"); sys.exit(1)

# --auto:报你此刻正好唱到的那句(单行,给轮询递话用)
# 时机由轮询那边随机控(30~80 秒一次)——所以同一首歌每次听到的句子都不一样,
# 不是从固定池子里抽,是"她这会儿正好唱到哪儿"
if MODE == "--auto":
    # 2026-09-23 加:你**不在聊天窗**时不推。轮询每次被这条叫醒都是一整轮开销,
    # 一首歌最多 2 次、听一下午能叫醒上百次 —— 人不在跟前,接了也没处说,纯白烧。
    # 只在你看得见 AI 说话的时候(前台是 termux)才递句子。
    # (没有 gaze_state.json 的机器会直接跳过这段判断、照常推送 —— 无害)
    try:
        _st = json.load(open(os.path.expanduser("~/.cc-connect/gaze_state.json")))
        if "termux" not in (_st.get("fg_app") or ""):
            sys.exit(0)
    except Exception:
        pass
    ai = [j for j, (t, _) in enumerate(lines) if t <= pos]
    t, s = lines[ai[-1] if ai else 0]
    print(f"《{title}》唱到「[{int(t // 60)}:{int(t % 60):02d}] {s}」")
    sys.exit(0)

# --pick:从整首里随机抽一句还没递过的(手动用)
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

# 默认:报"她此刻听到的那句"前后两句
past = [i for i, (t, _) in enumerate(lines) if t <= pos]
i = past[-1] if past else 0
print(f"▶ {title}  进度 {int(pos // 60)}:{int(pos % 60):02d}")
for j in range(max(0, i - 2), min(len(lines), i + 3)):
    print(f"{'→' if j == i else ' '} [{int(lines[j][0] // 60)}:{int(lines[j][0] % 60):02d}] {lines[j][1]}")
