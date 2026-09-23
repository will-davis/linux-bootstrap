"""Offline regression checks: temporary homes only; never run a package manager."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]

def load(name):
    spec = importlib.util.spec_from_file_location(name, REPO / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

desktop, releases = load('desktop'), load('releases')

class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        for name in ['config/kde', 'config/input-remapper-2', 'assets']:
            shutil.copytree(REPO / name, self.repo / name, ignore=shutil.ignore_patterns('config.json', '*.bak.*'))
        self.config = self.root / 'config'
        self.config.mkdir()
        self.data = self.root / 'data & spaces'
        for name, value in [('CONFIG', self.config), ('DATA', self.data)]:
            p = patch.object(desktop, name, value); p.start(); self.addCleanup(p.stop)
        p = patch('shutil.which', lambda command: '/usr/bin/' + command); p.start(); self.addCleanup(p.stop)

    def test_merge_preserves_unrelated_and_root_keys(self):
        path = self.config / 'test'
        path.write_text('# comment\n[Other]\nPreserve=yes\n[General]\nKey=old\n[General]\nKey=last\n')
        desktop.merge_kconfig(path, {'': {'Root': 'value'}, '[General]': {'Key': 'new'}})
        got = desktop.read_kconfig(path)
        self.assertEqual(got[''], {'Root': 'value'})
        self.assertEqual(got['[General]']['Key'], 'new')
        self.assertIn('# comment', path.read_text())
        self.assertEqual(got['[Other]']['Preserve'], 'yes')
        before = path.read_bytes()
        desktop.merge_kconfig(path, {'': {'Root': 'value'}, '[General]': {'Key': 'new'}})
        self.assertEqual(path.read_bytes(), before)

    def test_apply_twice_preserves_local_devices_and_shortcuts(self):
        (self.config / 'kglobalshortcutsrc').write_text('[Unrelated]\nkeep=Ctrl+Alt+K,none,Keep\nconflict=Meta+T\\tCtrl+K,none,Example\n')
        (self.config / 'dolphinrc').write_text('[General]\nHomeUrl=/local/path\n[MainWindow]\nWidth=987\n')
        toolbar = self.data / 'kxmlgui5/dolphin/dolphinui.rc'
        toolbar.parent.mkdir(parents=True)
        toolbar.write_text('<gui name="dolphin" version="49"><MenuBar><Menu name="local-menu"/></MenuBar><ActionProperties scheme="Default"><Action name="local-action" shortcut="Ctrl+Q"/></ActionProperties></gui>')
        local = self.config / 'input-remapper-2'
        (local / 'presets/Other Keyboard').mkdir(parents=True)
        (local / 'presets/Other Keyboard/local.json').write_text('[]')
        (local / 'config.json').write_text(json.dumps({'version': '2.2.1', 'autoload': {'Other Keyboard': 'local'}}))
        desktop.apply(self.repo)
        self.assertTrue(local.is_symlink())
        self.assertTrue(list(self.config.glob('input-remapper-2.bak.*')))
        self.assertTrue((local / 'presets/Other Keyboard/local.json').exists())
        self.assertEqual(json.loads((local / 'config.json').read_text())['autoload'], {'Other Keyboard': 'local', desktop.DEVICE: 'will-260903'})
        shortcuts = desktop.read_kconfig(self.config / 'kglobalshortcutsrc')
        self.assertEqual(shortcuts['[Unrelated]']['keep'], 'Ctrl+Alt+K,none,Keep')
        self.assertEqual(shortcuts['[Unrelated]']['conflict'], 'Ctrl+K,none,Example')
        self.assertEqual(shortcuts['[services][linux-bootstrap-firefox.desktop]']['_launch'], 'Meta+F')
        self.assertEqual(desktop.read_kconfig(self.config / 'dolphinrc')['[MainWindow]']['Width'], '987')
        self.assertIn('local-menu', toolbar.read_text())
        self.assertIn('local-action', toolbar.read_text())
        before = {str(p): p.read_bytes() for root in [self.config, self.data] for p in root.rglob('*') if p.is_file()}
        desktop.apply(self.repo)
        after = {str(p): p.read_bytes() for root in [self.config, self.data] for p in root.rglob('*') if p.is_file()}
        self.assertEqual(before, after)
        # A captured deployed toolbar resolves its installed icons correctly.
        desktop.capture(self.repo)
        self.assertIn(desktop.ICON_TOKEN, (self.repo / 'config/kde/dolphinui.rc').read_text())

    def test_existing_file_symlink_survives(self):
        target = self.root / 'actual'
        target.write_text('[Example]\nKey=old\n')
        path = self.config / 'linked'
        path.symlink_to(target)
        desktop.merge_kconfig(path, {'[Example]': {'Key': 'new'}})
        self.assertTrue(path.is_symlink())
        self.assertIn('Key=new', target.read_text())

    def test_fresh_desktop_application_is_idempotent(self):
        # A fresh install has no toolbar or ActionProperties yet. Replacing
        # the toolbar must not move it past the newly added ActionProperties.
        desktop.apply(self.repo)
        before = {str(p): p.read_bytes() for root in [self.config, self.data] for p in root.rglob('*') if p.is_file()}
        desktop.apply(self.repo)
        after = {str(p): p.read_bytes() for root in [self.config, self.data] for p in root.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

class ReleaseTests(unittest.TestCase):
    def test_checksum_failure_does_not_replace_existing_binary(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / '.local/bin').mkdir(parents=True)
            binary = home / '.local/bin/atuin'
            binary.write_text('original')
            asset = {'name': 'atuin-x86_64-unknown-linux-musl.tar.gz', 'digest': 'sha256:' + '0' * 64, 'browser_download_url': 'https://example.invalid/a'}
            responses = [io.BytesIO(json.dumps({'tag_name': 'v1', 'assets': [asset]}).encode()), io.BytesIO(b'bad download')]
            with patch.dict(os.environ, {'HOME': tmp, 'XDG_DATA_HOME': tmp + '/data'}), patch.object(releases, 'request', side_effect=responses):
                with self.assertRaisesRegex(RuntimeError, 'SHA-256 mismatch'):
                    releases.install('atuin', 'x86_64')
            self.assertEqual(binary.read_text(), 'original')
            self.assertFalse(binary.is_symlink())

    def test_archive_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / 'bad.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                member = tarfile.TarInfo('../escaped'); member.size = 1
                tar.addfile(member, io.BytesIO(b'x'))
            with self.assertRaises((RuntimeError, tarfile.FilterError)):
                releases.unpack(archive, root / 'out')
            self.assertFalse((root / 'escaped').exists())

class ShellTests(unittest.TestCase):
    def test_remapper_version_accepts_stderr_and_startup_diagnostics(self):
        script = '''
set -euo pipefail
source "$1/lib/bootstrap.sh"
input-remapper-control() {
    printf 'Config not initialized yet\\n' >&2
    printf 'input-remapper 2.2.1 commit https://github.com/sezanzeb/input-remapper\\n' >&2
    printf 'python-evdev 2.0.0\\n' >&2
}
remapper_recent_enough
'''
        result = subprocess.run(['bash', '-c', script, 'bash', str(REPO)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_remapper_version_rejects_old_or_failed_command(self):
        for version, status in [('2.1.1', 0), ('2.2.1', 1)]:
            with self.subTest(version=version, status=status):
                script = '''
set -euo pipefail
source "$1/lib/bootstrap.sh"
input-remapper-control() { printf 'input-remapper %s\\n' "$TEST_VERSION" >&2; return "$TEST_STATUS"; }
remapper_recent_enough
'''
                result = subprocess.run(['bash', '-c', script, 'bash', str(REPO)], env=os.environ | {'TEST_VERSION': version, 'TEST_STATUS': str(status)}, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)

    def test_rayglow_auto_push_stays_inside_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            allowed = root / 'shaders'; allowed.mkdir()
            outside = root / 'shaders-other'; outside.mkdir()
            first = allowed / 'one.glsl'; first.write_text('void main() {}\n')
            second = outside / 'two.glsl'; second.write_text('void main() {}\n')
            lua = root / 'check.lua'
            lua.write_text('''
local calls = {}
vim.system = function(cmd) table.insert(calls, cmd) end
local module = dofile(vim.env.TEST_REPO .. '/config/nvim/lua/rayglow.lua')
module.setup({ctl='/fake-helper', shader_root=vim.env.TEST_ROOT .. '/shaders', maps=false})
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ROOT .. '/shaders/one.glsl'))
vim.cmd('write')
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.TEST_ROOT .. '/shaders-other/two.glsl'))
vim.cmd('write')
assert(#calls == 1, 'unexpected shader push')
assert(calls[1][4] == vim.env.TEST_ROOT .. '/shaders/one.glsl')
print('RAYGLOW_GUARD_OK')
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(lua)], env=os.environ | {'TEST_REPO': str(REPO), 'TEST_ROOT': tmp, 'NVIM_LOG_FILE': str(root / 'nvim.log')}, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('RAYGLOW_GUARD_OK', result.stderr)

    def test_apt_full_package_plan_supplies_lsp_dependencies(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = '''
set -euo pipefail
source "$1/lib/bootstrap.sh"
PM=apt ARCH=aarch64 NVIM_MODE=full
sudo() { printf 'PACKAGE %s\\n' "$*"; }
fdfind() { :; }
atuin() { return 1; }
yazi() { return 1; }
eza() { return 1; }
apt_has() { return 1; }
nvim_ok=0
nvim_recent_enough() { ((nvim_ok)); }
node() { return 1; }
release_install() { printf 'RELEASE %s\\n' "$1"; if [[ $1 == nvim ]]; then nvim_ok=1; fi; }
install_core
'''
            result = subprocess.run(['bash', '-c', script, 'bash', str(REPO)], env=os.environ | {'HOME': tmp}, capture_output=True, text=True, check=True)
            for package in ['build-essential', 'nodejs', 'npm', 'unzip', 'python3']:
                self.assertIn(package, result.stdout)
            for tool in ['atuin', 'yazi', 'eza', 'nvim', 'node']:
                self.assertIn('RELEASE ' + tool, result.stdout)
            self.assertNotIn('sublime', result.stdout)

    def test_arch_minimal_uses_full_sync_without_plugin_build_tools(self):
        script = '''
set -euo pipefail
source "$1/lib/bootstrap.sh"
PM=pacman ARCH=aarch64 NVIM_MODE=minimal
sudo() { printf '%s\\n' "$*"; }
install_core
'''
        result = subprocess.run(['bash', '-c', script, 'bash', str(REPO)], capture_output=True, text=True, check=True)
        self.assertIn('pacman -Syu ', result.stdout)
        self.assertIn('atuin yazi', result.stdout)
        self.assertNotIn('base-devel', result.stdout)
        self.assertNotIn('nodejs', result.stdout)

    def test_minimal_headless_config_only_twice(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ | {'HOME': tmp, 'XDG_CONFIG_HOME': tmp + '/config', 'XDG_DATA_HOME': tmp + '/data'}
            config = Path(tmp) / 'config'; (config / 'fish').mkdir(parents=True)
            (config / 'fish/old').write_text('preserve me')
            args = ['bash', str(REPO / 'bootstrap.sh'), '--config-only', '--profile', 'headless', '--nvim', 'minimal']
            for _ in range(2): subprocess.run(args, env=env, check=True, stdout=subprocess.DEVNULL)
            self.assertTrue((config / 'fish').is_symlink())
            self.assertEqual(len(list(config.glob('fish.bak.*'))), 1)
            self.assertFalse((config / 'kitty').exists())
            self.assertFalse((config / 'kglobalshortcutsrc').exists())
            self.assertEqual((config / 'linux-bootstrap/nvim-mode').read_text(), 'minimal\n')
            # A real headless Neovim, with no plugin directory/network.
            result = subprocess.run(['nvim', '--headless', '-i', 'NONE', '+lua assert(package.loaded["lazy"] == nil); assert(vim.o.number)', '+q'], env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('Error', result.stderr)
            self.assertFalse((Path(tmp) / 'data/nvim/lazy').exists())

    def test_pi_detection_without_hostname(self):
        with tempfile.TemporaryDirectory() as tmp:
            model = Path(tmp) / 'proc/device-tree/model'; model.parent.mkdir(parents=True)
            model.write_bytes(b'Raspberry Pi 5 Model B\0')
            result = subprocess.run(['bash', '-c', 'source "$1/lib/bootstrap.sh"; PROFILE=headless; NVIM_MODE=auto; detect_platform "$2"; printf "%s %s" "$IS_PI" "$NVIM_MODE"', 'bash', str(REPO), tmp], capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, '1 minimal')

    def test_fzf_hidden_and_gitignored_without_junk_or_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); files = root / 'files'; files.mkdir()
            config = root / 'config/fd'; config.mkdir(parents=True)
            shutil.copy2(REPO / 'config/fd/ignore', config / 'ignore')
            for name in ['visible.txt', '.secret.txt', 'ignored/shader.glsl', 'node_modules/junk.js', '.venv/junk.py', 'normal/okay.txt']:
                p = files / name; p.parent.mkdir(parents=True, exist_ok=True); p.touch()
            (files / '.gitignore').write_text('ignored/\n')
            (files / 'outside').symlink_to(root / 'config', target_is_directory=True)
            subprocess.run(['git', 'init', '-q', str(files)], check=True)
            env = os.environ | {'XDG_CONFIG_HOME': str(root / 'config')}
            found = subprocess.check_output(['fd', '-t', 'f', '--hidden', '--no-ignore-vcs', '--exclude', '.git'], cwd=files, env=env, text=True).splitlines()
            self.assertIn('.secret.txt', found)
            self.assertIn('ignored/shader.glsl', found)
            self.assertNotIn('node_modules/junk.js', found)
            self.assertNotIn('.venv/junk.py', found)
            self.assertFalse(any(p.startswith('outside/') for p in found))
            dirs = subprocess.check_output(['fd', '-t', 'd', '--exclude', '.git'], cwd=files, env=env, text=True).splitlines()
            self.assertIn('normal/', dirs)
            self.assertNotIn('ignored/', dirs)
            self.assertFalse(any(p.startswith('.') for p in dirs))

if __name__ == '__main__':
    unittest.main()
