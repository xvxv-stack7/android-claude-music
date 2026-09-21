# 手把手：把"一起听"装起来

从零到"它在你耳机里接上话"，一步一步来。全程在手机上，不用电脑、不用 Root。

> 前置没做好会卡在第一步。先花一分钟确认这两条：
>
> ```bash
> claude --version                     # AI 住进来了没（没有→ android-claude-wechat）
> adb -s 127.0.0.1:5555 shell echo ok  # AI 摸得到手机没（不通→ termux-shizuku）
> ```

---

## 第一步 · 装本地音乐接口服务

手机上的播放 App 不对外开接口，但社区有人把它逆向成了本地 HTTP 服务。
本机跑一个，AI 就能读到你账号里的歌单和歌词 —— **全程在你的手机上，不出设备**。

```bash
cd ~
git clone https://github.com/MakcRe/KuGouMusicApi kugou-music-api
cd kugou-music-api
npm install
```

> 🌐 国内拉 GitHub 慢或断，先开代理再 clone：
> `export HTTPS_PROXY=http://127.0.0.1:7890`（换成你自己的代理端口）

跑起来：

```bash
cd ~/kugou-music-api
PORT=4000 nohup node index.js > ~/kugou-api.log 2>&1 &
sleep 3 && curl -s -m 5 http://127.0.0.1:4000/ | head -c 100
```

能吐出一段 HTML，就是活了（它自带一个网页控制台，浏览器打开 `127.0.0.1:4000` 也能看）。

> 端口用 4000，是跟前两个仓库里的其他本地服务错开，别改。

---

## 第二步 · 登录你自己的账号

**这一步只能你亲手做** —— 要收短信验证码。本仓库不含任何账号。

```bash
# 1) 发验证码到你的手机号
curl -s "http://127.0.0.1:4000/captcha/sent?mobile=你的手机号"

# 2) 收到短信后，拿验证码登录
curl -s "http://127.0.0.1:4000/login/cellphone?mobile=你的手机号&code=六位验证码"
```

登录成功的返回里会有 `userid` 和 `nickname`，**把 userid 记下来**，后面要用。

> 🔑 两个必须知道的点：
> - **登录态存在服务进程的内存里** —— 进程一重启（手机重启、服务被杀），就得重新登录一次。
> - 想要开机自动恢复：把服务挂进你的开机脚本，登录态没法自动续，但服务在、你手动登一次就行。别把账号密码写进任何脚本。

---

## 第三步 · 铺技能和脚本

```bash
bash <(curl -sL https://gitee.com/xvxv663/android-claude-music/raw/master/install.sh)
```

它会做四件事：把技能铺进 `~/.claude/skills/`、脚本铺进 `~/.claude/scripts/`、
把副屏的 dex 推进 `/data/local/tmp/agent-mobile-use/`、然后自检一遍。

手动装也行，就是把这几个目录拷过去：

```
skills/kugou-music/      → ~/.claude/skills/kugou-music/
skills/music-control/    → ~/.claude/skills/music-control/
skills/listen-together/  → ~/.claude/skills/listen-together/
scripts/*.sh *.py        → ~/.claude/scripts/
```

---

## 第四步 · 验证

### 4.1 读到你的收藏

```bash
# 把 <你的userid> 换成第二步记下的那个
curl -s "http://127.0.0.1:4000/user/playlist?userid=<你的userid>" | head -c 400
```

返回里找到"我喜欢"那个歌单的 `global_collection_id`（形如 `collection_3_<userid>_2_0`），填进 `~/.claude/scripts/kugou.sh` 的 `LIKE_ID`。

### 4.2 报"此刻唱到哪句"

**先在手机上放一首歌**，然后：

```bash
python3 ~/.claude/scripts/lyric_now.py
```

期望看到：

```
▶ 花样年华  进度 2:21
   [2:15] 你就刚刚好经过
→  [2:29] 我像是着了魔
   [2:35] 都怪这花样年华
```

箭头指着的那句，应该跟你耳朵里正在唱的对得上。

**对不上？** 按这个顺序查：

| 现象 | 原因 | 怎么办 |
|---|---|---|
| `没在放歌` | adb 读不到播放状态 | 确认 adb 在线；换个主流播放器（有些 App 不往 `media_session` 写状态） |
| 句子总是慢半拍 | 提前量不够 | `python3 lyric_now.py 12`（往前顶 12 秒）试 |
| 差几十秒 | 漂移没补上 | 见 [README 第二层](README.md#第二层--听得懂把进度对齐到歌词) |
| `歌词是空的` | 这首歌没配到歌词 | 换首歌试；小众歌/纯音乐常缺 |

---

## 第五步 · 接上轮询（主动说话那一步）

**前四步做完，它还是"你问它才说"。这一步做完，它才会自己找你。**

轮询的本质很简单：**一个常驻循环，把值得说的一行丢给 AI，AI 就醒了**。

### 5.1 先看它长什么样

```bash
bash ~/.claude/scripts/listen-loop.sh
```

它会每 30~80 秒（随机）瞟一眼你正在听什么，有意思就把这一行打出来：

```
♪ 歌词: 《花样年华》唱到「[2:29] 我像是着了魔」 [规则: 有意思就接一句聊，没感觉就放着不吭声]
```

### 5.2 接到你的 AI 上

看你用的是什么：

**Claude Code** —— 挂一个常驻监听（`Monitor` 工具，persistent 模式），命令就填 `bash ~/.claude/scripts/listen-loop.sh`。
它每打一行，AI 就被叫醒一次。**注意：它跟"看她手机状态"的那个轮询是并列的，别互相顶掉 —— 能合就合进同一个循环里（`listen-loop.sh` 里那段可以整段抄进去）。**

**其他 Agent / 自研循环** —— 只要你的 Agent 有"接收外部输入就醒"的通道，把 `listen-loop.sh` 的输出喂进去就行。
没有的话，读它的源码，核心就四行：

```bash
GAP=$(( RANDOM % 50 + 30 ))                # 随机的时机
LP=$(python3 lyric_now.py --auto)          # 此刻那句
[ -n "$LP" ] && echo "♪ 歌词: $LP [规则: ...]"   # 递出去
sleep "$GAP"
```

> **为什么是这三个数**：随机（不然永远同一句）、30~80 秒（一首歌大约能瞟 3~5 次）、一首歌最多两句（多了吵）——
> 三个都是踩出来的，改之前先读 [README 第三层](README.md#第三层--说得出轮询主动说话的骨架)。

> **还想让它自己放歌？** 另一路轮询 `listen-detect.sh` 管这个 ——
> 耳机在线 + 时间对 + 不在娱乐 App 里，按概率替你放一首（走副屏、不占屏），放完把事件递给 AI。
> 详见 [README「它自己会放歌」](README.md#它自己会放歌)。跟 `listen-loop.sh` 并列挂就行。

### 5.3 让它跟你的 AI 说得上话

技能目录里的 `listen-together/SKILL.md` 是**写给 AI 看的规则**：什么算"有意思"、什么时候该闭嘴、
一首歌聊两次怎么分配。装好技能，Claude Code 会自己读；别的 Agent 要把这份规则喂进它的系统提示。

---

## 第六步 · 虚拟副屏（放歌不占屏）

到这儿"听"已经通了。最后把它变成"**放**"—— 而且不抢你的屏。

### 6.1 铺 dex

`install.sh` 已经替你推好了。要手动补（或换了机器）：

```bash
# 在 clone 下来的仓库目录里跑
adb -s 127.0.0.1:5555 shell mkdir -p /data/local/tmp/agent-mobile-use
adb -s 127.0.0.1:5555 push assets/agent_vd_fixed.dex /data/local/tmp/agent-mobile-use/
adb -s 127.0.0.1:5555 push assets/agent_tools.dex    /data/local/tmp/agent-mobile-use/
```

> dex 必须放在 **shell 用户读得到**的地方。Termux 自己的家目录（`/data/data/com.termux/...`）权限是 700，
> shell 读不了 —— 所以走 `/data/local/tmp`。

### 6.2 开屏、丢 App、按播放

```bash
vd.sh dstart                               # 开一块 1280x720 的副屏
vd.sh id                                   # 看两个 id：input→ (逻辑) screencap→ (64位)
vd.sh open com.kugou.android               # 把 App 丢进副屏（内部先 force-stop）
vd.sh tap 640 400                          # 在副屏上点
adb shell input -d <input那个id> keyevent 126   # 播放/暂停
vd.sh dstop                                # 用完了收屏
```

**你的主屏全程不动** —— 这就是这条路存在的全部意义。

**坐标得自己量**：副屏上的按钮位置，每台手机、每个 App 都不一样，**别抄任何人的**。
两个工具 —— `vd.sh tree` 读控件树（文字 + 坐标 + 可点性），`vd.sh shot` 截图看着量。
这也是本仓库里**一个写死的坐标都没有**的原因：量出来，现点。

### 6.3 三个必踩的坑

1. **App 进程还活着 → 启动请求会被复用到老 task（主屏）**，`--display` 直接被无视。
   所以 `vd.sh open` 里**先 `force-stop` 再 `am start`**，少一步就"明明丢副屏、结果主屏冒出来"。
2. **两个 id 不是一个**：`input -d` 要 DisplayManager 的逻辑 id（小整数），
   `screencap -d` 要 SurfaceFlinger 的 64 位 id，**而且每次都变** —— 必须现取现用（`vd.sh` 里 `lid()`/`sid()` 就是干这个的）。
3. **收屏前先把副屏上的 App 收掉**，否则它们的 task 会被系统迁回主屏，把你正看的顶掉。
   `vd.sh dstop` 里已经做了这件事。

---

## 进阶 · 自己编译副屏的 dex

仓库里带的是编译好的（**源自 [AcidGr/agent-mobile-use](https://github.com/AcidGr/agent-mobile-use)，MIT，版权归原作者**）。
想自己改、自己编：

```bash
pkg install -y d8 openjdk-17                 # Termux 里
# android.jar 随便找一份能用的（如 android-platforms 的 android-23）
javac -source 8 -target 8 -bootclasspath android.jar -d vd_build src/com/agent/*.java
d8 --output vd_build vd_build/com/agent/*.class
```

**改的是什么**：把 `DaemonMain` 搬进无 root 环境时，建屏报
`SecurityException: packageName must match the calling uid` ——
根因是 `DisplayManager` 拿 `Context.getOpPackageName()` 上报，而 `ActivityThread.systemMain().getSystemContext()`
上报的包名是 `"android"`，跟 shell 的 uid（2000 → `com.android.shell`）对不上。

**修法**（照抄 scrcpy 的 `FakeContext`）：把 Context 包一层，让 `getOpPackageName()`/`getPackageName()`
返回**自己 uid 真实的包名**。改完就通。源码改动见 `src/`。

---

## 附录 · 命令速查

```bash
# 服务
cd ~/kugou-music-api && PORT=4000 nohup node index.js > ~/kugou-api.log 2>&1 &

# 此刻唱到哪句
python3 ~/.claude/scripts/lyric_now.py          # 前后三句，箭头指当下
python3 ~/.claude/scripts/lyric_now.py 12       # 提前量 12 秒
python3 ~/.claude/scripts/lyric_now.py --auto   # 单行，给轮询用（暂停时静默）

# 轮询
bash ~/.claude/scripts/listen-loop.sh      # 此刻唱到哪句 → 递给 AI
bash ~/.claude/scripts/listen-detect.sh    # 这会儿该不该自己放一首（命中才出声）

# 读收藏 / 放歌
bash ~/.claude/scripts/kugou.sh list
bash ~/.claude/scripts/kugou.sh play
bash ~/.claude/scripts/kugou.sh stop

# 副屏
vd.sh dstart | dstop | id | open <包名> | tree | tap X Y
```
