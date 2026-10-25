#!/usr/bin/env bash
# Boots an x86_64 Android 11 (API 30, the platform record's floor) emulator
# headless with KVM forced on, waits for the boot to complete, opens Settings
# and reads it through UI Automator's accessibility dump. Exit 0 on PASS.
#
# Every wait is bounded, and every failure after the emulator starts prints
# its log. S12_WAIT shortens the device and boot bound for a local test of
# those failure paths.
set -euo pipefail
: "${ANDROID_HOME:?the hosted image sets ANDROID_HOME}"
readonly image='system-images;android-30;default;x86_64' wait_s=${S12_WAIT:-600}
# The hosted image's cmdline-tools write AVDs under XDG_CONFIG_HOME, which the
# emulator never searches; both honour ANDROID_AVD_HOME.
export ANDROID_AVD_HOME="${HOME}/.android/avd"
mkdir -p "${ANDROID_AVD_HOME}"

# GitHub's documented step for KVM on standard Linux runners (changelog 2024-04-02).
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
ls -l /dev/kvm

sdk="${ANDROID_HOME}/cmdline-tools/latest/bin"
# `yes` ends on SIGPIPE once sdkmanager stops reading; that is its normal end.
timeout 300 "${sdk}/sdkmanager" --licenses < <(yes || true) >/dev/null
timeout 600 "${sdk}/sdkmanager" emulator platform-tools "${image}" >/dev/null
echo no | timeout 120 "${sdk}/avdmanager" create avd --name s12 --package "${image}" --force >/dev/null
[[ -f ${ANDROID_AVD_HOME}/s12.ini ]] || {
  echo "avdmanager wrote no s12.ini in ${ANDROID_AVD_HOME}" >&2
  exit 1
}
timeout 60 "${ANDROID_HOME}/emulator/emulator" -accel-check || true

adb="${ANDROID_HOME}/platform-tools/adb"
fail() {
  tail -n 80 emulator.log >&2
  echo "$1" >&2
  exit 1
}
start=${SECONDS}
"${ANDROID_HOME}/emulator/emulator" -avd s12 -no-window -no-audio -no-boot-anim -no-snapshot \
  -gpu software -accel on >emulator.log 2>&1 &
emulator=$!
# alive_within_bound <what>: fails the probe once the emulator has exited or the bound has passed.
alive_within_bound() {
  kill -0 "${emulator}" 2>/dev/null || fail "the emulator exited while waiting for $1"
  ((SECONDS - start <= wait_s)) || fail "waited ${wait_s} s for $1"
}
state=''
until [[ ${state} == device ]]; do
  alive_within_bound 'a device on adb'
  sleep 2
  state=$(timeout 10 "${adb}" get-state 2>/dev/null) || state=''
done
echo "device in $((SECONDS - start)) s"
booted=''
until [[ ${booted} == 1 ]]; do
  alive_within_bound 'a completed boot'
  sleep 2
  booted=$(timeout 10 "${adb}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') || booted=''
done
echo "booted in $((SECONDS - start)) s with acceleration forced on"

timeout 30 "${adb}" shell wm dismiss-keyguard >/dev/null || true
timeout 60 "${adb}" shell am start -W -a android.settings.SETTINGS >/dev/null || fail 'Settings did not start within 60 s'
# The dump is of the foreground window: Settings is read once its own package draws it.
dumped=${SECONDS}
until grep -q 'package="com.android.settings"' window.xml 2>/dev/null; do
  if ((SECONDS - dumped > 60)); then
    grep -o 'text="[^"]*"' window.xml 2>/dev/null | sort -u | head -n 20 >&2 || true
    fail 'no UI Automator dump of Settings within 60 s'
  fi
  sleep 2
  timeout 30 "${adb}" shell uiautomator dump /sdcard/window.xml >/dev/null || continue
  timeout 30 "${adb}" pull /sdcard/window.xml window.xml >/dev/null || continue
done
grep -o 'text="[^"]*"' window.xml | sort -u | head -n 10
timeout 30 "${adb}" emu kill >/dev/null || true
echo "PASS android-emulator: KVM-accelerated API 30 booted; Settings' window read through UI Automator"
