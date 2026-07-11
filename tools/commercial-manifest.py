#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey


def b64encode(value: bytes) -> str:
    """使用 URL 安全 Base64 编码密钥、签名和摘要。"""
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def b64decode(value: str) -> bytes:
    """还原 URL 安全 Base64 字符串，自动补齐 padding。"""
    return base64.urlsafe_b64decode((value + "=" * (-len(value) % 4)).encode())


def canonical_json(payload: dict[str, Any]) -> bytes:
    """生成签名前后的稳定 JSON 字节串。"""
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def load_private_key(value: str) -> Ed25519PrivateKey:
    if "BEGIN PRIVATE KEY" in value:
        loaded = serialization.load_pem_private_key(value.encode(), password=None)
        if not isinstance(loaded, Ed25519PrivateKey):
            raise ValueError("不是 Ed25519 私钥")
        return loaded
    return Ed25519PrivateKey.from_private_bytes(b64decode(value))


def load_public_key(value: str) -> Ed25519PublicKey:
    if "BEGIN PUBLIC KEY" in value:
        loaded = serialization.load_pem_public_key(value.encode())
        if not isinstance(loaded, Ed25519PublicKey):
            raise ValueError("不是 Ed25519 公钥")
        return loaded
    return Ed25519PublicKey.from_public_bytes(b64decode(value))


def generate_keypair() -> None:
    """生成用户部署发布 manifest 签名密钥对。"""
    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()
    private_raw = private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_raw = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    print(f"COMMERCIAL_MANIFEST_PRIVATE_KEY={b64encode(private_raw)}")
    print(f"COMMERCIAL_MANIFEST_PUBLIC_KEY={b64encode(public_raw)}")


def build_release_manifest(
    package_dir: Path,
    version: str,
    images: list[str],
    release_source: dict[str, str] | None = None,
) -> dict[str, Any]:
    """根据用户部署包内容生成 release manifest。"""
    files = []
    for path in sorted(package_dir.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(package_dir).as_posix()
        if relative in {"release-manifest.json", "release-manifest.sig"}:
            continue
        data = path.read_bytes()
        files.append(
            {
                "path": relative,
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
            }
        )
    manifest = {
        "schema": 1,
        "product": "datafusionx",
        "edition": "enterprise",
        "version": version,
        "generated_at": datetime.now(UTC).isoformat(),
        "images": images,
        "algorithm": "sha256",
        "files": files,
    }
    normalized_source = {key: value for key, value in (release_source or {}).items() if value}
    if normalized_source:
        manifest["releaseSource"] = normalized_source
    return manifest


def sign_release(
    package_dir: Path,
    version: str,
    private_key_value: str,
    images: list[str],
    release_source: dict[str, str] | None = None,
) -> None:
    """签名用户部署包 release manifest。"""
    manifest = build_release_manifest(package_dir, version, images, release_source=release_source)
    manifest_path = package_dir / "release-manifest.json"
    signature_path = package_dir / "release-manifest.sig"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    private_key = load_private_key(private_key_value)
    signature_path.write_text(
        b64encode(private_key.sign(canonical_json(manifest))),
        encoding="utf-8",
    )


def verify_release(package_dir: Path, public_key_value: str) -> None:
    """校验 release manifest 签名和包内文件摘要。"""
    manifest_path = package_dir / "release-manifest.json"
    signature_path = package_dir / "release-manifest.sig"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    signature = signature_path.read_text(encoding="utf-8").strip()
    public_key = load_public_key(public_key_value)
    try:
        public_key.verify(b64decode(signature), canonical_json(manifest))
    except InvalidSignature as exc:
        raise SystemExit("release manifest 签名无效") from exc
    for item in manifest.get("files") or []:
        path = package_dir / item["path"]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != item["sha256"]:
            raise SystemExit(f"release 文件校验和不匹配：{item['path']}")
    print("release manifest 已通过校验")


def main() -> None:
    parser = argparse.ArgumentParser(description="DataFusionX Enterprise 用户部署发布 manifest 工具")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("generate-keypair")

    sign_parser = subparsers.add_parser("sign-release")
    sign_parser.add_argument("--package-dir", required=True)
    sign_parser.add_argument("--version", required=True)
    sign_parser.add_argument("--private-key", required=True)
    sign_parser.add_argument("--image", action="append", default=[])
    sign_parser.add_argument("--build-commit", default="")
    sign_parser.add_argument("--origin-sha", default="")
    sign_parser.add_argument("--gitee-sha", default="")
    sign_parser.add_argument("--build-ref", default="")
    sign_parser.add_argument("--build-actor", default="")
    sign_parser.add_argument("--build-run-id", default="")
    sign_parser.add_argument("--build-run-url", default="")

    verify_parser = subparsers.add_parser("verify-release")
    verify_parser.add_argument("--package-dir", required=True)
    verify_parser.add_argument("--public-key", required=True)

    args = parser.parse_args()
    if args.command == "generate-keypair":
        generate_keypair()
        return
    if args.command == "sign-release":
        release_source = {
            "buildCommit": args.build_commit,
            "originSha": args.origin_sha,
            "giteeSha": args.gitee_sha,
            "buildRef": args.build_ref,
            "buildActor": args.build_actor,
            "buildRunId": args.build_run_id,
            "buildRunUrl": args.build_run_url,
        }
        sign_release(Path(args.package_dir), args.version, args.private_key, args.image, release_source)
        return
    if args.command == "verify-release":
        verify_release(Path(args.package_dir), args.public_key)


if __name__ == "__main__":
    main()
