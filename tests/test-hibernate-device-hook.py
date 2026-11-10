#!/usr/bin/env python3
"""Exercise the hook against fake sysfs without touching host devices."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).resolve().parents[1] / 'bin/hibernate-device-hook'
DEVICES = [('btintel_pcie', '0000:00:14.7'), ('intel-ipu7', '0000:00:05.0')]


class HibernateHookTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / 'events'
        self.log.touch()
        self.runtime = self.root / 'run/hibernate-device-hook'
        self.camera_marker = self.runtime / 'intel-ipu7-0000_00_05.0'
        self.relay_marker = self.runtime / 'restart-camera-relay'
        self.bridge = self.root / 'sys/bus/i2c/devices/i2c-INTC10E1:00'
        self.bridge.mkdir(parents=True)
        (self.bridge / 'driver').symlink_to(self.root)
        for driver, device in DEVICES:
            driver_path = self.root / 'sys/bus/pci/drivers' / driver
            device_path = self.root / 'sys/bus/pci/devices' / device
            driver_path.mkdir(parents=True)
            device_path.mkdir(parents=True)
            for operation in ('bind', 'unbind'):
                (driver_path / operation).touch()
            (driver_path / device).symlink_to(device_path)
            (device_path / 'driver').symlink_to(driver_path)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.stub('systemctl', '''
case "$1" in
  show) cat "$FIXTURE/state" ;;
  stop|start)
    echo "$1" >> "$FIXTURE/events"
    [[ ! -e "$FIXTURE/fail-$1" ]]
    ;;
  *) exit 1 ;;
esac
''')
        self.stub('udevadm', 'echo settle >> "$FIXTURE/events"')
        self.stub('sleep', ':')
        (self.root / 'state').write_text('active\n')
        source = HOOK.read_text().replace('/sys/', str(self.root / 'sys') + '/')
        source = source.replace('/run/hibernate-device-hook', str(self.runtime))
        source = source.replace('EUID != 0', '0 != 0')
        # Emulate sysfs bind/unbind side effects after the real hook writes a
        # device ID. Production code has no test-specific path or root bypass.
        mock_printf = '''
printf() {
  local target device driver_dir device_dir
  target=$(readlink "/proc/$$/fd/1")
  command printf "$@"
  case "$target" in
    "$FIXTURE"/sys/bus/pci/drivers/*/unbind|"$FIXTURE"/sys/bus/pci/drivers/*/bind)
      device=${@: -1}
      driver_dir=${target%/*}
      device_dir="$FIXTURE/sys/bus/pci/devices/$device"
      echo "${target##*/}:$device" >> "$FIXTURE/events"
      if [[ $target == */unbind ]]; then
        rm "$driver_dir/$device" "$device_dir/driver"
      elif [[ ! -e "$FIXTURE/fail-bind" ]]; then
        ln -s "$device_dir" "$driver_dir/$device"
        ln -s "$driver_dir" "$device_dir/driver"
      fi
      ;;
  esac
}
'''
        self.script = self.root / 'hook'
        self.script.write_text(source.replace('set -euo pipefail', 'set -euo pipefail\n' + mock_printf))

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + body + '\n')
        path.chmod(0o755)

    def run_hook(self, action, success=True):
        env = dict(os.environ, FIXTURE=str(self.root), PATH=f'{self.bin}:{os.environ["PATH"]}')
        result = subprocess.run(['bash', str(self.script), action], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def events(self):
        return self.log.read_text().splitlines()

    def test_active_relay_order_and_cleanup(self):
        self.run_hook('pre')
        self.assertTrue(self.relay_marker.exists())
        self.run_hook('post')
        self.assertEqual(self.events(), ['stop', 'unbind:0000:00:14.7', 'unbind:0000:00:05.0',
                                         'bind:0000:00:14.7', 'settle', 'bind:0000:00:05.0', 'start'])
        self.assertFalse(self.runtime.exists())
        self.run_hook('post')
        self.assertEqual(self.events().count('start'), 1)

    def test_inactive_relay_stays_stopped(self):
        (self.root / 'state').write_text('inactive\n')
        self.run_hook('pre')
        self.run_hook('post')
        self.assertNotIn('stop', self.events())
        self.assertNotIn('start', self.events())

    def test_already_detached_camera_is_left_alone(self):
        (self.root / 'sys/bus/pci/drivers/intel-ipu7/0000:00:05.0').unlink()
        (self.root / 'sys/bus/pci/devices/0000:00:05.0/driver').unlink()
        self.run_hook('pre')
        self.run_hook('post')
        self.assertEqual(self.events(), ['unbind:0000:00:14.7', 'bind:0000:00:14.7'])

    def test_stop_failure_can_restore_without_detaching(self):
        (self.root / 'fail-stop').touch()
        self.run_hook('pre', success=False)
        self.run_hook('post')
        self.assertEqual(self.events(), ['stop', 'start'])
        self.assertFalse(self.runtime.exists())

    def test_bridge_timeout_preserves_state_for_retry(self):
        self.run_hook('pre')
        (self.bridge / 'driver').unlink()
        self.run_hook('post', success=False)
        self.assertTrue(self.camera_marker.exists())
        self.assertTrue(self.relay_marker.exists())
        self.assertNotIn('bind:0000:00:05.0', self.events())
        self.assertNotIn('start', self.events())
        (self.bridge / 'driver').symlink_to(self.root)
        self.run_hook('post')
        self.assertEqual(self.events()[-2:], ['bind:0000:00:05.0', 'start'])

    def test_failed_camera_bind_does_not_restart_relay(self):
        self.run_hook('pre')
        # Restore Bluetooth first so the injected failure targets IPU7.
        bt_driver = self.root / 'sys/bus/pci/drivers/btintel_pcie'
        bt_device = self.root / 'sys/bus/pci/devices/0000:00:14.7'
        (bt_driver / '0000:00:14.7').symlink_to(bt_device)
        (bt_device / 'driver').symlink_to(bt_driver)
        (self.root / 'fail-bind').touch()
        self.run_hook('post', success=False)
        self.assertTrue(self.camera_marker.exists())
        self.assertTrue(self.relay_marker.exists())
        self.assertNotIn('start', self.events())


if __name__ == '__main__':
    unittest.main()
