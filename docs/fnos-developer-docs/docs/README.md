# 飞牛开发文档镜像

该目录由脚本自动从 `https://developer.fnnas.com` 抓取并转换为 GitHub 友好的 Markdown，覆盖开发文档（`/docs/`）与开放 API（`/api/`）两部分。

- 单文件合集: [../ALL_DOCS.md](../ALL_DOCS.md)

## 目录

### 入口

- [欢迎加入飞牛应用开发者平台](guide.md)

### 开放 API

- [概述](api/overview.md)
- [调用方式](api/calling.md)
- [平台配置](api/platform-config.md)
- [授权与文件概览](api/authorization/overview.md)
- [页面路由](api/page/routing.md)
- [错误码](api/error-codes.md)
- [页面交互](api/page/ui.md)
- [应用共享授权路径](api/authorization/shared-access.md)
- [用户个人授权路径](api/authorization/user-access.md)
- [文件权限检查](api/authorization/file-acl.md)
- [路径转换](api/authorization/path-convert.md)

### 文档更新日志

- [更新日志](update-log.md)

### 分类页

- [快速开始](category/快速开始.md)
- [开发指南](category/开发指南.md)
- [应用案例](category/应用案例.md)
- [开发工具](category/开发工具.md)

### 快速开始

- [准备工作](quick-started/prerequisites.md)
- [创建应用](quick-started/create-application.md)
- [测试应用](quick-started/test-application.md)
- [上架应用](quick-started/publish-application.md)

### 开发指南

- [应用框架](core-concepts/framework.md)
- [Manifest](core-concepts/manifest.md)
- [环境变量](core-concepts/environment-variables.md)
- [应用权限](core-concepts/privilege.md)
- [应用资源](core-concepts/resource.md)
- [应用入口](core-concepts/app-entry.md)
- [index.cgi](core-concepts/index-cgi.md)
- [统一网关](core-concepts/gateway-registration.md)
- [用户向导](core-concepts/wizard.md)
- [应用依赖](core-concepts/dependency.md)
- [中间件服务](core-concepts/middleware.md)
- [运行时环境](core-concepts/runtime.md)
- [图标](core-concepts/icon.md)

### CLI 开发工具

- [fnpack](cli/fnpack.md)
- [appcenter-cli](cli/appcentercli.md)

### examples

- [Native 应用案例](examples/native.md)
- [Docker 应用案例](examples/docker.md)
