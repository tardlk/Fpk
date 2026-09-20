# fnOS FPK 打包经验与注意事项

本文记录把上游 Linux 应用（以 Emby Server 为例）打包成飞牛 fnOS `.fpk` 时踩过的坑与结论，供后续打包/排错参考。

- 官方文档：<https://developer.fnnas.com/>
- 官方工具：`fnpack`（创建/打包）、`appcenter-cli`（设备上安装/管理）

---

## 1. 最重要的一条：fnOS 不会托管你的进程

**结论：fnOS 不是 systemd，它不会按退出码重启应用，也不会在崩溃后自动拉起。**

fnOS 的应用模型是：

- `appcenter` 负责安装、卸载、`cmd/main start|stop|status`、以及“应用是否在运行”的检测；
- 应用进程由 `cmd/main` 自己启动/停止，**没有 watchdog / 自动重启**；
- 运行契约只来自 `cmd/main` 的退出码（`0` 运行、`1` 失败、`3` 未运行），**没有“退出码 = 请重启我”这种约定**。

而上游发行版（deb/rpm）通常用 systemd 管理服务，常见写法：

```ini
# 上游 systemd 单元示意
Restart=on-failure
RestartForceExitStatus=3      # 进程退出码 3 → 强制重启
```

很多应用（Emby、Jellyfin、部分 Java 服务）依赖这个约定：

- 进程收到“需要重启”后，**先优雅 Disposing 再退出，并返回约定的退出码**（Emby 用 `-restartexitcode 3`）；
- 期望**服务管理器把它重新拉起**。

### 坑：移植时只改了功能，漏了“重启契约”

我们把 Emby 改成 fnOS 启动脚本时：

- ✅ 去掉了上游的 `-updatepackage`（不让它自更新）；
- ✅ 路径改用 `TRIM_*`；
- ❌ **保留了 `-restartexitcode 3`，却没有提供对应的 supervisor**；
- ❌ 启动器用 `exec`、`cmd/main` 只启动一次 → 等价于“没有服务管理器”。

于是插件更新后 Emby 空闲时自行重启退出，**再也没起来**，直到重启机器系统自启。fnOS 只在应用中心记了一条事件：

```
TRIMEVENT: {"APP_NAME":"embyserver",...,"eventId":"APP_CRASH","from":"trim.app-center"}
```

### 正确做法：在启动器里自带 supervisor

把“重启 + 停止传播”这两件 systemd 的职责做进启动器（`app/bin/<launcher>`）：

```sh
RESTART_EXIT_CODE=3
STOPPING=0
EMBY_PID=""

forward_term() {
    STOPPING=1
    [ -n "${EMBY_PID}" ] && kill -TERM "${EMBY_PID}" 2>/dev/null
}
trap forward_term TERM INT

while :; do
    "${APP_DIR}/system/EmbyServer" ... &
    EMBY_PID=$!
    wait "${EMBY_PID}"; rc=$?
    child_pid="${EMBY_PID}"; EMBY_PID=""

    # 收到 TERM/INT：转发后等待子进程退出，实现优雅停止
    [ "${STOPPING}" -eq 1 ] && { wait "${child_pid}" 2>/dev/null; exit 0; }

    # 退出码 3：应用请求重启
    [ "${rc}" -eq "${RESTART_EXIT_CODE}" ] && { sleep 2; continue; }

    exit "${rc}"
done
```

要点：

- **不要用 `set -e`**：`wait` 会返回非 0，会被误判为错误退出，破坏重启逻辑；
- 用**非 `exec` 的方式启动子进程**，才能拿到 PID、转发信号；
- 监听 `TERM/INT` 并转发，保证 `cmd/main stop` 仍能优雅停止；
- 崩溃（其它非零退出码）当前不重启；如需容错可扩展为“按退避重启 + 崩溃循环保护”。

---

## 2. 文件与路径权限：能“穿越”，不能“列目录”

### 现象

应用以**专用应用用户**运行（`config/privilege` 的 `run-as=package`），不是你的 NAS 登录用户。给应用授权共享文件夹后，在其自带界面里：

- 点“浏览/选择文件夹” → 报错，例如 Emby：
  `Access to the path '/vol1/@appshare' is denied.`
- 但**手动输入完整路径**（如 `/vol1/1000/Media`）→ 可以正常读取、添加媒体库。

### 原因

- 浏览/枚举目录需要目录的**读权限 `r`**；
- 访问一个已知路径只需要各级父目录的**执行/搜索权限 `x`**。

fnOS 的授权/ACL 通常只覆盖到共享文件夹本身及必要的路径穿越，应用用户对 `/vol1`、`/vol1/1000` 往往**没有 `r`（不能列目录）**，所以：

- 浏览枚举失败；
- 手填完整路径可用（只需要 `x`）。

> 若应用用户连 `x` 都没有，手填也会失败。可用下面的命令确认。

### 路径格式

共享文件夹完整路径为：

```
/vol{N}/{uid}/{共享文件夹名}
```

- `{N}`：卷号（`/vol1`、`/vol2` …）
- `{uid}`：用户 ID 目录，通常为 `1000`

查找真实路径：

```bash
find /vol* -maxdepth 2 -name "你的共享文件夹名"
```

### 验证权限（SSH）

```bash
ls -ld /vol1 /vol1/@appshare /vol1/1000 /vol1/1000/<目录>
sudo -u <应用用户> ls /vol1/1000          # 能否列目录
sudo -u <应用用户> ls /vol1/1000/<目录>    # 能否访问目标
```

常见结果：第一条 `ls` 报错、第二条成功 → 即“浏览不行、手填可行”。

### 打包建议

- 在 `manifest.desc`、安装向导（`wizard/install`）和 README 里**明确提示用户手动输入完整路径**；
- 启动器的 `-defaultdirectory`（或等价默认目录）优先指向 `TRIM_DATA_SHARE_PATHS` / `TRIM_DATA_ACCESSIBLE_PATHS`；
- 不要试图在应用内调用 fnOS 原生目录选择器——那需要 `micro_app=true` + 开放 API JS SDK（`pickUserFile`/`pickSharedFile`），只适用于“应用页面是微应用”的形态，普通自带 Web UI 的原生服务用不了。

---

## 3. 打包与工程实践

### 平台必须按架构拆包

`manifest.platform` 为 `x86` / `arm` / `all`。**只要包内含该架构的原生二进制，就不能用 `all`**，必须分别出包。`fnpack` 本身可在任意架构主机上打包（它只是组包，不编译）。

### 只用官方字段

避免使用未公开字段（例如社区包里的 `port-config`、`systemd-unit`）。官方文档明确支持的字段/文件之外的写法，可能随 fnOS 版本失效。

### `fnpack` 的行为

- `fnpack create <app>` 生成官方骨架；`fnpack build` 产出 `<appname>.fpk`；
- 打包时由 `fnpack` 写入 `manifest.checksum`，**不会回写源 `manifest`**；
- 会把 `app/` 内容安装到 `target/`。

### Windows / WSL 协作

- 在 Windows 侧编辑、WSL 侧构建时，务必加 `.gitattributes` 强制脚本 LF：
  ```
  * text=auto eol=lf
  cmd/* text eol=lf
  ```
  否则 CRLF 会让 `#!/bin/bash` 变成 `/bin/bash^M`，`cmd/*` 直接执行失败；
- Git 会保留可执行位，但若用 Windows 工具重新 `git add`，可能丢失；CI 构建前可 `chmod +x cmd/* bin/<launcher>` 兜底。

### 卸载清理

`rm -rf "$dir"/*` 不会删除点文件。用：

```bash
find "$dir" -mindepth 1 -delete
```

### 停止时清理子进程

若应用会派生转码等子进程，停止后按**用户范围**清理，避免误杀其它实例：

```bash
pkill -u "$TRIM_USERNAME" -x <ProcessName> 2>/dev/null || true
```

---

## 4. 供应链与校验（建议纳入 CI）

- **固定工具链**：`fnpack` 按已知 SHA-256 校验后再使用。注意官方当前**未发布 `linux-arm64` 版**（文档里的链接会 404）。
- **校验上游产物**：Emby 的 GitHub Release 提供 `.deb` 的 `digest`（sha256），下载后校验；无 digest 时至少打印实际 sha256。
- **打包后做契约校验**：合法 tar.gz、必含 `manifest/app.tgz/cmd/config/ICON*`、`checksum == md5(app.tgz)`、脚本可执行位、JSON 合法、**所有 ELF 架构与 `platform` 一致**。
- CI 里用 `GITHUB_TOKEN` 调用 GitHub API，避免匿名 60 次/小时的限流。

---

## 5. 排错方法与日志位置（本次案例）

### 常用日志位置

| 内容 | 路径 |
| --- | --- |
| 应用中心事件/错误 | `/var/log/trim_app_center/info.log`、`error.log` |
| 系统日志（fnOS 用它，`journalctl` 常为空） | `/var/log/syslog` |
| 应用生命周期/安装日志 | `/var/log/apps/<appname>.log` |
| 应用运行数据/自身日志 | `/vol{n}/@appdata/<appname>/` |
| 应用文件 | `/vol{n}/@appcenter/<appname>/` |

### 本次排查步骤（可复用）

1. 确认进程与启动时间：
   `pgrep -a EmbyServer`、`ps -o pid,lstart,etime -p <pid>`
2. 看应用自身日志尾部的退出原因（Emby：`@appdata/embyserver/logs/embyserver*.txt`）
3. 判断是“优雅退出”还是“崩溃”：出现 `Main: Shutdown complete` → 是收到信号/主动重启
4. 查系统事件：
   `grep -i embyserver /var/log/syslog` → 找到 `eventId":"APP_CRASH"`
5. 排除 OOM：`dmesg -T | grep -i 'killed process'`
6. 排除重启：`uptime -s`、`last -x reboot`

### 本次时间线（2026-09-20）

```
11:15:58  安装后启动 Emby
11:17:43  插件自动更新 → "Emby Server needs to be restarted."
12:32:43  空闲自动重启 → Shutdown complete（退出码 3，等待被拉起）
12:33:09  fnOS 记录 APP_CRASH（应用中心发现进程不在）
13:54/13:59  NAS 重启
14:00:11  开机自启，Emby 恢复
```

根因：**应用以退出码 3 请求重启，但 fnOS 不托管进程、包内也没有 supervisor**。

---

## 6. 打包/发布检查清单

- [ ] 用官方 `fnpack create` 骨架，未引入非官方字段
- [ ] `manifest` 字段完整；含原生二进制时 `platform` 按架构拆包
- [ ] `config/privilege` 使用最小权限（优先 `run-as=package`）
- [ ] `cmd/main` 正确实现 `start/stop/status`（`0/1/3`）
- [ ] **启动器处理上游的重启/停止契约**（退出码重启、信号转发）
- [ ] 需要文件访问时，在 `desc`/安装向导/README 说明“先授权目录、手填完整路径”
- [ ] 图标：根 `ICON.PNG`(64) + `ICON_256.PNG`(256)，入口 `icon_{0}.png`
- [ ] `.gitattributes` 保证脚本 LF；可执行位正确
- [ ] CI：固定 fnpack 哈希、校验上游产物、打包后做结构/架构/校验和验证
- [ ] 发布产物含 `.fpk`，并在真实设备上验证安装 → 启动 → 状态 → 停止 → 卸载
