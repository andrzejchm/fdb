/// fdb version — update this AND pubspec.yaml on every release.
const version = '1.0.1';

const pidFile = '/tmp/fdb.pid';
const logFile = '/tmp/fdb_logs.txt';
const vmUriFile = '/tmp/fdb_vm_uri.txt';
const launcherScript = '/tmp/fdb_launcher.sh';
const deviceFile = '/tmp/fdb_device.txt';
const defaultScreenshotPath = '/tmp/fdb_screenshot.png';

const launchTimeoutSeconds = 300; // 5 minutes
const reloadTimeoutSeconds = 10;
const restartTimeoutSeconds = 10;
const killTimeoutSeconds = 10;
const pollIntervalMs = 3000;
const heartbeatIntervalSeconds = 15;
