#!/bin/bash
set -e

# Work from the script's directory
cd "$(dirname "$0")"

echo "=== 1. Setting up Python Virtual Environment ==="
cd backend
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install pyinstaller

echo "=== 2. Compiling Python Backend via PyInstaller ==="
# Package all sounddevice (PortAudio) and miniaudio resources/dylib files into one binary
pyinstaller --clean -y --name backend --onefile --collect-all sounddevice --collect-all miniaudio main.py
deactivate
cd ..

echo "=== 3. Building SwiftUI Frontend via Swift Package Manager ==="
cd frontend
swift build -c release
cd ..

echo "=== 4. Creating macOS .app Bundle Structure ==="
APP_NAME="utils-audio-scheduler.app"
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

echo "=== 5. Copying Executables and Assets ==="
# Copy compiled SwiftUI binary
cp frontend/.build/release/utils-audio-scheduler "$APP_NAME/Contents/MacOS/utils-audio-scheduler"
chmod +x "$APP_NAME/Contents/MacOS/utils-audio-scheduler"

# Copy compiled Python Backend binary
cp backend/dist/backend "$APP_NAME/Contents/Resources/backend"
chmod +x "$APP_NAME/Contents/Resources/backend"

# Create Info.plist
cat <<EOF > "$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>utils-audio-scheduler</string>
    <key>CFBundleIdentifier</key>
    <string>com.audio-scheduler.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AudioScheduler</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== 6. Initializing Git Repository & Initial Commit ==="
git branch -M main || true
git add .
# Commit if there are files in staging area
if ! git diff-index --quiet HEAD --; then
    git commit -m "Complete native macOS audio scheduler implementation"
else
    echo "No modifications to commit."
fi

echo "=========================================================="
echo "SUCCESS: Standalone application built!"
echo "You can launch the app by double-clicking: $(pwd)/$APP_NAME"
echo ""
echo "To push to your remote GitHub repository, run:"
echo "  git push -u origin main"
echo "=========================================================="
