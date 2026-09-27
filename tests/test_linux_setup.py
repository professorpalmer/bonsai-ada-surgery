import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LinuxLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bonsai setup ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copy2(ROOT / 'start-linux.sh', self.root / 'start-linux.sh')
        self.model = self.root / 'model with spaces.gguf'
        self.model.touch()
        self.server = self.root / 'vendor/linux-test/build-linux/bin/llama-server'
        self.server.parent.mkdir(parents=True)
        self.server.write_text(f'#!{sys.executable}\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        self.server.chmod(0o755)
        (self.root / 'tooling').mkdir()
        (self.root / 'tooling/linux-server-path').write_text(str(self.server) + '\n')

    def run_launcher(self, **settings):
        env = {k: v for k, v in os.environ.items() if not k.startswith('BONSAI_')}
        env.update(settings)
        return subprocess.run(['bash', str(self.root / 'start-linux.sh'), str(self.model)],
                              env=env, text=True, capture_output=True)

    def test_model_path_spaces_and_loopback_defaults(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(args[args.index('-m') + 1], str(self.model))
        self.assertEqual(args[args.index('--host') + 1], '127.0.0.1')
        self.assertEqual(args[args.index('--spec-type') + 1], 'none')

    def test_invalid_port_does_not_launch(self):
        result = self.run_launcher(BONSAI_PORT='99999')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('between 1 and 65535', result.stderr)

    def test_missing_build_gives_next_command(self):
        (self.root / 'tooling/linux-server-path').unlink()
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('bash build/build_linux.sh', result.stderr)

    def test_missing_model_does_not_launch(self):
        self.model.unlink()
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stderr)

    def test_scripts_parse(self):
        for path in [ROOT / 'build/build_linux.sh', ROOT / 'start-linux.sh']:
            subprocess.run(['bash', '-n', str(path)], check=True)


if __name__ == '__main__':
    unittest.main()
