# AGENTS.md — 本仓库给 AI/开发者接手用的说明

本仓库用**飞牛 fnOS 官方方式**（官方 `fnpack` 工具 + 官方应用包结构）把上游软件打包成 `.fpk`。
当前维护两个应用：`Emby Server`（`embyserver`）与 `qBittorrent`（`qbittorrent`）。

> 详细交接文档见 [`docs/fpk-handoff.md`](docs/fpk-handoff.md)。动手前先读它。

## 目录速览

```
embyserver/ qbittorrent/     # 官方 fnpack 项目（manifest/config/cmd/wizard/图标）
  app/                        # 构建产物，由脚本组装，.gitignore 忽略，不提交
src/<app>/app/               # fnOS 专属覆盖层（启动器/默认配置/ui/图标），构建时叠加
scripts/
  fetch-fnpack.sh            # 下载并 SHA-256 校验官方 fnpack
  build-embyserver.sh        # 下载 Emby .deb → 组装 → fnpack build
  build-qbittorrent.sh       # 下载 qbittorrent-nox-static → 组装 → fnpack build
  verify-fpk.sh              # 打包后结构/架构校验
docs/
  fnos-packaging-notes.md    # 打包经验与踩坑（必读）
  fnos-developer-docs/       # 官方开发文档镜像（完整）
  fpk-handoff.md             # 本文件对应的详细交接文档
.github/workflows/build-<app>.yml
README.md  .gitattributes  .gitignore
```

## 铁律

1. **只用官方方式**：官方 `fnpack` + 官方包结构/字段；不使用 `port-config`、`systemd-unit` 等未公开字段。
2. **按架构拆包**：含原生二进制必须 `platform=x86` / `arm` 分开出包，不能用 `all`。CI 会按矩阵覆盖 `platform`。
3. **`app/` 是产物**：由 `scripts/build-*.sh` 生成，绝不提交；`src/<app>/app/` 才是源码。
4. **供应链校验**：fnpack 按固定 SHA-256；上游 `.deb`/二进制按 GitHub Release 的 `sha256 digest` 校验。改动时不要削弱校验。
5. **发布靠 Release**：CI push 触发（改动相关路径），产物上传为工作流 artifact 并创建 Release（标签 `emby-v*` / `qbittorrent-v*`、资产 `<appname>_<version>_<arch>.fpk`）。
6. **不要提交密钥**：文档/脚本用占位符（`$NAS_IP`、`$MP_TOKEN` 等）。
7. **LF**：脚本必须 LF（`.gitattributes` 已强制）；Windows/WSL 编辑后注意可执行位。

## 常用命令

```bash
./scripts/fetch-fnpack.sh                       # 下载校验 fnpack（1.2.3）
./scripts/build-embyserver.sh  --arch x86       # 构建 Emby（默认最新版）
./scripts/build-qbittorrent.sh --arch arm       # 构建 qBittorrent
./scripts/verify-fpk.sh dist/embyserver.fpk x86 bin/emby-server
git add -A && git commit -m "..." && git push origin main   # push 触发 CI 发布
```

## 关键事实（易忘）

- fnOS **不托管应用进程**：上游若“退出码 3 请求重启”，必须由启动器自带 supervisor（Emby 已实现）。
- 应用以专用用户运行，`/vol` 卷目录**能穿越不能列目录** → 媒体库要**手动输入完整路径**。
- Emby 启动器：`src/embyserver/app/bin/emby-server`（supervisor + 转发 TERM）。
- qBittorrent：`cmd/main` 直接跑 `qbittorrent-nox`，`cmd/install_callback` 生成默认配置（admin/adminadmin，WebUI 58085，BT 58080）。
- GitHub API 基址要含 `/releases`（曾因缺失导致校验静默失败）。
