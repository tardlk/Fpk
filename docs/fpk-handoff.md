# Fpk 打包仓库交接文档

> 面向接手的 AI / 开发者。目标：不依赖口头上下文，也能独立继续打包/修复/发布 fnOS `.fpk`。
> 仓库：`https://github.com/tardlk/Fpk`

---

## 1. 目标与范围

用**飞牛 fnOS 官方方式**产出 `.fpk`：官方 `fnpack` 工具 + 官方应用包结构/字段，不手搓 FPK、不用未公开字段。

当前维护两个应用：

| 应用 | `appname` | 上游 | 端口 | Release |
| --- | --- | --- | --- | --- |
| Emby Server | `embyserver` | `MediaBrowser/Emby.Releases`（官方 `.deb`） | 8096 | `emby-v*` |
| qBittorrent | `qbittorrent` | `userdocs/qbittorrent-nox-static`（静态二进制） | WebUI 58085 / BT 58080 | `qbittorrent-v*` |

---

## 2. 目录与职责

```
embyserver/ qbittorrent/
  manifest config/ cmd/ wizard/ ICON*.PNG   # 官方 fnpack 项目（提交）
  app/                                       # 组装产物（gitignore，不提交）
src/<app>/app/                               # fnOS 覆盖层源码（提交）
  embyserver: bin/emby-server（supervisor 启动器）、ui/
  qbittorrent: defaults/qBittorrent.conf.tpl、ui/
scripts/
  fetch-fnpack.sh        # 下载并按固定 SHA-256 校验官方 fnpack
  build-embyserver.sh    # Emby: 下载 deb → 解包 → 组装 → fnpack build
  build-qbittorrent.sh   # qBittorrent: 下载静态二进制 → 组装 → fnpack build
  verify-fpk.sh          # 产物契约校验
docs/
  fnos-packaging-notes.md    # 打包经验/踩坑（强烈建议先读）
  fnos-developer-docs/       # 官方开发文档离线镜像（ALL_DOCS.md + 分页）
.github/workflows/build-<app>.yml
```

`.gitignore` 忽略：`/fnpack`、`/build/`、`/dist/`、`/embyserver/app/`、`/qbittorrent/app/`、`*.deb`、`*.fpk`。

---

## 3. 权威资料（本地已有）

- 官方开发文档镜像：`docs/fnos-developer-docs/`（同步自 developer.fnnas.com，覆盖 `/docs/` 与 `/api/`）。
- 打包经验与坑：`docs/fnos-packaging-notes.md`。**必读三条**：
  1. **fnOS 不托管应用进程** —— 上游“退出码 3 请求重启”需启动器自带 supervisor（Emby 就是）；
  2. **媒体/文件路径权限** —— 应用用户对 `/vol` 只能穿越不能列目录，媒体库要**手动输入完整路径**；
  3. 供应链校验、Windows/WSL 的 LF 与可执行位、卸载清理等。

---

## 4. 各应用的包配置

### Emby（`embyserver/`）
- `manifest`：`appname=embyserver`、`platform=x86`（CI 覆盖）、`service_port=8096`、`ctl_stop=true`、`desktop_applaunchname=embyserver.Application`、`desc`/`changelog` 含使用提示。
- `config/privilege`：`run-as=package`，用户/组 `embyserver`，`join-groups:["video","render"]`（硬解）。
- `config/resource`：`data-share: embyserver`。
- `cmd/main`：启动 `${TRIM_APPDEST}/bin/emby-server`，PID/端口探活/TERM→KILL；`pkill -u $TRIM_USERNAME -x EmbyServer` 兜底。
- 启动器 `src/embyserver/app/bin/emby-server`：**supervisor** —— Emby 退出码 3 时自动重启、转发 TERM/INT；设置 `LD_LIBRARY_PATH` 等并 `exec system/EmbyServer`。
- `cmd/install_callback` / `upgrade_*`：仅建目录；`uninstall_callback` 按 `wizard_delete_data` 清理（`find -delete`）。

### qBittorrent（`qbittorrent/`）
- `manifest`：`appname=qbittorrent`、`service_port=58085`、`platform` 占位（CI 覆盖）、`desc`/`changelog` 记录端口与默认账号。
- `config/privilege`：`run-as=package`，用户/组 `qbittorrent`。
- `config/resource`：`data-share: qbittorrent`。
- `cmd/main`：直接运行 `${TRIM_APPDEST}/bin/qbittorrent-nox --profile=$TRIM_PKGVAR --webui-port=$TRIM_SERVICE_PORT`；探活端口；`pkill -u "$TRIM_USERNAME" -x qbittorrent-nox` 兜底。
- `cmd/install_callback`：从 `src` 覆盖层模板生成 `TRIM_PKGVAR/qBittorrent/config/qBittorrent.conf`（替换日志/共享目录/端口），创建下载目录，chown 给应用用户；模板含 WebUI 端口 58085、`Session\Port=58080`、`admin/adminadmin` 的 PBKDF2、关闭 CSRF/HostHeader 以适配反代。
- `wizard/{install,uninstall}`：安装提示 + 卸载是否删数据。

---

## 5. 构建流程（`scripts/build-*.sh`）

通用步骤：
1. `fetch-fnpack.sh`：下载官方 `fnpack 1.2.3` 并校验 SHA-256（`linux-amd64`/`darwin-amd64`/`darwin-arm64`；官方**未发布 `linux-arm64`**，需 `FNPACK_SHA256` 覆盖）。
2. 解析上游版本；下载产物并校验 **sha256 digest**（CI 用 `GITHUB_TOKEN` 免限流）。
3. 组装 `app/`：拷贝上游 payload → 叠加 `src/<app>/app/`（启动器/默认配置/ui/图标）→ 保证脚本可执行位。
4. `sed` 改写 `manifest` 的 `version` / `platform`。
5. `fnpack build --directory <app>` → `dist/<appname>.fpk`。

### Emby
- 上游：`https://github.com/MediaBrowser/Emby.Releases`（tag=版本号）；资产 `emby-server-deb_<ver>_<amd64|arm64>.deb`。
- `jar`? 不：`ar -x` + `tar -xf data.tar.xz`，取 `opt/emby-server`，把 `bin etc extra lib licenses share system` 放进 `app/`。
- 注意：GitHub API 基址必须包含 `/releases`（`.../Emby.Releases/releases/latest`、`.../releases/tags/<ver>`）；曾因漏写 `/releases` 导致 digest 校验静默失败。

### qBittorrent
- 上游：`userdocs/qbittorrent-nox-static`；tag 形如 `release-5.2.3_v2.0.14`，从中解析应用版本 `5.2.3`。
- 资产：`x86_64-qbittorrent-nox` / `aarch64-qbittorrent-nox`；放到 `app/bin/qbittorrent-nox`。
- 注意：指定版本时 releases 列表 URL 不能写成 `.../releases/releases`（曾因此 CI 必挂）。

### 校验（`scripts/verify-fpk.sh`）

```
scripts/verify-fpk.sh <fpk> <x86|arm> [可执行载荷路径 ...]
```
校验：合法 tar.gz、必含 `manifest/app.tgz/cmd/{main,install_*,uninstall_*,upgrade_*}/config/{privilege,resource}/ICON*.PNG`、
`manifest.platform` 与目标一致、`checksum == md5(app.tgz)`、`cmd/*` 可执行、JSON 合法、
payload 基础项（`ui/config`、`ui/images/icon_{64,256}.png`）与额外可执行载荷存在、
以及 `system/lib/bin/extra` 下所有 ELF 架构匹配目标平台。

---

## 6. fnpack 行为要点

- `fnpack create <app> [--template docker] [--without-ui true]` 生成官方骨架。
- `fnpack build --directory <dir>` 组包；**不会回写源 `manifest`**；会写入 `manifest.checksum`（`app.tgz` 的 MD5）。
- 打包主机架构与目标架构无关（它只是 tar 组包，不编译）。
- `app/` 内容安装到 `/var/apps/<app>/target/`。

---

## 7. CI 与发布

每个应用一个工作流：`.github/workflows/build-<app>.yml`。

- 触发：`workflow_dispatch`（可选版本、`arch: both|x86|arm`）；push 到 `main`（路径过滤：对应 app 目录、`src/**`、`scripts/**`、工作流本身）；每天定时（Emby `0 20 * * *`、qBittorrent `30 20 * * *`，定时若该版本已发布则跳过）。
- 结构：`prepare`（解析版本/tag/should_build/矩阵）→ `build`（矩阵 `arch`，`chmod +x` 兜底 → `fetch-fnpack.sh` → `build-*.sh` → `verify-fpk.sh` → 重命名 `dist/<appname>_<ver>_<arch>.fpk` → 上传 artifact）→ `release`（下载 artifacts → `gh release create/upload`）。
- 权限：`contents: write`；使用 `secrets.GITHUB_TOKEN`。
- 标签/资产：`emby-v<ver>` → `embyserver_<ver>_<arch>.fpk`；`qbittorrent-v<ver>` → `qbittorrent_<ver>_<arch>.fpk`。

已发布：`emby-v4.10.0.40`（x86 354MB / arm 136MB）、`qbittorrent-v5.2.3`（x86 31.4MB / arm 31.3MB）。

### 新增第三个应用（recipe）

1. `./fnpack create <appname>`（或手工造官方结构）。
2. 写 `src/<appname>/app/` 覆盖层（启动器/默认配置/ui/图标）。
3. 写 `scripts/build-<appname>.sh`：参照现有两个脚本（下载校验 → 组装 `app/` → 叠加 `src/` → 改 manifest → `fnpack build`）。
4. `.gitignore` 加 `/<appname>/app/`。
5. 新增 `.github/workflows/build-<appname>.yml`（复制现有、改 app 名/路径/标签/端口）。
6. `README.md` 增行；本地跑一遍 build + `verify-fpk.sh`，push 触发 CI。

---

## 8. 排错手册

| 现象 | 原因/处理 |
| --- | --- |
| Emby 在插件更新后退出且不再启动 | 上游以退出码 3 请求重启，fnOS 不托管进程 → 启动器须有 supervisor（`src/embyserver/app/bin/emby-server`） |
| Emby 里加媒体库浏览报 `Access to the path '/vol1/@appshare' is denied` | 应用用户无列目录权限 → 手动输入完整路径 `/vol{N}/{uid}/{share}`（打包经验文档有详解） |
| CI 报 GitHub API 404 / 校验被跳过 | 检查 API 基址是否含 `/releases` |
| CI 构建失败在 “Build FPK” | 看脚本下载/校验/解包；qBittorrent 指定版本时注意 releases URL |
| `verify-fpk.sh` 报 ELF 架构不符 | 上游产物架构不对（x86 应为 `x86-64`、arm 为 `aarch64`） |
| 无法拉取上游 / API 限流 | 设置 `GITHUB_TOKEN`；或本地用 `EMBY_RELEASES_API`/`QBIT_RELEASES_API` 覆盖（测试用 `file://` 亦可） |
| Windows 编辑后脚本报 `bash^M` | `.gitattributes` 强制 LF；必要时 `chmod +x` |
| 需要 linux-arm64 的 fnpack | 官方未发布；`FNPACK_SHA256` + 可信二进制 |

设备侧排查可用 SSH + Docker（若目标 NAS 用容器）：查看 `/var/apps/<app>/`、`$TRIM_PKGVAR` 日志、`appcenter` 事件；安装用 `appcenter-cli install-fpk` 或应用中心手动安装。

---

## 9. 验证方法（接手建议）

1. 本地：`./scripts/fetch-fnpack.sh` → `./scripts/build-<app>.sh --arch x86 --version <v>` → `./scripts/verify-fpk.sh dist/<appname>.fpk x86 <launcher>`。
2. 抽查 FPK：`tar -tzf` 看顶层；`tar -xzf ... -O manifest`；`tar -xzf ... -O app.tgz | tar -tzf -` 看 payload。
3. 设备：应用中心手动安装 `.fpk`；验证桌面入口、端口、启停/状态、日志与数据目录。

---

## 10. 已知限制 / TODO

- 目前仅 Emby 与 qBittorrent；可扩展更多应用（见 §7 recipe）。
- `embyserver/manifest` 中 `platform` 与 `qbittorrent/manifest` 中 `platform` 为**提交时的占位值**，构建脚本/CI 会按目标架构覆盖（qbittorrent 当前文件里是 `arm`，正常现象）。
- 图标取自各自上游/官方 logo（Emby 用 `dashboard-ui` 的 512 图标缩放；qBittorrent 用上游 256 图标），如需上架可能有圆角规范要求。
- Emby 媒体库路径授权说明已写进 `desc` + 安装向导 + README，但无法在 Emby 界面内调用 fnOS 原生目录选择器（需 `micro_app`，与本形态不符）。
- `docs/fnos-developer-docs/` 是官方文档的**静态镜像**，不会自动同步；需要时从官方站点重新抓取更新。

---

## 11. 安全

- 不提交 `fnpack` 二进制、`build/`、`dist/`、`app/` 与 `*.deb/*.fpk`（已在 `.gitignore`）。
- 不提交任何密钥；文档/脚本一律用占位符。
- 保持供应链校验：fnpack 固定 SHA-256；上游产物按 Release `digest` 校验。
