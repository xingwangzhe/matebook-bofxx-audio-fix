#!/bin/bash
set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root, for example: pkexec bash scripts/install.sh" >&2
  exit 1
fi

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ $(< /sys/class/dmi/id/sys_vendor) == HUAWEI ]] || fail "This profile is restricted to HUAWEI hardware."
[[ $(< /sys/class/dmi/id/product_name) == BoF-XX ]] || fail "Expected product_name BoF-XX."
[[ $(< /sys/class/dmi/id/board_name) == BoF-XX-PCB ]] || fail "Expected board_name BoF-XX-PCB."
device=/sys/bus/i2c/devices/i2c-HWSP0001:00
[[ -e $device ]] || fail "HWSP0001 ACPI I2C device is missing."
resolved=$(readlink -f "$device")
[[ $resolved == /sys/devices/*/i2c-3/i2c-HWSP0001:00 ]] || fail "HWSP0001 is not on I2C bus 3."
[[ ! -L $device/driver ]] || fail "HWSP0001 has a bound kernel driver."
command -v i2cget >/dev/null || fail "Install i2c-tools first."
command -v i2cset >/dev/null || fail "Install i2c-tools first."
for addr in 0x58 0x5b; do
  id=$(i2cget -y -f 3 "$addr" 0x00) || fail "Cannot read $addr."
  [[ ${id,,} == 0x5a ]] || fail "Unexpected register 0x00 value at $addr."
done

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install -D -o root -g root -m 0755 "$repo_dir/src/matebook-hwsp-init" /usr/local/sbin/matebook-hwsp-init
install -D -o root -g root -m 0755 "$repo_dir/systemd/matebook-hwsp-resume" /usr/lib/systemd/system-sleep/matebook-hwsp-resume
install -D -o root -g root -m 0755 "$repo_dir/scripts/uninstall.sh" /usr/local/sbin/matebook-hwsp-uninstall
install -D -o root -g root -m 0644 "$repo_dir/systemd/matebook-hwsp-init.service" /etc/systemd/system/matebook-hwsp-init.service
systemctl daemon-reload
systemctl enable --now matebook-hwsp-init.service
systemctl --no-pager --full status matebook-hwsp-init.service
