# YouTube 片源（Windows）

运行 `powershell -ExecutionPolicy Bypass -File tools/setup_youtube.ps1 -NodePath <Node.exe 路径>`，再编译 Windows 版本。脚本下载官方 yt-dlp 2026.08.19 并验证 SHA256，复用 Node.js 22+，不读取浏览器 Cookie 或账号。

首次启动自动加入 YouTube 片源。番剧详情 → 播放来源 → YouTube，可按番剧名称搜索；“修改检索关键词”也接受 youtube.com / youtu.be 视频和播放列表链接。结果显示上传频道与时长，便于区分正片、预告、解说。播放列表最多读取 300 个视频。

播放器“画质”菜单显示该视频实际可用分辨率及高帧率档位。默认最高 1080p，记住后续选择；4K/2K 只在视频提供时出现。高清音视频分离流由 mpv 同步播放，切换时保留秒级进度、播放/暂停状态和弹幕；会重新缓冲。

搜索与播放沿用应用手动代理或 Windows 系统代理。登录验证、付费和地区限制会显示错误，不会伪装成无结果。此功能当前仅集成 Windows 运行组件。

上游：<https://github.com/yt-dlp/yt-dlp>；JavaScript 运行依赖：<https://github.com/yt-dlp/yt-dlp/wiki/EJS>。Windows yt-dlp 可执行程序含 GPLv3+ 组件，其许可与第三方许可一并放在运行组件目录；Node 许可同目录。运行文件不纳入 Git，由 CMake 随应用打包。
