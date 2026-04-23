#!/usr/bin/env zsh
# Mock fdb that prints realistic pre-canned output for VHS recording

case "$1" in
  devices)
    echo "DEVICE_ID=b433094a NAME=Pixel_9_Pro PLATFORM=android-arm64 EMULATOR=false"
    echo "DEVICE_ID=00008150-001E044E1444401C NAME=iPhone_16_Pro PLATFORM=ios EMULATOR=false"
    ;;
  launch)
    echo "WAITING..."
    sleep 0.5
    echo "WAITING..."
    sleep 0.5
    echo "APP_STARTED"
    echo "VM_SERVICE_URI=ws://127.0.0.1:56420/xKj9mNpQrTs=/ws"
    echo "PID=28341"
    echo "LOG_FILE=/tmp/fdb_logs.txt"
    ;;
  screenshot)
    echo "SCREENSHOT_SAVED=/tmp/fdb_screenshot.png"
    echo "SIZE=91.2KB"
    ;;
  describe)
    echo "SCREEN: My Flutter App"
    echo "ROUTE: /home"
    echo ""
    echo "INTERACTIVE:"
    echo "  @1 TextField \"Search...\" key=search_field"
    echo "  @2 ElevatedButton \"Sign In\" key=sign_in_button"
    echo "  @3 ElevatedButton \"Create Account\" key=create_account_button"
    echo "  @4 FloatingActionButton \"[Add]\" key=fab_add"
    echo ""
    echo "VISIBLE TEXT:"
    echo "  \"Welcome back\""
    echo "  \"Continue where you left off\""
    ;;
  tap)
    shift
    echo "TAPPED=FloatingActionButton X=340.0 Y=740.0"
    ;;
  logs)
    echo "[MyApp] user session started id=u_8f3k2p"
    echo "[MyApp] fetched 12 items from cache"
    echo "[MyApp] screen /home rendered in 18ms"
    echo "[MyApp] FAB tapped — opening create sheet"
    echo "[MyApp] counter incremented to 1"
    ;;
  reload)
    echo "RELOADED"
    echo "ELAPSED=312ms"
    ;;
  kill)
    echo "APP_KILLED"
    ;;
  *)
    echo "unknown command: $1"
    exit 1
    ;;
esac
