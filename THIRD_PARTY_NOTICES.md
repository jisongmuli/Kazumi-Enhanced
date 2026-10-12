# Upstream and third-party notices

Kazumi-Enhanced is derived from [Predidit/Kazumi](https://github.com/Predidit/Kazumi), version 2.3.8, commit `11671bc0ec61727e99e34810f142a1b5e4121a8e`. The original Git history, author notices and root GPL version 3 LICENSE are retained. The original README is preserved in [README_UPSTREAM.md](README_UPSTREAM.md).

The enhanced portal, cinema / YouTube integrations, danmaku compatibility endpoint, playback networking, ArtCNN and interpolation work were added in October 2026. This repository is independently maintained by jisongmuli.

| Component | Origin / retained notices |
| --- | --- |
| ech_http 0.2.1, MSVC embedding fix | `local_overrides/ech_http/LICENSE`, `licenses/ech_http/` |
| media-kit video renderer / ANGLE integration | `local_overrides/media_kit_video/LICENSE`; Windows renderer based on media-kit commit `c533e446755f51cf53c7e57aea873f2aa5355f81` |
| Anime4K | `assets/shaders/LICENSE` |
| ArtCNN | `assets/shaders/ArtCNN_LICENSE`; commit `8789539dfae120f2877a89bb6218026d56809612` |
| danmu_api | Downloaded at commit `f47b786876f2ab51ef69518e5e0b1c0574664589`; installer preserves its LICENSE |
| VapourSynth-RIFE-ncnn-Vulkan | Downloaded from `r9_mod_v33`; model revision `c3ec6aabc07c8fa37a4f58d7fed9e2ad1fc1b13f`; installer preserves LICENSE |
| mpv / FFmpeg, Python, VapourSynth, ANGLE | Optional native downloads; original component notices remain with their distributions and source projects |
| yt-dlp / Node.js | Setup script downloads original LICENSE and third-party notices alongside the runtime |

Third-party binaries, models, node_modules, local settings, cookies, logs and watch history are not stored in Git. Downloads use the pinned versions and SHA-256 hashes recorded in the setup scripts and `tools/enhancement-components.json`.

The vendored ech_http localhost TLS key is an upstream public test fixture; it is not a user's credential. Media titles and poster images in the documentation screenshot belong to their respective owners. This project does not host video content; public website metadata is fetched at runtime.
