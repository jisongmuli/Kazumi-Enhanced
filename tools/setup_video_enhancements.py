"""Install pinned portable RIFE runtime; downloaded binaries stay outside Git.

Requires Python 3.10+, CMake (or 7-Zip), and internet access.
Usage: python tools/setup_video_enhancements.py --proxy http://127.0.0.1:7897
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = json.loads((ROOT / "tools/enhancement-components.json").read_text(encoding="utf-8"))
RIFE_REVISION = MANIFEST["commits"]["styler00dollar/VapourSynth-RIFE-ncnn-Vulkan"]


def digest(file):
    with file.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(stream.read()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy", default="")
    parser.add_argument("--cache", type=Path, default=ROOT / "tools/.downloads/video")
    parser.add_argument("--destination", type=Path, default=ROOT / "windows/video_engine")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    args.destination.mkdir(parents=True, exist_ok=True)
    proxy = urllib.request.ProxyHandler({"https": args.proxy, "http": args.proxy}) if args.proxy else urllib.request.ProxyHandler()
    client = urllib.request.build_opener(proxy)

    def download(url, name, sha):
        file = args.cache / name
        if not file.exists() or digest(file) != sha:
            print(f"Downloading {name}", flush=True)
            with client.open(urllib.request.Request(url, headers={"User-Agent": "Kazumi-Enhanced-Setup"}), timeout=180) as response, file.open("wb") as stream:
                shutil.copyfileobj(response, stream)
        if digest(file) != sha:
            raise RuntimeError(f"SHA256 mismatch: {name}")
        return file

    def unzip(file, destination):
        # Reject archive traversal even though each archive has a pinned hash.
        destination = destination.resolve()
        with zipfile.ZipFile(file) as archive:
            for name in archive.namelist():
                if not (destination / name).resolve().is_relative_to(destination):
                    raise RuntimeError("Unsafe archive member")
            archive.extractall(destination)

    dev = download("https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261011/mpv-dev-x86_64-20261011-git-accb7b2821.7z",
                   "mpv_dev.7z", "cf63b4ce66e03e5e70acf2648cbc3177656c77c5b9583e16d83efc58801182b7")
    extracted = args.cache / "mpv-dev"
    extracted.mkdir(exist_ok=True)
    cmake = shutil.which("cmake")
    sevenzip = shutil.which("7z")
    if not cmake and not sevenzip:
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
        if vswhere.exists():
            vs = subprocess.check_output([str(vswhere), "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], text=True).strip()
            candidate = Path(vs) / "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe"
            if candidate.exists(): cmake = str(candidate)
    if cmake:
        subprocess.run([cmake, "-E", "tar", "xf", str(dev.resolve())], cwd=extracted, check=True)
    elif sevenzip:
        subprocess.run([sevenzip, "x", "-y", str(dev.resolve()), "-o" + str(extracted.resolve())], check=True)
    else:
        raise RuntimeError("CMake or 7-Zip is required")
    dll = next(extracted.rglob("libmpv-2.dll"))
    expected = MANIFEST["sha256"]["windows/video_engine/libmpv-2.dll"]
    if digest(dll) != expected: raise RuntimeError("libmpv hash mismatch")
    shutil.copy2(dll, args.destination / "libmpv-2.dll")

    python = download("https://www.python.org/ftp/python/3.14.2/python-3.14.2-embed-amd64.zip",
                      "python_embed.zip", "f05e28d161c6b15af64a7cb7f08b4a22b3a6b03eee71baee24ea557b3bdd5798")
    pyroot = args.destination / "python"
    unzip(python, pyroot)
    (pyroot / "python314._pth").write_text("python314.zip\n.\nLib\nLib/site-packages\nimport site\n", encoding="utf-8")
    vs = download("https://github.com/vapoursynth/vapoursynth/releases/download/R81/VapourSynth64-Portable-R81.zip",
                  "vs_portable.zip", "6d625bd3b4d68697a7664a886f3a5e2f1df1a4744b4811bf77bd944baed63436")
    vsdir = args.cache / "vapoursynth"
    unzip(vs, vsdir)
    wheel = next(vsdir.rglob("vapoursynth-81-*.whl"))
    unzip(wheel, pyroot / "Lib/site-packages")
    plugin = download("https://github.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan/releases/download/r9_mod_v33/librife_windows_x86-64.dll",
                      "librife.dll", MANIFEST["sha256"]["windows/video_engine/plugins/librife.dll"])
    plugins = args.destination / "plugins"
    plugins.mkdir(exist_ok=True)
    shutil.copy2(plugin, plugins / "librife.dll")
    for relative, sha in MANIFEST["sha256"].items():
        prefix = "windows/video_engine/plugins/models/"
        if not relative.startswith(prefix): continue
        model = relative.removeprefix(prefix)
        url = f"https://raw.githubusercontent.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan/{RIFE_REVISION}/models/{model}"
        data = download(url, model.replace("/", "-"), sha)
        destination = plugins / "models" / model
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(data, destination)
    licenses = args.destination / "licenses"
    licenses.mkdir(exist_ok=True)
    # Preserve notices available in the source package; Python/VS ship theirs in the archives.
    for name in ["LICENSE", "COPYING", "COPYING.GPLv2"]:
        for file in extracted.rglob(name): shutil.copy2(file, licenses / ("mpv-" + file.name))
    with client.open(f"https://raw.githubusercontent.com/styler00dollar/VapourSynth-RIFE-ncnn-Vulkan/{RIFE_REVISION}/LICENSE", timeout=30) as response:
        (licenses / "RIFE-LICENSE").write_bytes(response.read())
    print(f"RIFE models 23/70/72/73 installed: {args.destination}. Rebuild the Windows app.")


if __name__ == "__main__":
    main()
