# Fpk — fnOS 应用打包仓库

使用飞牛 fnOS **官方打包方式**（官方 `fnpack` 工具 + 官方应用包结构）构建应用的 `.fpk` 安装包，不依赖第三方打包脚本或自定义 FPK 格式。

- 官方文档：<https://developer.fnnas.com/>
- 本仓库文档：[`docs/`](docs/README.md) —— 完整官方开发文档 + 打包经验补充（[`docs/fnos-packaging-notes.md`](docs/fnos-packaging-notes.md)）

## 应用

| 应用 | `appname` | 访问端口 | 默认账号 | Release 标签 |
| --- | --- | --- | --- | --- |
| Emby Server | `embyserver` | 8096 | — | `emby-v*` |
| qBittorrent | `qbittorrent` | 58085（WebUI）/ 58080（BT） | `admin` / `adminadmin` | `qbittorrent-v*` |

产物与发布见 [Releases](https://github.com/tardlk/Fpk/releases)。

> qBittorrent 的 WebUI 端口为 `58085`，BT 监听（上传/下载）端口为 `58080`。BT 端口如需外网使用，请在路由器/防火墙自行放行或映射。

## 目录结构

```
embyserver/ qbittorrent/        # 官方 fnpack 项目（manifest/config/cmd/wizard/图标）
src/<应用>/app/                  # fnOS 专属覆盖层（启动器、默认配置、桌面入口、图标）
docs/                           # 完整官方开发文档 + 打包经验补充
scripts/
├── fetch-fnpack.sh            # 下载并校验官方 fnpack
├── build-embyserver.sh        # 下载 Emby .deb → 组装 → fnpack build
├── build-qbittorrent.sh       # 下载 qbittorrent-nox-static → 组装 → fnpack build
└── verify-fpk.sh              # 打包后的结构与架构校验
.github/workflows/
├── build-embyserver.yml
└── build-qbittorrent.yml
```

每个应用包目录下的 `app/` 是构建产物，由脚本组装，不提交。

## 构建

```bash
# 1. 下载官方 fnpack（1.2.3，按 SHA-256 校验）
./scripts/fetch-fnpack.sh

# 2. 选择应用构建（默认最新版本，x86）
./scripts/build-embyserver.sh  --arch x86
./scripts/build-qbittorrent.sh --arch arm

# 指定版本
./scripts/build-embyserver.sh  --arch x86 --version 4.10.0.40
./scripts/build-qbittorrent.sh --arch arm --version 5.2.3
```

产物输出到 `dist/<appname>.fpk`（官方 `fnpack` 命名）。安装：应用中心 → 手动安装；或 `appcenter-cli install-fpk`。

## 设计说明（对齐官方文档）

- **按架构拆包**：含原生二进制的应用不能用 `platform=all`，必须分别出 `x86` / `arm` 包。
- **最小权限**：`config/privilege` 使用专用包用户（`run-as=package`）；Emby 额外加入 `video`/`render` 组以获得硬件转码。
- **只用官方字段**：不使用 `port-config`、`systemd-unit` 等未公开字段。
- **重启契约**：Emby 依赖服务管理器在退出码 `3` 时重启，而 fnOS 不托管应用进程，因此启动器自带 supervisor（详见打包经验文档）。qBittorrent 无此需求。
- **路径与数据**：所有脚本使用 `TRIM_APPDEST`、`TRIM_PKGVAR`、`TRIM_DATA_SHARE_PATHS` 等官方变量，不硬编码路径。

### Emby 媒体库路径

Emby 以专用应用用户运行，fnOS 卷目录（`/vol1` 等）对应用用户没有“列目录”权限：**添加媒体库时请手动输入完整路径**（如 `/vol1/1000/Media`），不要使用「浏览文件夹」。格式为 `/vol{N}/{uid}/{共享文件夹名}`。详见 [`docs/fnos-packaging-notes.md`](docs/fnos-packaging-notes.md)。

## 校验与供应链

- `scripts/fetch-fnpack.sh`：按已知 **SHA-256** 校验官方 fnpack（`linux-amd64` / `darwin-amd64` / `darwin-arm64`；官方未发布 `linux-arm64`）。
- `scripts/build-*.sh`：从 GitHub Release 元数据读取上游产物（Emby `.deb` / qbittorrent-nox-static 二进制）的 **sha256 digest** 并校验；CI 中使用 `GITHUB_TOKEN` 避免 API 限流。
- `scripts/verify-fpk.sh <fpk> <arch> [可执行载荷路径...]`：校验 FPK 结构、必含项、manifest、`checksum == md5(app.tgz)`、脚本可执行位、JSON 合法性，以及所有 ELF 架构与目标平台一致。
- `.gitattributes` 强制脚本 LF（兼容 Windows/WSL 编辑）。

## GitHub Actions

| 工作流 | 应用 | 触发 |
| --- | --- | --- |
| `build-embyserver.yml` | Emby | 手动 / push（`embyserver/`、`src/`、`scripts/`）/ 每天 20:00 UTC |
| `build-qbittorrent.yml` | qBittorrent | 手动 / push（`qbittorrent/`、`src/qbittorrent/`、`scripts/`）/ 每天 20:30 UTC |

流程：下载官方 fnpack → 下载并校验上游产物 → 组装 → `fnpack build` → `verify-fpk.sh` 校验 → 发布到 Release（含工作流产物与固定标签）。

## 开发与交接

- [`AGENTS.md`](AGENTS.md)：给 AI/开发者的仓库契约与铁律（官方方式、按架构拆包、供应链校验、发布规则）。
- [`docs/fpk-handoff.md`](docs/fpk-handoff.md)：完整交接文档（结构、各应用配置、构建流程、CI 发布、新增应用 recipe、排错手册、验证方法、已知限制）。
