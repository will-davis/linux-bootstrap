#!/usr/bin/env python3
"""Capture/apply the portable subset of KDE preferences, preserving local state."""
import argparse
import copy
import datetime
import json
import os
from pathlib import Path
import shutil
import tempfile
import xml.etree.ElementTree as ET

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
DATA = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
DEVICE = "ProtoArc EM05NL"
ICON_TOKEN = "@BOOTSTRAP_ICONS@"
LAUNCHERS = {
    "firefox": ("Firefox Developer Edition — New Window", ["firefox-developer-edition", "firefox-devedition"], "--new-window %u", "firefox-developer-edition", "Meta+F"),
    "sublime": ("Sublime Text — New File", ["subl"], "--command new_file", "sublime-text", "Meta+S"),
    "terminal": ("kitty", ["kitty"], "", "kitty", r"Alt+Shift+T\tMeta+T"),
}


def read_kconfig(path):
    groups, group = {}, ""
    if not path.exists(): return groups
    for line in path.read_text().splitlines():
        if line.startswith("[") and line.endswith("]"):
            group = line
        elif "=" in line and not line.startswith(("#", ";")):
            key, value = line.split("=", 1)
            groups.setdefault(group, {})[key] = value
    return groups


def backup(path):
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    dest = path.with_name(f"{path.name}.bak.{stamp}")
    if path.is_dir() and not path.is_symlink(): shutil.copytree(path, dest, symlinks=True)
    else: shutil.copy2(path, dest, follow_symlinks=False)
    return dest


def write_changed(path, content, backups=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == content: return False
    if backups and (path.exists() or path.is_symlink()): backup(path)
    # Resolve a file symlink rather than replacing someone else's chosen link.
    actual = path.resolve() if path.is_symlink() else path
    actual.parent.mkdir(parents=True, exist_ok=True)
    mode = actual.stat().st_mode & 0o777 if actual.exists() else 0o600
    with tempfile.NamedTemporaryFile(dir=actual.parent, delete=False) as f:
        tmp = Path(f.name)
        f.write(content)
    tmp.chmod(mode)
    tmp.replace(actual)
    print(f"Updated {path}")
    return True


def merge_kconfig(path, patches):
    remaining = copy.deepcopy(patches)
    lines = path.read_text().splitlines() if path.exists() else []
    positions, group = {}, ""
    for index, line in enumerate(lines):
        if line.startswith("[") and line.endswith("]"):
            group = line
        elif "=" in line and not line.startswith(("#", ";")):
            key = line.split("=", 1)[0]
            positions[group, key] = index
    output = lines[:]
    for (group, key), index in positions.items():
        if key in remaining.get(group, {}):
            output[index] = key + "=" + remaining[group].pop(key)
    # Ungrouped keys must precede every group header.
    output[0:0] = [f"{key}={value}" for key, value in remaining.pop("", {}).items()]
    # Repeated KConfig group headers are legal and avoid reformatting unrelated
    # groups/comments. Future runs update these entries in place.
    for group, entries in remaining.items():
        if entries:
            output += ["", group]
            output += [f"{key}={value}" for key, value in entries.items()]
    return write_changed(path, ("\n".join(output).rstrip() + "\n").encode())


def json_write(path, value, backups=False):
    return write_changed(path, (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode(), backups)


def capture(repo):
    destination = repo / "config/kde"
    shortcuts = {}
    # Store custom bindings for portable KDE components. Exclude per-activity
    # UUIDs and third-party application instances; app launchers are explicit.
    for group, values in read_kconfig(CONFIG / "kglobalshortcutsrc").items():
        if group not in ("[kwin]", "[plasmashell]", "[ksmserver]", "[kmix]", "[org_kde_powerdevil]"): continue
        for key, value in values.items():
            fields = value.split(",", 2)
            if len(fields) == 3 and fields[0] != fields[1]:
                shortcuts.setdefault(group, {})[key] = value
    # Super+T is a Plasma default even when it hasn't yet been registered.
    shortcuts.setdefault("[kwin]", {})["Edit Tiles"] = "none,Meta+T,Toggle Tiles Editor"
    json_write(destination / "shortcuts.json", shortcuts)
    dolphin = read_kconfig(CONFIG / "dolphinrc")
    for group in ("[General]", "[MainWindow]"):
        # Session geometry/version/timestamps do not belong to a preference set.
        dolphin.pop(group, None)
    json_write(destination / "dolphin.json", dolphin)
    root = ET.parse(DATA / "kxmlgui5/dolphin/dolphinui.rc").getroot()
    portable = ET.Element("gui", dict(root.attrib))
    for child in root:
        if child.tag not in ("ToolBar", "ActionProperties"): continue
        child = copy.deepcopy(child)
        for element in child.iter():
            icon = element.get("icon", "")
            if icon.startswith("/"):
                source = Path(icon)
                if not source.is_file(): raise RuntimeError(f"Missing custom icon: {source}")
                icon_dest = repo / "assets/dolphin-icons" / source.name
                write_changed(icon_dest, source.read_bytes(), False)
                element.set("icon", ICON_TOKEN + "/" + source.name)
        portable.append(child)
    ET.indent(portable)
    write_changed(destination / "dolphinui.rc", ET.tostring(portable, encoding="utf-8") + b"\n", False)
    source_dir = CONFIG / "input-remapper-2"
    active = json.loads((source_dir / "config.json").read_text())
    preset = active["autoload"][DEVICE]
    if Path(preset).name != preset: raise RuntimeError("Invalid preset name")
    source = source_dir / "presets" / DEVICE / (preset + ".json")
    json.loads(source.read_text())
    remapper = repo / "config/input-remapper-2"
    write_changed(remapper / "presets" / DEVICE / source.name, source.read_bytes(), False)
    json_write(remapper / "defaults.json", {"version": active["version"], "autoload": {DEVICE: preset}})
    print("Captured portable KDE settings and active trackball preset. Review git diff before committing.")


def install_remapper(repo):
    target = repo / "config/input-remapper-2"
    dest = CONFIG / "input-remapper-2"
    defaults = json.loads((target / "defaults.json").read_text())
    local = json.loads((dest / "config.json").read_text()) if (dest / "config.json").exists() else {}
    if dest.resolve() != target.resolve():
        # Preserve other devices in ignored local files inside the directory
        # symlink. The original entire directory also remains as a backup.
        for source in (dest / "presets").rglob("*.json"):
            output = target / source.relative_to(dest)
            if not output.exists():
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, output)
        if dest.exists() or dest.is_symlink():
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            dest.rename(dest.with_name(dest.name + ".bak." + stamp))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.symlink_to(target, target_is_directory=True)
    local["version"] = defaults["version"]
    local.setdefault("autoload", {}).update(defaults["autoload"])
    json_write(target / "config.json", local, True)


def apply(repo):
    kde = repo / "config/kde"
    patches = json.loads((kde / "shortcuts.json").read_text())
    for name, (label, commands, args, icon, keys) in LAUNCHERS.items():
        executable = next((shutil.which(c) for c in commands if shutil.which(c)), None)
        if executable is None: raise RuntimeError(f"Install {commands[0]} before applying KDE configuration")
        desktop_id = f"linux-bootstrap-{name}.desktop"
        quoted = executable.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$")
        content = f'[Desktop Entry]\nType=Application\nName={label}\nExec="{quoted}" {args}\nIcon={icon}\nNoDisplay=true\nTerminal=false\n'
        write_changed(DATA / "applications" / desktop_id, content.encode())
        patches[f"[services][{desktop_id}]"] = {"_launch": keys}
    path = CONFIG / "kglobalshortcutsrc"
    reserved = set()
    for entries in patches.values():
        for value in entries.values(): reserved.update(value.split(",", 1)[0].split(r"\t"))
    reserved.discard("none")
    reserved.discard("")
    for group, values in read_kconfig(path).items():
        for key, value in values.items():
            if key in patches.get(group, {}): continue
            fields = value.split(",", 1)
            keys = fields[0].split(r"\t")
            filtered = [k for k in keys if k not in reserved]
            if filtered != keys:
                fields[0] = r"\t".join(filtered) or "none"
                patches.setdefault(group, {})[key] = ",".join(fields)
    merge_kconfig(path, patches)
    merge_kconfig(CONFIG / "dolphinrc", json.loads((kde / "dolphin.json").read_text()))
    merge_kconfig(CONFIG / "kdeglobals", {"[General]": {"TerminalApplication": "kitty", "TerminalService": "kitty.desktop"}})
    icon_dir = DATA / "linux-bootstrap/dolphin-icons"
    for source in (repo / "assets/dolphin-icons").glob("*.svg"):
        write_changed(icon_dir / source.name, source.read_bytes())
    portable = ET.parse(kde / "dolphinui.rc").getroot()
    for element in portable.iter():
        icon = element.get("icon", "")
        if icon.startswith(ICON_TOKEN): element.set("icon", str(icon_dir) + icon[len(ICON_TOKEN):])
    toolbar_path = DATA / "kxmlgui5/dolphin/dolphinui.rc"
    root = ET.parse(toolbar_path).getroot() if toolbar_path.exists() else ET.Element("gui", portable.attrib)
    # Preserve destination menu customizations/state and unrelated action
    # properties. Replace only the captured toolbar and its managed attributes.
    for managed in portable:
        match = next((node for node in root if node.tag == managed.tag and node.get("name") == managed.get("name") and node.get("scheme") == managed.get("scheme")), None)
        if managed.tag == "ActionProperties" and match is not None:
            for action in managed:
                existing = next((a for a in match if a.get("name") == action.get("name")), None)
                if existing is None: match.append(action)
                else: existing.attrib.update(action.attrib)
        else:
            if match is not None:
                position = list(root).index(match)
                root.remove(match)
                root.insert(position, managed)
            else:
                root.append(managed)
    ET.indent(root)
    write_changed(toolbar_path, ET.tostring(root, encoding="utf-8") + b"\n")
    install_remapper(repo)
    print("KDE settings saved. Close/reopen Dolphin; log out/in for shortcuts and remapper autoload.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["apply", "capture"])
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        {"apply": apply, "capture": capture}[args.command](args.repo.resolve())
    except (OSError, ValueError, RuntimeError, KeyError, ET.ParseError) as error:
        parser.exit(1, f"Desktop configuration failed: {error}\n")


if __name__ == "__main__": main()
