---
name: kugou-music
description: 音乐技能——读"我喜欢"收藏（纯 API）+ 读"此刻唱到哪一句" + 放歌走【虚拟副屏】（不占主屏）。使用时机：查收藏、放歌/停歌、聊某句歌词、要知道用户此刻听到哪一句时。
---

# 音乐 Skill — 读收藏 · 报歌词 · 放歌不占屏

靠本机跑的音乐接口服务（`127.0.0.1:4000`）读**用户自己账号**的收藏与歌词。

## 背景

> ⚠️ 这一套是**酷狗**那条路。想换音乐 App：读播放状态、发播放键仍然通用（走系统媒体接口），
> 但**歌单和歌词要换对应的本地接口服务** —— 本项目默认的是 `KuGouMusicApi`。

- 本机跑 `KuGouMusicApi`（`~/kugou-music-api`），服务在 `127.0.0.1:4000`。
- 服务进程已登录用户账号并记住登录态，读"我喜欢"**无需 cookie / 验证码**。
- **进程重启 = 登录态丢**，要重新登录一次（见 TUTORIAL 第二步）。
- 歌单 id 写在 `~/.claude/scripts/music.env` 的 `MUSIC_LIKE_ID`。

## ⚠️ 当前能力（如实，别虚标）

- `list`（读收藏）：纯 API，✅ 成
- `play`（副屏发播放/暂停键）：✅ 成，续播上次那首
- **`pick "歌名"`（挑歌播放）：✅ 成** —— 归位 → 顶部搜索 → 灌歌名 → 点结果（坐标现读）。
  API 那条路仍被平台侧滑块验证码堵着，但**副屏上点得动**，所以走 UI。
- `stop`（收副屏）：✅

## 语法

```bash
bash ~/.claude/scripts/kugou.sh list              # 列"我喜欢"收藏（歌名，纯 API）
bash ~/.claude/scripts/kugou.sh pick "歌名"       # ★挑一首放：归位 → 搜索 → 点结果
bash ~/.claude/scripts/kugou.sh play              # 起副屏 + 丢 app + 发播放/暂停键（续播上一首）
bash ~/.claude/scripts/kugou.sh stop              # 听完了收副屏
```

## 挑歌：说歌名就能放（2026-09 打通）

API 选歌被平台侧验证码挡死，但**副屏上点得动** —— 所以走 UI 那条路：

```bash
bash ~/.claude/scripts/kugou.sh pick "歌名"
```

四步：**归位**（连按返回直到看见底部导航）→ 点顶部`搜索` → 灌歌名 → **点结果行**。

两个踩出来的设计：

**① 归位不能省。** 一首放完，App 可能停在歌手页、播放页、任意位置 ——
不先退回主界面就点"搜索"，点出来的是别的东西（踩过：跳进了歌手主页）。
归位用返回键循环，**不 force-stop**，所以歌不会被打断。

**② 结果行的坐标是现读的。** 脚本从控件树里找**含歌名的那一行**再点它的中心，
**不写死坐标** —— 换台手机、换个搜索词都能用。整个流程里写死的只有"顶部搜索入口"一个点。

> ⚠️ **别走"歌单页右上角搜索"那条**：那条会让输入法弹出**全屏提取框**盖住整个上半屏
> （`0,0~1124,270`），结果行**点不动** —— 点哪儿都被输入法吃掉，得先收键盘；
> 而输入法的"完成"键每个输入法位置都不一样，换台机器就不灵。顶部搜索这条没这问题。

**歌名从 `list` 拿**（纯 API，一次全出），别在副屏上一个个读树。

## 读歌词（走 API，别去副屏上戳）

副屏上音乐 App 的歌词是**自绘的**，控件树里抓不到。**读歌词走 API，三步**：

```bash
# 1. 拿 hash（收藏列表里每首都有）
curl -s "http://127.0.0.1:4000/playlist/track/all?id=$MUSIC_LIKE_ID&page=1&pagesize=200"
#    → songs[].hash
# 2. 拿 lyrics id + accesskey
curl -s "http://127.0.0.1:4000/search/lyric?hash=<hash>"      # → candidates[0].id / .accesskey
# 3. 拿正文（LRC）
curl -s "http://127.0.0.1:4000/lyric?id=<id>&accesskey=<key>&decode=true&fmt=lrc"
#    → lyrics 字段，带 [mm:ss.xx] 时间轴
```

## 报"此刻听到哪一句"

```bash
python3 ~/.claude/scripts/lyric_now.py
```

打印当前歌 + 进度 + 时间轴前后两句，箭头 `→` 指正听到的那句。
用户问"这句写的什么"、想聊歌词时，**先跑它再开口，别凭印象编歌词**。

**`--auto` 给轮询用**：报"此刻正好唱到的那句"，单行；暂停/没放歌时静默。
轮询（`listen-loop.sh`）那边**隔 30~80 秒随机瞟一次**，一首歌最多递两句 ——
随的是**时机**，所以同一首歌听十遍撞上的句子都不同。

**两个坑（都踩过）**：

- `dumpsys media_session` 的 position 是**快照**，必须补 `now(/proc/uptime) - updated` 的漂移 —— 实测差过 **39 秒**，不补就报错句。
- 歌词字段不固定：有的给 `lyrics`，有的只给 base64 的 `content`/`decodeContent`，三种都要兜。

## ⛔ 铁律：不占用户的屏

- **绝不许 `am start` / `monkey` 把音乐 App 拉到主屏前台** —— 那会当场把用户正在看的东西顶掉，是最招人烦的一件事。
- 放歌一律走副屏：`play` 自己起屏、丢 app、发 `input -d <副屏id> keyevent 126`。**冷启动也不碰主屏。**
- 副屏 id 每次可能变，**现取现用**（`vd.sh id`），别写死。
- 放完**别急着收屏** —— 用户常是听着睡；说停再 `stop`。

## 给 AI 的话术

- 放歌是**你放给用户听**，不是用户自己在听。触发后认知为"我在放歌给他/她"。
- 结束后配一句话，报歌名别硬编：`play` 最后一行会打 `副屏(display N) → PLAYING  歌名 - 歌手`，照它说。

## 依赖

- `~/kugou-music-api` 服务在 4000 活着（挂了：`PORT=4000 node index.js`）
- adb 回环在线（第二个仓库 `android-claude-agent`）
- `~/.claude/scripts/vd.sh`（虚拟副屏，源自 AcidGr/agent-mobile-use）
