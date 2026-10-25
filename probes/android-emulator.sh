#!/usr/bin/env bash
# Boots an x86_64 Android 11 (API 30, the platform record's floor) emulator
# headless with KVM forced on, waits for the boot to complete, opens Settings
# and reads it through UI Automator's accessibility dump. Exit 0 on PASS.
set -euo pipefail
: "${ANDROID_HOME:?the hosted image sets ANDROID_HOME}"
readonly image='system-images;android-30;default;x86_64'

# GitHub's documented step for KVM on standard Linux runners (changelog 2024-04-02).
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
ls -l /dev/kvm

sdk="${ANDROID_HOME}/cmdline-tools/latest/bin"
# `yes` ends on SIGPIPE once sdkmanager stops reading; that is its normal end.
"${sdk}/sdkmanager" --licenses < <(yes || true) >/dev/null
"${sdk}/sdkmanager" emulator platform-tools "${image}" >/dev/null
echo no | "${sdk}/avdmanager" create avd --name s12 --package "${image}" --force >/dev/null

adb="${ANDROID_HOME}/platform-tools/adb"
start=${SECONDS}
"${ANDROID_HOME}/emulator/emulator" -avd s12 -no-window -no-audio -no-boot-anim -no-snapshot \
  -gpu software -accel on >emulator.log 2>&1 &
"${adb}" wait-for-device
booted=''
until [[ ${booted} == 1 ]]; do
  if ((SECONDS - start > 600)); then
    tail -n 40 emulator.log >&2
    echo 'the emulator did not finish booting within 600 s' >&2
    exit 1
  fi
  sleep 2
  booted=$("${adb}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') || booted=''
done
echo "booted in $((SECONDS - start)) s with acceleration forced on"

"${adb}" shell am start -W -a android.settings.SETTINGS >/dev/null
"${adb}" shell uiautomator dump /sdcard/window.xml >/dev/null
"${adb}" pull /sdcard/window.xml window.xml >/dev/null
grep -o 'text="[^"]*Settings[^"]*"' window.xml | head -n 3
"${adb}" emu kill >/dev/null
echo 'PASS android-emulator: KVM-accelerated API 30 booted; Settings read through UI Automator'
