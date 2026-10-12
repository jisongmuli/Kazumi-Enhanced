# Kazumi-Enhanced

基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 2.3.8 开发的增强版，面向 Windows 桌面使用。保留原项目作者、提交历史和 **GPL-3.0** 许可证。本仓库由 **jisongmuli** 独立维护。

![Flutter](https://img.shields.io/badge/Flutter-3.47.6-blue)
![License](https://img.shields.io/badge/License-GPL--3.0-green)

![浅色门户主页](docs/images/home-desktop.png)

## 增强功能

- 浅色商业风格主页：首页、动漫、影视、短剧、YouTube、我的；轮播、分类、统一搜索、真实封面、继续观看和分页。
- 45 个影视/视频站入口，保留原地址并新增公告公布的其他地址；可读取的站点支持详情、线路和选集。
- 播放来源检索包含已安装的动漫、影视、短剧与 YouTube 来源；支持分类和“有结果”筛选，区分空结果、验证、超时及连接失败。影视封面页与统一搜索汇总多个站点，逐步显示结果。
- 红果官方短剧入口，仅使用官方网页开放的内容。
- YouTube 关键词、视频链接与播放列表；播放器按实际可用格式提供画质选择，支持音视频分离流。
- Bangumi 源码版搜索回退及弹幕接口配置；可选本机弹幕服务。
- Anime4K 与 ArtCNN 超分辨率；RIFE 4.6、4.25 Lite、4.26、4.26 Large 和普通光流插帧，支持关闭、倍数及分辨率设置，显示实际输出帧率。
- 播放网络重试、代理和缓冲策略；断点续播、集数与历史进度保留。

界面中的内容来自实际数据，不使用设计图中的示例评分或集数。站点验证、地区/登录限制和网络波动会影响可用性；插帧效果和实时速度取决于显卡、源视频、分辨率和显示器刷新率。

## 从源码运行（Windows x64）

环境：Flutter **3.47.6**、Git、Visual Studio 2022 的 **使用 C++ 的桌面开发** 工作负载及 Windows SDK。安装可选运行组件时另需 Node.js **22+**（推荐 24.21.0）和 Python **3.10+**。

```powershell
git clone https://github.com/jisongmuli/Kazumi-Enhanced.git
cd Kazumi-Enhanced
powershell -ExecutionPolicy Bypass -File tools/setup_angle.ps1
flutter pub get
flutter run -d windows
```

`pubspec_overrides.yaml` 使用仓库内的 Windows 兼容性修复；ANGLE 二进制不进入 Git，由脚本下载并校验。如果需要代理，给安装脚本添加 `-Proxy http://127.0.0.1:你的端口`。Python 安装脚本使用 `--proxy` 参数。

### 安装完整的可选功能

在编译前运行以下命令，以便 CMake 将运行组件打包到程序旁：

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup_youtube.ps1
powershell -ExecutionPolicy Bypass -File tools/setup_danmaku.ps1
python tools/setup_video_enhancements.py
flutter build windows --release
```

Node.js 必须在 PATH 中，或向两个 PowerShell 脚本传入 `-NodePath "你的node.exe路径"`。插帧安装脚本固定下载 mpv、便携 Python、VapourSynth、RIFE 插件及四种模型；不会修改系统 Python。未安装相应运行组件时，可配置外部弹幕接口；YouTube / AI 插帧会提示组件不可用。

编译结果：`build/windows/x64/runner/Release/kazumi.exe`。分发便携版本时需包含整个 Release 文件夹。

## 验证与 CI

```powershell
flutter analyze --no-fatal-infos --fatal-warnings
flutter test --no-pub
```

增强版在 Windows 本机通过 **280 项测试**，已验证主页真实目录/分类/搜索、跨站片源检索、桌面和窄屏布局、YouTube 实际画质、插帧动态启停和中间帧。联网/原生 GPU 探测位于 `tools/*_live_test.dart`，不混入普通离线测试。

GitHub Actions 在推送 main 和提交 PR 时执行 Windows 安装、检查、测试、编译，并提供便携构建 artifact。其他平台沿用上游源码，但此增强版尚未逐一验证；上游原工作流保存在 `.github/upstream-workflows/` 供参考。

## 使用说明

- [主页功能与交互](tools/PORTAL.md)
- [影视与短剧目录](tools/CINEMA.md)
- [YouTube 与画质选择](tools/YOUTUBE.md)
- [插帧开关与生效检测](tools/INTERPOLATION.md)
- [本地依赖修复](local_overrides/README.md)
- [上游原始 README](README_UPSTREAM.md)
- [来源与第三方声明](THIRD_PARTY_NOTICES.md)

## 许可证与贡献

本项目继续使用原仓库的 [GNU GPL version 3](LICENSE)。各第三方组件的原有许可证和作者声明保留。欢迎提交 Issue 和 PR；复现问题时请提供平台、版本、片源与可公开的日志，并移除 Cookie、账号密钥和个人信息。
