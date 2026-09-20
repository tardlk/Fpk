# Fpk — Emby Server for fnOS

使用飞牛 fnOS **官方打包方式**（官方 `fnpack` 工具 + 官方应用包结构）构建 Emby Server 的 `.fpk` 安装包。

本项目不依赖任何第三方打包脚本或自定义 FPK 格式，完全遵循官方开发文档：
<https://developer.fnnas.com/docs/quick-started/create-application/>

> 文档见 [`docs/`](docs/README.md)：包含**完整官方开发文档**（`docs/fnos-developer-docs/`）与**打包经验补充**（`docs/fnos-packaging-notes.md`，含“fnOS 不托管进程”“媒体路径权限”等）。

## 打包逻辑

```
src/app/                      # fnOS 专属覆盖层（源码维护）
├── bin/emby-server           # 启动器：适配 TRIM_* 路径，去掉上游自更新
└── ui/                        # 桌面入口配置与图标
    ├── config
    └── images/{icon_64,icon_256}.png

embyserver/                   # 官方 fnpack 项目（fnpack create 生成）
├── manifest                  # 应用元数据
├── ICON.PNG / ICON_256.PNG   # 包图标（取自 Emby 官方图标）
├── config/{privilege,resource}
├── cmd/                      # 生命周期脚本
├── wizard/{install,uninstall} # 安装提示 / 卸载向导（是否删除数据）
└── app/                      # 运行文件（由构建脚本生成，不提交）

scripts/
├── fetch-fnpack.sh           # 下载官方 fnpack
└── build.sh                  # 拉取 Emby .deb → 组装 → fnpack build
```

构建时：

1. 用 `curl` 下载 Emby 官方 `.deb`（`MediaBrowser/Emby.Releases`）。
2. `ar -x` + `tar -xf data.tar.xz` 解包，取出 `opt/emby-server`。
3. 把 `bin etc extra lib licenses share system` 放入 `embyserver/app/`（即安装后的 `target/`）。
4. 用 `src/app/` 覆盖 fnOS 专属文件（启动器、入口配置、图标）。
5. 改写 `manifest` 的 `version` / `platform`。
6. 运行官方 `fnpack build` 生成 `.fpk`。

## 使用

```bash
# 1. 下载官方 fnpack（1.2.3）
./scripts/fetch-fnpack.sh

# 2. 构建（默认最新版，x86）
./scripts/build.sh

# 指定架构 / 版本
./scripts/build.sh --arch arm
./scripts/build.sh --arch x86 --version 4.10.0.40
```

产物输出到 `dist/embyserver.fpk`（官方 `fnpack` 的命名方式）。

安装到 fnOS：应用中心 → 手动安装，选择该 `.fpk`；或使用 `appcenter-cli install-fpk`。
安装后通过 `http://<NAS-IP>:8096` 或桌面 Emby 图标访问。

## 媒体库路径与授权

Emby 以专用应用用户 `embyserver` 运行（不是你的 NAS 登录用户），而 fnOS 卷目录（`/vol1`、`/vol2` 等）对应用用户没有“列目录”权限。因此：

1. **先授权目录**：在 fnOS「应用设置 → 授权目录」中，把要作为媒体库的共享文件夹授权给 Emby。
2. **添加媒体库时手动输入完整路径**：在 Emby 中添加媒体库时，**不要点击「浏览文件夹」**（浏览会因权限被拒，报 `Access to the path '/vol1/@appshare' is denied.`），而是直接填写完整路径，例如：

   ```
   /vol1/1000/Media
   ```

3. **路径格式**为 `/vol{N}/{uid}/{共享文件夹名}`，其中 `{N}` 是卷号、`{uid}` 是用户 ID 目录（通常为 `1000`）。可用 SSH 查找真实路径：

   ```bash
   find /vol* -maxdepth 2 -name "你的共享文件夹名"
   ```

> 说明：这是 fnOS 的权限模型导致的（应用用户可“穿越”路径但无“列目录”权限），并非本包缺陷；社区同类包（如 Plex）也采用“手动输入完整路径”的方式。fnOS 的原生目录选择器需要应用声明 `micro_app=true` 并使用开放 API，不适用于 Emby 自带的管理界面。

上述提示同样写在 `manifest` 的应用描述与应用安装向导（`wizard/install`）中。

## 设计说明（对齐官方文档）

- **平台**：Emby 自带原生二进制，因此 `platform` 必须按架构分别打包（`x86` / `arm`），不能使用 `all`。
- **运行身份**：`config/privilege` 使用专用包用户 `embyserver`，并通过 `join-groups: ["video", "render"]` 获得硬件转码所需的设备访问能力。
- **路径**：所有脚本使用 `TRIM_APPDEST`、`TRIM_PKGVAR`、`TRIM_DATA_SHARE_PATHS` 等官方环境变量，不硬编码安装路径。
- **数据**：Emby 的运行数据保存在 `TRIM_PKGVAR`；`config/resource` 声明 `embyserver` 共享目录，作为默认媒体库目录。
- **入口**：`app/ui/config` 使用端口入口（`service_port=8096`）。
- **启停**：`cmd/main` 按官方约定实现 `start`/`stop`/`status`（运行返回 0，未运行返回 3）。
- **重启自愈**：`app/bin/emby-server` 作为 Emby 的 supervisor。Emby 在插件更新等场景下会以退出码 `3`（`restartexitcode`）请求重启，期望由服务管理器拉起；fnOS 不托管应用进程，因此由启动器自动重启，并转发 `TERM/INT` 保证 `cmd/main stop` 仍能优雅停止。
- **不做的非官方行为**：不修改 FPK 格式、不写入自定义 `checksum`、不使用 `port-config`/`systemd-unit` 等未公开字段。

## GitHub Actions 自动构建

`.github/workflows/build.yml` 负责在云端用官方 `fnpack` 构建并发布：

- **手动触发**：可选择架构（`both` / `x86` / `arm`）和指定 Emby 版本。
- **push 到 main**：当 `embyserver/`、`src/`、`scripts/` 或工作流本身变化时重建。
- **定时任务**：每天 `20:00 UTC` 检查 Emby 新版本；该版本已发布则跳过。

流程：下载官方 fnpack → 下载 Emby `.deb` → 组装 `embyserver/` → `fnpack build` → **`scripts/verify-fpk.sh` 校验** → 把 `embyserver_<version>_<arch>.fpk` 上传为工作流产物并发布到 Release（标签 `emby-v<version>`）。

## 校验与供应链

- `scripts/fetch-fnpack.sh`：按已知 **SHA-256** 校验官方 fnpack 1.2.3（`linux-amd64` / `darwin-amd64` / `darwin-arm64`）。官方当前未发布 `linux-arm64` 版，脚本会明确报错。
- `scripts/build.sh`：从 GitHub Release 元数据读取 Emby `.deb` 的 **sha256 digest** 并校验下载文件；无 digest 时至少打印实际 sha256。
- `scripts/verify-fpk.sh`：打包后校验 FPK 结构、必含项、manifest 字段、`checksum == md5(app.tgz)`、脚本可执行位、JSON 合法性，以及 **所有 ELF 架构与目标平台一致**。

## 更新版本

```bash
./scripts/build.sh --version <新版本>
```

同步更新 `embyserver/manifest` 中的 `version`（构建脚本会自动写入）与 `README` 中的上游链接即可。
