"""Verify the real cron entry wrapper delays before invoking any manager work."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class WrapperTest(unittest.TestCase):
    def test_delay_precedes_tick(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            sleep = root / 'sleep'
            sleep.write_text('#!/bin/sh\nprintf "sleep %s\\n" "$1" >> "$TRACE"\n')
            tick = root / 'tick'
            tick.write_text('#!/bin/sh\necho tick >> "$TRACE"\n')
            sleep.chmod(0o755)
            tick.chmod(0o755)
            source = (ROOT / 'files/usr/sbin/4830-offline-manager').read_text()
            source = source.replace('/usr/lib/4830-offline-manager/tick', str(tick))
            subprocess.run(['sh', '-c', source], check=True,
                env=dict(os.environ, PATH=str(root)+':'+os.environ['PATH'], TRACE=str(root/'trace')))
            self.assertEqual((root/'trace').read_text(), 'sleep 18\ntick\n')
            cron = (ROOT / 'files/usr/lib/micron.d/4830-offline-manager').read_text()
            self.assertEqual(cron.strip(), '* * * * * /usr/sbin/4830-offline-manager')

if __name__ == '__main__':
    unittest.main()
