#!/usr/bin/env python3
"""Verify official release downloads and stage working binaries before switching PATH.

Uses Python's standard library; never installs Python packages or builds Rust.
Old installations remain intact if downloading, verification, or execution fails.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile


def request(url):
    req = urllib.request.Request(url, headers={"User-Agent": "will-linux-bootstrap"})
    return urllib.request.urlopen(req, timeout=60)


def fetch_asset(repo, pattern, directory):
    with request(f"https://api.github.com/repos/{repo}/releases/latest") as response:
        release = json.load(response)
    assets = [a for a in release["assets"] if re.fullmatch(pattern, a["name"])]
    if len(assets) != 1:
        raise RuntimeError(f"{repo}: expected one asset matching {pattern}, found {len(assets)}")
    asset = assets[0]
    digest = asset.get("digest") or ""
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise RuntimeError(f"{asset['name']}: missing SHA-256 in release metadata; refusing unverified download")
    if Path(asset["name"]).name != asset["name"]:
        raise RuntimeError("Unexpected asset filename")
    path = directory / asset["name"]
    print(f"Downloading {repo} {release['tag_name']}: {path.name}", file=sys.stderr)
    with request(asset["browser_download_url"]) as response, path.open("wb") as output:
        shutil.copyfileobj(response, output)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest.split(":", 1)[1]:
        raise RuntimeError(f"SHA-256 mismatch: {path.name}")
    return path, release["tag_name"]


def fetch_node(arch, directory):
    with request("https://nodejs.org/dist/index.json") as response:
        versions = json.load(response)
    version = next(v["version"] for v in versions if v.get("lts") and int(v["version"].split(".")[0][1:]) >= 20)
    name = f"node-{version}-linux-{'x64' if arch == 'x86_64' else 'arm64'}.tar.xz"
    base = f"https://nodejs.org/dist/{version}/"
    with request(base + "SHASUMS256.txt") as response:
        checksums = dict(line.split()[::-1] for line in response.read().decode().splitlines() if line.strip())
    path = directory / name
    print(f"Downloading official Node.js LTS {version}", file=sys.stderr)
    with request(base + name) as response, path.open("wb") as output:
        shutil.copyfileobj(response, output)
    if hashlib.sha256(path.read_bytes()).hexdigest() != checksums[name]:
        raise RuntimeError("Node.js checksum mismatch")
    return path, version


def unpack(archive, destination):
    destination.mkdir()
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as z:
            for member in z.infolist():
                path = Path(member.filename)
                if path.is_absolute() or ".." in path.parts:
                    raise RuntimeError("Unsafe archive member")
            z.extractall(destination)
    else:
        with tarfile.open(archive) as tar:
            if hasattr(tarfile, "data_filter"):
                tar.extractall(destination, filter="data")
            else:
                # Python without the backported data filter: only ordinary
                # files/directories. Reject links instead of guessing semantics.
                for member in tar.getmembers():
                    path = Path(member.name)
                    if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                        raise RuntimeError("Archive needs Python with tarfile.data_filter support")
                tar.extractall(destination)


def install(tool, arch):
    if arch not in ("x86_64", "aarch64"):
        raise RuntimeError(f"No upstream {tool} binary supported for {arch}")
    repositories = {"nvim": "neovim/neovim", "atuin": "atuinsh/atuin",
                    "atuin-server": "atuinsh/atuin", "yazi": "sxyazi/yazi", "eza": "eza-community/eza"}
    if tool == "nvim":
        asset = f"nvim-linux-{'arm64' if arch == 'aarch64' else arch}.tar.gz"
    elif tool == "yazi":
        asset = f"yazi-{arch}-unknown-linux-musl.zip"
    elif tool == "eza":
        asset = f"eza_{arch}-unknown-linux-{'musl' if arch == 'x86_64' else 'gnu_no_libgit'}.tar.gz"
    else:
        asset = f"{tool}-{arch}-unknown-linux-musl.tar.gz"
    data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    releases = data / "linux-bootstrap/releases" / tool
    releases.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".staging-", dir=releases) as temp:
        stage = Path(temp)
        archive, tag = fetch_node(arch, stage) if tool == "node" else fetch_asset(repositories[tool], re.escape(asset), stage)
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", tag):
            raise RuntimeError("Unexpected release tag")
        unpack(archive, stage / "tree")
        names = {"yazi": ["yazi", "ya"], "node": ["node", "npm", "npx"]}.get(tool, [tool])
        binaries = {}
        for name in names:
            if tool == "node":
                executable = stage / "tree" / f"node-{tag}-linux-{'x64' if arch == 'x86_64' else 'arm64'}" / "bin" / name
                matches = [executable] if executable.is_file() else []
            else:
                matches = [p for p in (stage / "tree").rglob(name) if p.is_file()]
            if len(matches) != 1:
                raise RuntimeError(f"Expected one {name} executable, found {len(matches)}")
            binary = matches[0]
            binary.chmod(0o755)
            env = dict(os.environ, PATH=str(binary.parent) + os.pathsep + os.environ.get("PATH", ""))
            subprocess.run([str(binary), "--version"], check=True, timeout=20, env=env, cwd=stage)
            binaries[name] = binary.relative_to(stage / "tree")
        if tool == "nvim":
            subprocess.run([str(stage / "tree" / binaries[tool]), "--headless", "-u", "NONE", "-i", "NONE", "+q"], check=True, timeout=20)
        final = releases / f"{tag}-{arch}"
        if not final.exists():
            (stage / "tree").rename(final)
        # Validate a reused version directory too; never select a damaged copy.
        for relative in binaries.values():
            binary = final / relative
            env = dict(os.environ, PATH=str(binary.parent) + os.pathsep + os.environ.get("PATH", ""))
            subprocess.run([str(binary), "--version"], check=True, timeout=20, env=env, cwd=stage)
        bindir = Path.home() / ".local/bin"
        bindir.mkdir(parents=True, exist_ok=True)
        for name, relative in binaries.items():
            dest = bindir / name
            if dest.is_symlink() and dest.resolve() == final / relative:
                continue
            if dest.exists() or dest.is_symlink():
                backup = dest.with_name(f"{name}.bak.{os.getpid()}")
                if backup.exists() or backup.is_symlink():
                    raise RuntimeError(f"Backup already exists: {backup}")
                if dest.is_symlink(): backup.symlink_to(os.readlink(dest))
                else: shutil.copy2(dest, backup)
            link = bindir / f".{name}.new.{os.getpid()}"
            link.symlink_to(final / relative)
            link.replace(dest)
            print(f"Installed {dest} -> {final / relative}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    ins = commands.add_parser("install")
    ins.add_argument("tool", choices=["nvim", "atuin", "atuin-server", "yazi", "eza", "node"])
    ins.add_argument("--arch", required=True)
    dl = commands.add_parser("download")
    dl.add_argument("repository")
    dl.add_argument("--pattern", required=True)
    dl.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "install": install(args.tool, args.arch)
        else: print(fetch_asset(args.repository, args.pattern, args.directory)[0])
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError, tarfile.TarError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release installation failed: {error}\n")


if __name__ == "__main__":
    main()
