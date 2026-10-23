"""Build HarmonyOS in an isolated workspace; never swap the main pubspec."""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
from urllib.parse import unquote, urljoin, urlparse


APP = Path(__file__).resolve().parents[1]
IGNORED = shutil.ignore_patterns(
    "build", "node_modules", "oh_modules", ".hvigor", ".idea", ".git",
    ".dart_tool", "local.properties", "package.json", "package-lock.json",
    "oh-package-lock.json5", "GeneratedPluginRegistrant.ets", "*.local.json5",
    "flutter_assets", "libapp.so", "libflutter.so", "libvmservice_snapshot.so",
    "__pycache__", ".test", ".cxx",
)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_overrides(stage: Path, *, local_geolocator: bool = False) -> None:
    # Federated plugin pubspecs refer to moving branches. Override each direct Git
    # package to the pinned source as well, so Pub does not reject differing refs.
    source = (stage / 'pubspec.yaml').read_text(encoding='utf-8')
    entries = re.findall(r'^  (\w+):\n(    git:\n(?:      [^\n]+\n)+)', source, re.MULTILINE)
    lines = ['dependency_overrides:', '  web: 0.5.1']
    for name, declaration in entries:
        if name == 'geolocator' and local_geolocator:
            lines.extend(['  geolocator:', '    path: vendor/geolocator'])
        else:
            lines.append(f'  {name}:\n{declaration.rstrip()}')
    write_text(stage / 'pubspec_overrides.yaml', '\n'.join(lines) + '\n')


def load_config(app: Path = APP) -> dict:
    local = app / "tool/ohos.local.json"
    config = json.loads(local.read_text(encoding="utf-8-sig")) if local.exists() else {}
    for key, env in (("flutter_sdk", "OHOS_FLUTTER_SDK"), ("deveco_home", "DEVECO_HOME")):
        if os.environ.get(env):
            config[key] = os.environ[env]
    if os.environ.get("OHOS_FLUTTER"):
        config["flutter_sdk"] = str(Path(os.environ["OHOS_FLUTTER"]).resolve().parents[1])
    for key in ("flutter_sdk", "deveco_home"):
        if not config.get(key):
            raise RuntimeError(f"Set {key} in tool/ohos.local.json (see ohos.local.example.json)")
        config[key] = str(Path(config[key]).expanduser().resolve())
    # Default cache stays on the same drive as the project. Ignore global PUB_CACHE.
    config["pub_cache"] = str(Path(config.get("pub_cache", app.parent / ".pub-cache-ohos")).resolve())
    if Path(config["pub_cache"]).drive.lower() != app.drive.lower():
        raise RuntimeError("HarmonyOS PUB_CACHE must be on the same drive as the project")
    return config


def remove_generated(path: Path, app: Path) -> None:
    resolved = path.resolve()
    allowed = (app / "build").resolve()
    if not resolved.is_relative_to(allowed) or resolved == allowed or not allowed.is_relative_to(app.resolve()):
        raise RuntimeError(f"Refusing to delete outside the generated workspace: {path}")
    if path.is_symlink():
        raise RuntimeError(f"Refusing to follow a symlink: {path}")
    if path.exists():
        # ArkTS cache names exceed MAX_PATH on Windows. Python's extended path
        # form permits repeat builds to clean those generated files as well.
        target = "\\\\?\\" + str(resolved) if os.name == "nt" else str(resolved)
        shutil.rmtree(target)


def stage_project(app: Path, config: dict) -> Path:
    # 默认 build/ohos-workspace；被残留句柄锁住时可用环境变量换备用路径。
    stage = app / (os.environ.get("RUNTRAIL_OHOS_STAGE") or "build/ohos-workspace")
    # A clean source copy also removes files deleted from the actual project.
    remove_generated(stage, app)
    stage.mkdir(parents=True)
    for folder in ("lib", "assets", "ohos", "tool", "test"):
        shutil.copytree(app / folder, stage / folder, ignore=IGNORED)
    shutil.copy2(app / "pubspec_ohos.yaml", stage / "pubspec.yaml")
    write_overrides(stage)
    shutil.copy2(app / "analysis_options.yaml", stage / "analysis_options.yaml")
    lock = app / "pubspec_ohos.lock"
    if lock.exists():
        shutil.copy2(lock, stage / "pubspec.lock")
    signing = app / "ohos/build-profile.local.json5"
    if signing.exists():
        shutil.copy2(signing, stage / "ohos/build-profile.json5")
    flutter_sdk = Path(config["flutter_sdk"])
    write_text(stage / "ohos/local.properties", "flutter.sdk=" + str(flutter_sdk).replace("\\", "\\\\") + "\n")
    # Configuration copied for DevEco's manual builds of the staged project.
    write_text(stage / "tool/ohos.local.json", json.dumps(config, indent=2))
    for file in (stage / "ohos").rglob("*"):
        if file.suffix in (".json5", ".json", ".ts", ".ets", ".bat"):
            write_text(file, file.read_text(encoding="utf-8-sig"))
    return stage


def verify_launcher_icon_sdk(config: dict) -> None:
    """Fail closed unless the selected installed SDK and packaging schema know the feature.

    targetSdkVersion is NOT the compile SDK: current DevEco supplies the latter.
    Checking declarations avoids assuming a marketing OS version implies support.
    """
    deveco = Path(config["deveco_home"])
    # DevEco and its matching CLI use sdk/default as their active bundled SDK.
    # Do not accept a newer, inactive SDK merely because another version is installed.
    sdk = deveco / "sdk" / "default"
    signatures = (r"function\s+setAlternateIcon\s*\(", r"function\s+getAlternateIcons\s*\(")
    declarations = list(sdk.rglob("@ohos.bundle.bundleManager.d.ts")) if sdk.is_dir() else []
    known_api = any(all(re.search(pattern, path.read_text(encoding="utf-8-sig"))
                        for pattern in signatures) for path in declarations)
    if not known_api:
        raise RuntimeError("--launcher-icons requires the selected DevEco SDK with public "
                           "setAlternateIcon/getAlternateIcons (API 26.0.0+). "
                           "Install/select a matching DevEco/Command Line Tools SDK; "
                           "the normal build remains unchanged.")
    # Schemas may be bundled with the SDK or Hvigor plugin depending on tool release.
    schemas = []
    for root in (sdk, deveco / "tools" / "hvigor"):
        if root.is_dir():
            schemas.extend(path for path in root.rglob("*.json*")
                           if path.is_file() and path.stat().st_size <= 2_000_000
                           and ("schema" in str(path).lower() or "app" in path.name.lower()))
    def declares_alternate_icons(path: Path) -> bool:
        try:
            return '"alternateIcons"' in path.read_text(encoding="utf-8-sig")
        except (UnicodeError, OSError):
            return False
    known_schema = any(declares_alternate_icons(path) for path in schemas)
    if not known_schema:
        raise RuntimeError("The selected SDK/Hvigor app schema does not declare alternateIcons. "
                           "Use matching API 26.0.0+ DevEco and command-line tools; "
                           "do not inject the field into an older packaging toolchain.")


def prepare_launcher_icons(stage: Path) -> None:
    """Apply experimental API26 integration only to the disposable build workspace."""
    overlay = stage / "tool/launcher_icons_api26"
    source = overlay / "LauncherIconSupport.ets"
    if not source.is_file():
        raise RuntimeError("Launcher icon API26 overlay is missing")
    app_file = stage / "ohos/AppScope/app.json5"
    # This repository's app.json5 is strict JSON. Fail rather than rewrite unknown JSON5.
    data = json.loads(app_file.read_text(encoding="utf-8-sig"))
    app_config = data["app"]
    if app_config.get("bundleType", "app") != "app":
        raise RuntimeError("alternateIcons is supported only for bundleType app")
    if app_config.get("alternateIcons"):
        raise RuntimeError("Existing alternateIcons need review before applying this overlay")
    styles = ("light", "dark", "editorial")
    app_config["alternateIcons"] = [
        {"name": "runtrail_" + style, "icon": "$media:launcher_" + style}
        for style in styles]
    target = stage / "ohos/entry/src/main/ets/appearance/LauncherIconSupport.ets"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    media = stage / "ohos/AppScope/resources/base/media"
    media.mkdir(parents=True, exist_ok=True)
    for style in styles:
        shutil.copy2(overlay / "media" / ("launcher_" + style + ".svg"), media)
    write_text(app_file, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    # Keep target/compatible versions, signing, identifiers and production defaults intact.
    write_text(stage / "LAUNCHER_ICONS_EXPERIMENTAL.txt",
               "API26 launcher-icons trial. Native compiler/device validation required.\n"
               "Compile with the selected API26 SDK; target/compatible versions unchanged.\n")


def run(command: list[str], cwd: Path, env: dict) -> None:
    subprocess.run(command, cwd=cwd, env=env, check=True)


def package_path(stage: Path, name: str) -> Path:
    config_file = stage / ".dart_tool/package_config.json"
    packages = json.loads(config_file.read_text(encoding="utf-8"))["packages"]
    entry = next(p for p in packages if p["name"] == name)
    parsed = urlparse(urljoin(config_file.as_uri(), entry["rootUri"]))
    path = unquote(parsed.path)
    if os.name == "nt" and len(path) > 2 and path[0] == "/" and path[2] == ":":
        path = path[1:]
    return Path(path)


def prepare_compatibility(stage: Path, config: dict) -> None:
    # Patch private copies only: no edits to the shared pub cache or Flutter SDK.
    geolocator = stage / "vendor/geolocator"
    shutil.copytree(package_path(stage, "geolocator"), geolocator,
                    ignore=shutil.ignore_patterns(".git", "build", ".dart_tool", "example"))
    source = geolocator / "lib/geolocator.dart"
    text = source.read_text(encoding="utf-8")
    if "GeolocatorPlatform" not in text:
        raise RuntimeError("Unknown geolocator source; review the compatibility patch")
    write_text(source, "\n".join(line for line in text.splitlines()
                                if "export 'package:geolocator_web/" not in line) + "\n")
    write_overrides(stage, local_geolocator=True)
    plugin = stage / "vendor/flutter-hvigor-plugin"
    shutil.copytree(Path(config["flutter_sdk"]) / "packages/flutter_tools/hvigor", plugin,
                    ignore=shutil.ignore_patterns("node_modules", ".git", "build"))
    manifest = plugin / "package.json"
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data.get("devDependencies", {}).pop("@ohos/hvigor", None)
    write_text(manifest, json.dumps(data, indent=2))


def build(app: Path, mode: str, config: dict, *, offline: bool = False,
          prepare_only: bool = False, analyze: bool = False, launcher_icons: bool = False) -> Path:
    app = app.resolve()
    if launcher_icons:
        verify_launcher_icon_sdk(config)
    lock_dir = app / "build/.ohos-build-lock"
    lock_dir.parent.mkdir(parents=True, exist_ok=True)
    try:
        lock_dir.mkdir()
    except FileExistsError as error:
        raise RuntimeError("Another HarmonyOS build is active; do not build concurrently") from error
    try:
        stage = stage_project(app, config)
        if launcher_icons:
            prepare_launcher_icons(stage)
        env = os.environ.copy()
        env.update(PUB_CACHE=config["pub_cache"], DEVECO_HOME=config["deveco_home"],
                   DEVECO_SDK_HOME=str(Path(config["deveco_home"]) / "sdk"),
                   NPM_CONFIG_OMIT="dev")
        env.setdefault("PUB_HOSTED_URL", "https://pub.flutter-io.cn")
        env.setdefault("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn")
        executable = "flutter.bat" if os.name == "nt" else "flutter"
        flutter = str(Path(config["flutter_sdk"]) / "bin" / executable)
        pub = [flutter, "pub", "get"] + (["--offline"] if offline else [])
        run(pub, stage, env)
        prepare_compatibility(stage, config)
        run(pub, stage, env)
        # Each platform keeps its own reproducible dependency lock.
        shutil.copy2(stage / "pubspec.lock", app / "pubspec_ohos.lock")
        if analyze:
            run([flutter, "analyze", "--no-pub"], stage, env)
        if not prepare_only:
            hap_cmd = [flutter, "build", "hap", "--" + mode, "--no-pub"]
            # 模拟器(x86_64)需要 ohos-x64；默认 arm64 给真机。可用环境变量覆盖。
            target = os.environ.get("RUNTRAIL_OHOS_TARGET")
            if target:
                hap_cmd += ["--target-platform", target]
            run(hap_cmd, stage, env)
            artifacts = list((stage / "build").rglob("*.hap"))
            if not artifacts:
                artifacts = list((stage / "ohos/entry/build").rglob("*.hap"))
            if not artifacts:
                raise RuntimeError("Build completed without a HAP artifact")
            output = app / ("build/ohos/launcher-icons-hap" if launcher_icons else "build/ohos/hap")
            output.mkdir(parents=True, exist_ok=True)
            for artifact in artifacts:
                shutil.copy2(artifact, output / artifact.name)
        return stage
    finally:
        lock_dir.rmdir()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", nargs="?", choices=("debug", "release", "profile"), default="debug")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--analyze", action="store_true")
    parser.add_argument("--launcher-icons", action="store_true",
                        help="Experimental API26 alternate launcher icons; isolated overlay, matching SDK required")
    options = parser.parse_args()
    stage = build(APP, options.mode, load_config(), offline=options.offline,
                  prepare_only=options.prepare_only, analyze=options.analyze,
                  launcher_icons=options.launcher_icons)
    print(f"HarmonyOS workspace: {stage}")
    if not options.prepare_only:
        output = APP / ("build/ohos/launcher-icons-hap" if options.launcher_icons else "build/ohos/hap")
        print(f"HAP output: {output}")


if __name__ == "__main__":
    main()
