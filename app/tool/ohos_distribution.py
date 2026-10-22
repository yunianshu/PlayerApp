"""Prepare release credentials, sign a HAP, and check Pgyer signing material.

Signing secrets stay in the ignored signing/ directory. Huawei must issue the
release certificate and specified-device distribution profile; local key/CSR
generation does not replace that authorization.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid
import zipfile

from ohos_build import APP, load_config

SETTINGS = APP / "signing/harmony-release/signing.local.json"
DISTRIBUTION_HAP = APP / "build/ohos/distribution/entry-default-signed.hap"
UNSIGNED_HAP = APP / "build/ohos-workspace/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap"
BUNDLE = "com.runtrail.runtrail"


def checked_run(command: list[str], *, env: dict | None = None,
                secret: str = "") -> None:
    result = subprocess.run(command, env=env, capture_output=True)
    if result.returncode:
        message = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        if secret:
            message = message.replace(secret, "[REDACTED]")
        # Never raise CalledProcessError: its command would include the password.
        raise RuntimeError(message[-2500:] or "Signing command failed")


def sdk_tools() -> tuple[Path, Path, Path]:
    home = Path(load_config()["deveco_home"])
    suffix = ".exe" if os.name == "nt" else ""
    return (home / f"jbr/bin/java{suffix}", home / f"jbr/bin/keytool{suffix}",
            home / "sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar")


def read_settings() -> dict:
    if not SETTINGS.exists():
        raise RuntimeError("请先运行 python tool/ohos_distribution.py prepare")
    return json.loads(SETTINGS.read_text(encoding="utf-8"))


def prepare() -> None:
    folder = SETTINGS.parent
    folder.mkdir(parents=True, exist_ok=True)
    if SETTINGS.exists():
        config = read_settings()
    else:
        config = {
            "bundleName": BUNDLE,
            "keyAlias": "runtrailRelease",
            "password": secrets.token_urlsafe(30),
            "keystore": str(folder / "runtrail-release.p12"),
            "csr": str(folder / "runtrail-release.csr"),
            "certificate": str(folder / "runtrail-release.cer"),
            "profile": str(folder / "runtrail-release.p7b"),
        }
        SETTINGS.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    _, keytool, _ = sdk_tools()
    env = os.environ.copy()
    env["RUNTRAIL_RELEASE_KEY_PASSWORD"] = config["password"]
    common = ["-alias", config["keyAlias"], "-keystore", config["keystore"],
              "-storetype", "PKCS12", "-storepass:env", "RUNTRAIL_RELEASE_KEY_PASSWORD",
              "-keypass:env", "RUNTRAIL_RELEASE_KEY_PASSWORD"]
    if not Path(config["keystore"]).exists():
        if Path(config["csr"]).exists():
            raise RuntimeError("CSR 已存在但密钥库缺失，请恢复原密钥库，不要生成不同的密钥")
        checked_run([str(keytool), "-genkeypair", *common, "-keyalg", "EC",
                     "-groupname", "secp256r1", "-sigalg", "SHA256withECDSA",
                     "-dname", "CN=RunTrail Release,C=CN", "-validity", "3650"],
                    env=env, secret=config["password"])
    if not Path(config["csr"]).exists():
        checked_run([str(keytool), "-certreq", *common, "-sigalg", "SHA256withECDSA",
                     "-file", config["csr"]], env=env, secret=config["password"])
    print("证书申请文件：" + config["csr"])
    print("请在 AGC 申请发布证书及指定设备发布 Profile；本地生成的密钥尚不能用于分发。")


def verified_profile(path: Path, directory: Path) -> dict:
    java, _, jar = sdk_tools()
    output = directory / "profile.json"
    checked_run([str(java), "-jar", str(jar), "verify-profile", "-inFile", str(path),
                 "-outFile", str(output)])
    data = json.loads(output.read_text(encoding="utf-8"))
    if data.get("verifiedPassed") is not True:
        raise RuntimeError("Profile 签名验证失败")
    content = data["content"]
    return json.loads(content) if isinstance(content, str) else content


def require_release(profile: dict) -> None:
    if profile.get("type") != "release":
        raise RuntimeError(
            f"当前 Profile 为 {profile.get('type')!r}，不可用于蒲公英网页安装。"
            "release 编译模式不等于发布签名；请申请发布证书和指定设备发布 Profile。")
    if profile.get("bundle-info", {}).get("bundle-name") != BUNDLE:
        raise RuntimeError("Profile 的包名与跑迹不一致")
    if profile.get("app-distribution-type") != "internaltesting":
        raise RuntimeError("Profile 不是指定设备发布（internaltesting），不能用于蒲公英内测分发")
    devices = profile.get("debug-info", {})
    if devices.get("device-id-type") != "udid" or not devices.get("device-ids"):
        raise RuntimeError("指定设备发布 Profile 未包含有效的设备 UDID 授权")
    validity = profile.get("validity", {})
    if not validity.get("not-before", float("inf")) <= time.time() <= validity.get("not-after", 0):
        raise RuntimeError("Profile 已过期、尚未生效或缺少有效期")


def matching_key(config: dict, profile: dict) -> None:
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.serialization import pkcs12
    except ImportError as error:
        raise RuntimeError("签名检查需要 cryptography：python -m pip install cryptography") from error
    key, stored_cert, _ = pkcs12.load_key_and_certificates(
        Path(config["keystore"]).read_bytes(), config["password"].encode())
    if key is None:
        raise RuntimeError("P12 中没有私钥")
    expected = profile.get("bundle-info", {}).get("distribution-certificate")
    if not expected:
        raise RuntimeError("Profile 缺少发布证书")
    cert = x509.load_pem_x509_certificate(expected.encode())
    def public_bytes(value):
        return value.public_key().public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    if public_bytes(key) != public_bytes(cert):
        raise RuntimeError("P12 私钥与 Profile 的发布证书不匹配")
    if stored_cert is None or stored_cert.public_bytes(serialization.Encoding.DER) != cert.public_bytes(serialization.Encoding.DER):
        raise RuntimeError("P12 尚未导入华为发布证书，请先执行 sign；不能上传只含本地自签证书的 P12")
    expected_devices = set(config.get("expectedDeviceIds", []))
    if not expected_devices.issubset(profile.get("debug-info", {}).get("device-ids", [])):
        raise RuntimeError("Profile 未包含本地配置指定的安装设备，请在 AGC 重新选择设备")


def import_release_certificate(config: dict, profile: dict) -> None:
    # keytool creates a self-signed placeholder for the CSR. Pgyer needs the
    # actual Huawei-issued certificate chain inside the P12, not just its key.
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.serialization import pkcs12
    key, _, _ = pkcs12.load_key_and_certificates(
        Path(config["keystore"]).read_bytes(), config["password"].encode())
    if key is None:
        raise RuntimeError("P12 中没有私钥")
    expected = x509.load_pem_x509_certificate(
        profile["bundle-info"]["distribution-certificate"].encode())
    raw = Path(config["certificate"]).read_bytes()
    chain = (x509.load_pem_x509_certificates(raw) if b"-----BEGIN CERTIFICATE-----" in raw
             else [x509.load_der_x509_certificate(raw)])
    leaf = next((cert for cert in chain if cert.public_bytes(serialization.Encoding.DER)
                 == expected.public_bytes(serialization.Encoding.DER)), None)
    if leaf is None:
        raise RuntimeError("CER 证书与 Profile 中的发布证书不一致")
    public_format = (serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    if key.public_key().public_bytes(*public_format) != leaf.public_key().public_bytes(*public_format):
        raise RuntimeError("华为签发的证书不属于本地发布密钥，请检查申请时使用的 CSR")
    data = pkcs12.serialize_key_and_certificates(
        config["keyAlias"].encode(), key, leaf, [cert for cert in chain if cert != leaf],
        serialization.BestAvailableEncryption(config["password"].encode()))
    path = Path(config["keystore"])
    temporary = path.with_suffix(".p12.tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def inspect_hap(hap: Path, *, enforce_release: bool = True) -> dict:
    if not hap.is_file():
        raise RuntimeError(f"安装包不存在：{hap}")
    java, _, jar = sdk_tools()
    with tempfile.TemporaryDirectory(prefix="runtrail-signature-") as temp:
        directory = Path(temp)
        profile_file = directory / "profile.p7b"
        checked_run([str(java), "-jar", str(jar), "verify-app", "-inFile", str(hap),
                     "-outCertChain", str(directory / "chain.cer"),
                     "-outProfile", str(profile_file)])
        profile = verified_profile(profile_file, directory)
    with zipfile.ZipFile(hap) as archive:
        app = json.loads(archive.read("module.json"))["app"]
    if app["bundleName"] != BUNDLE:
        raise RuntimeError("安装包的包名与跑迹不一致")
    if enforce_release:
        require_release(profile)
        matching_key(read_settings(), profile)
    print(json.dumps({"bundleName": app["bundleName"], "versionName": app["versionName"],
                      "profileType": profile.get("type"),
                      "distributionType": profile.get("app-distribution-type"),
                      "authorizedDeviceCount": len(profile.get("debug-info", {}).get("device-ids", [])),
                      "profileValidUntil": datetime.fromtimestamp(
                          profile["validity"]["not-after"], timezone.utc).isoformat(),
                      "signatureVerified": True}, ensure_ascii=False))
    return profile


def sign(unsigned: Path) -> None:
    config = read_settings()
    for field in ("keystore", "certificate", "profile"):
        if not Path(config[field]).is_file():
            raise RuntimeError(f"缺少 {field} 文件：{config[field]}")
    with tempfile.TemporaryDirectory(prefix="runtrail-profile-") as temp:
        profile = verified_profile(Path(config["profile"]), Path(temp))
    require_release(profile)
    import_release_certificate(config, profile)
    matching_key(config, profile)
    with zipfile.ZipFile(unsigned) as archive:
        app = json.loads(archive.read("module.json"))["app"]
    if app["bundleName"] != BUNDLE:
        raise RuntimeError("待签名安装包的包名不匹配")
    java, _, jar = sdk_tools()
    DISTRIBUTION_HAP.parent.mkdir(parents=True, exist_ok=True)
    # Promote only after the complete signed artifact passes verification.
    with tempfile.TemporaryDirectory(prefix="runtrail-release-", dir=DISTRIBUTION_HAP.parent) as temp:
        signed = Path(temp) / "entry-default-signed.hap"
        checked_run([str(java), "-jar", str(jar), "sign-app", "-mode", "localSign",
                     "-keyAlias", config["keyAlias"], "-keyPwd", config["password"],
                     "-keystoreFile", config["keystore"], "-keystorePwd", config["password"],
                     "-appCertFile", config["certificate"], "-profileFile", config["profile"],
                     "-signAlg", "SHA256withECDSA", "-inFile", str(unsigned),
                     "-outFile", str(signed), "-compatibleVersion", str(app["minAPIVersion"])],
                    secret=config["password"])
        inspect_hap(signed)
        signed.replace(DISTRIBUTION_HAP)
    print("蒲公英分发安装包：" + str(DISTRIBUTION_HAP))


def upload_cert(hap: Path, build_key: str) -> None:
    inspect_hap(hap)
    config = read_settings()
    api_key = os.environ.get("PGYER_API_KEY", "")
    if not api_key:
        raise RuntimeError("PGYER_API_KEY 未设置；请通过 fastlane pgyer_hap 调用")
    boundary = "runtrail-" + uuid.uuid4().hex
    body = bytearray()
    for name, value in {"_api_key": api_key, "buildKey": build_key,
                        "password": config["password"]}.items():
        body.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    body.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="runtrail-release.p12"\r\nContent-Type: application/x-pkcs12\r\n\r\n'.encode())
    body.extend(Path(config["keystore"]).read_bytes())
    body.extend(f'\r\n--{boundary}--\r\n'.encode())
    request = urllib.request.Request("https://upload.pgyer.com/apiv2/app/uploadHarmonyCert",
        data=bytes(body), headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    result = json.load(urllib.request.urlopen(request, timeout=60))
    if result.get("code") != 0:
        raise RuntimeError(f"蒲公英发布证书上传失败，错误码：{result.get('code')}")
    print("已同步与 HAP 匹配的 P12，供蒲公英签署安装清单。")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "inspect", "check", "sign", "upload-cert"))
    parser.add_argument("--hap", type=Path, default=DISTRIBUTION_HAP)
    parser.add_argument("--unsigned", type=Path, default=UNSIGNED_HAP)
    parser.add_argument("--build-key")
    options = parser.parse_args()
    try:
        if options.action == "prepare":
            prepare()
        elif options.action in ("inspect", "check"):
            inspect_hap(options.hap, enforce_release=options.action == "check")
        elif options.action == "sign":
            sign(options.unsigned)
        elif options.build_key:
            upload_cert(options.hap, options.build_key)
        else:
            parser.error("upload-cert requires --build-key")
    except Exception as error:
        message = str(error)
        if SETTINGS.exists():
            password = read_settings().get("password", "")
            if password:
                message = message.replace(password, "[REDACTED]")
        print(message, file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
