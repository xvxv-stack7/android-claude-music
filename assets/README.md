# assets — 第三方二进制

这里的 `.dex` **不是本项目的代码**，来自：

> **[AcidGr/agent-mobile-use](https://github.com/AcidGr/agent-mobile-use)**
> 作者：酸小明（AcidGr） · MIT 许可，全文见 [`LICENSE-agent-mobile-use`](LICENSE-agent-mobile-use)

| 文件 | 用途 | 本项目的改动 |
|---|---|---|
| `agent_vd_fixed.dex` | 建一块虚拟副屏（`DaemonMain`） | **有** —— 修了免 root 下的 `SecurityException: packageName must match the calling uid`；源码见 `../src/com/agent/DaemonMain.java` |
| `agent_tools.dex` | 副屏上读控件树 / 点按 / 灌字（`ToolMain`） | 无 |

安装脚本会把它们推到 `/data/local/tmp/agent-mobile-use/` ——
**必须是 shell 用户读得到的位置**（Termux 自己的家目录权限是 700，`app_process` 读不了）。

**版权归原作者所有。** 本项目只做了上面那一处修改，并按 MIT 保留原始许可与署名。
