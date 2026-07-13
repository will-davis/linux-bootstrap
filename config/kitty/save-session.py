#!/usr/bin/env python3
"""Snapshot the CURRENT kitty instance's layout to a session file.

Reconstructs OS windows -> tabs -> windows(panes), each window's cwd, the
tab layout, and the foreground command (so nvim/etc. relaunch; plain shells
just open a shell). This restores STRUCTURE, not live process state — kitty
has no persistent server (see Zellij/tmux for that).

Usage:
    python3 save-session.py [output_file]
Default output: ~/.config/kitty/sessions/last.conf
"""
import json, subprocess, shlex, sys, os

SHELLS = {"fish", "bash", "zsh", "sh", "dash", "tcsh", "nu"}

def is_shell(cmd):
    if not cmd:
        return True
    return os.path.basename(cmd[0]).lstrip("-") in SHELLS

def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.config/kitty/sessions/last.conf")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    data = json.loads(subprocess.check_output(["kitty", "@", "ls"]))
    lines = []
    for oi, osw in enumerate(data):
        for ti, tab in enumerate(osw.get("tabs", [])):
            title = tab.get("title", "")
            if oi == 0 and ti == 0:
                pass                       # implicit first tab/window
            elif ti == 0:
                lines.append("new_os_window")
            else:
                lines.append(f"new_tab {title}")
            lines.append(f"layout {tab.get('layout', 'tall')}")

            for w in tab.get("windows", []):
                fp = (w.get("foreground_processes") or [{}])[0]
                cwd = fp.get("cwd") or w.get("cwd") or os.path.expanduser("~")
                cmd = fp.get("cmdline") or []
                lines.append(f"cd {cwd}")
                if is_shell(cmd):
                    lines.append("launch")
                else:
                    lines.append("launch " + " ".join(shlex.quote(c) for c in cmd))
                if w.get("is_focused"):
                    lines.append("focus")

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Saved {len(data)} window(s) to {out_path}")

if __name__ == "__main__":
    main()
