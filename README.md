# Fpk — Emby Server for fnOS

使用飞牛 fnOS **官方打包方式**（官方 `fnpack` 工具 + 官方应用包结构）构建 Emby Server 的 `.fpk` 安装包。

本项目不依赖任何第三方打包脚本或自定义 FPK 格式，完全遵循官方开发文档：
<https://developer.fnnas.com/docs/quick-started/create-application/>

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
├── wizard/uninstall          # 卸载向导（是否删除数据）
└── app/                      # 运行文件（由构建脚本生成，不提交）

scripts/
├── fetch-fnpack.sh           # 下载官方 fnpack
└── build.sh                  # 拉取 Emby .deb → 组装 → fnpack build
```

构建时：

1. 用 `curl` 下载 Emby 官方 `.deb`（`MediaBrowser/Emby.Releases`）。
2. `ar -x` + `tar -xf data.tar.xz` 解包，取出 `opt/emby-server`。
3. 把 `bin etc ex lib licenses share system` 放入 `embyserver/app/`（即安装后的 `target/`）。
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

## 设计说明（对齐官方文档）

- **平台**：Emby 自带原生二进制，因此 `platform` 必须按架构分别打包（`x86` / `arm`），不能使用 `all`。
- **运行身份**：`config/privilege` 使用专用包用户 `embyserver`，并通过 `join-groups: ["video", "render"]` 获得硬件转码所需的设备访问能力。
- **路径**：所有脚本使用 `TRIM_APPDEST`、`TRIM_PKGVAR`、`TRIM_DATA_SHARE_PATHS` 等官方环境变量，不硬编码安装路径。
- **数据**：Emby 的运行数据保存在 `TRIM_PKGVAR`；`config/resource` 声明 `embyserver` 共享目录，作为默认媒体库目录。
- **入口**：`app/ui/config` 使用端口入口（`service_port=8096`）。
- **启停**：`cmd/main` 按官方约定实现 `start`/`stop`/`status`（运行返回 0，未运行返回 3）。
- **不做的非官方行为**：不修改 FPK 格式、不写入自定义 `checksum`、不使用 `port-config`/`systemd-unit` 等未公开字段。

## GitHub Actions 自动构建

`.github/workflows/build.yml` 负责在云端用官方 `fnpack` 构建并发布：

- **手动触发**：可选择架构（`both` / `x86` / `arm`）和指定 Emby 版本。
- **push 到 main**：当 `embyserver/`、`src/`、`scripts/` 或工作流本身变化时重建。
- **定时任务**：每天 `20:00 UTC` 检查 Emby 新版本；该版本已发布则跳过。

流程：下载官方 fnpack → 下载 Emby `.deb` → 组装 `embyserver/` → `fnpack build` → 把 `embyserver_<version>_<arch>.fpk` 上传为工作流产物并发布到 Release（标签 `emby-v<version>`）。

## 更新版本

```bash
./scripts/build.sh --version <新版本>
```

同步更新 `embyserver/manifest` 中的 `version`（构建脚本会自动写入）与 `README` 中的上游链接即可。
