# Huawei MateBook BoF-XX Linux speaker fix

Linux on one HUAWEI BoF-XX system exposed an ES8336 playback device and a PipeWire Speakers sink, but the internal speakers were silent. The machine also exposed a separate ACPI device named `HWSP0001:00`. On this specific system, initializing the two I2C devices at addresses `0x58` and `0x5b` on bus 3 restored audible speaker output.

This repository packages that observed workaround as a guarded systemd oneshot service and systemd resume hook. It is **not a Linux driver**, does not use the Windows ISST installer, and does not change PipeWire/WirePlumber routing, the default output, or Bluetooth configuration.

## Verified system

| Item | Observed value |
| --- | --- |
| Huawei product family | HUAWEI MateBook D 15 2022 12th Gen Intel Core family, officially mapped by Huawei to product code `BoF` |
| Linux DMI product / version | `BoF-XX` / `M1010` |
| Linux DMI board | `BoF-XX-PCB` |
| OS and kernel during test | Ubuntu 26.04.1 LTS, `7.0.0-38-generic` |
| Audio controller | Intel Alder Lake PCH-P HDA, PCI ID `8086:51c8` |
| Kernel audio path | SOF (`sof-audio-pci-intel-tgl`) with ES8336 codec (`sof-essx8336`) |
| Additional ACPI device | `HWSP0001:00` on I2C bus 3 |
| Amplifier addresses observed | `0x58`, `0x5b`; register `0x00` read `0x5a` on both |

The commercial model mapping comes from Huawei's [supported-device listing](https://consumer.huawei.com/cn/support/content/zh-cn15945089/). `BoF-XX` is the DMI string on the tested machine; the software checks exact local DMI values rather than assuming every MateBook D 15 has the same board.

## Diagnosis and evidence

The kernel successfully created the `sof-essx8336` ALSA card and PipeWire exposed a Speakers sink. The SOF firmware and `sof-adl-es8336-dmic2ch-ssp0.tplg` topology loaded, so the first failure was not a missing Windows driver or an absent Linux sound card. The supplied Windows archive contained an `ISST_10.29.0.7767.exe`; it is a Windows installer, not a Linux kernel module.

The system had a separate ACPI device, `HWSP0001:00`, but no bound Linux I2C driver. Read-only inspection found devices at `0x58` and `0x5b` on bus 3. Before initialization, both returned `0x5a` at register `0x00` and `0x38` at register `0x01`. After applying the profile below, register `0x01` read `0x69` on both; the owner then confirmed audible internal-speaker output.

The values were informed by an [experimental upstream RFC patch](https://patchew.org/linux/20260614161028.10405-1-tgaraev653@gmail.com/) and a community [BOD-WXX9 speaker investigation](https://github.com/MaximushkaBed/huawei-matebook-d15-speaker-fix). Those sources concern other boards. The BOD-specific values were not assumed to be universally compatible: they were first tested on the BoF-XX machine, where profile writes restored sound. On this hardware, writes to registers `0x03` and `0x59` did not retain the proposed values on readback (`0x0c` and `0x00`, respectively); the script still sends those writes but verifies all other profile registers.

## Install

Requirements: systemd, Bash, `i2c-tools`, and the exact tested DMI / I2C layout. Install `i2c-tools` with the distribution package manager if `i2cget` or `i2cset` is missing. From a clone of this repository:

```bash title="Install on the verified BoF-XX system"
pkexec bash "$(pwd)/scripts/install.sh"
```

The installer refuses a different vendor, product, board, bus layout, bound kernel driver, or unexpected device value. The runtime script repeats these checks before every write. It writes 14 register/value pairs to each of `0x58` and `0x5b`, then reads back the writable profile registers.

The systemd service initializes the amplifier at boot. The sleep hook runs the same guarded script after systemd resumes the machine. The scripts do not call `wpctl`, `pactl`, PipeWire, or WirePlumber and do not set an output device; choose internal speakers or Bluetooth through the desktop audio settings as usual.

## Verify and remove

```bash title="Check the service and output devices"
systemctl status matebook-hwsp-init.service
journalctl -u matebook-hwsp-init.service -b
wpctl status
```

For a manual test tone, select the internal Speakers sink in the desktop audio settings, unmute it, then run:

```bash title="Play a short internal speaker test"
speaker-test -D 'plughw:CARD=sofessx8336,DEV=0' -c 2 -t sine -f 440
```

Stop the test with `Ctrl+C`. A running audio stream alone does not prove that the physical speakers are audible; listen at the machine.

Remove only this repository's automation with:

```bash title="Remove the boot and resume automation"
pkexec /usr/local/sbin/matebook-hwsp-uninstall
```

Uninstallation removes the service, resume hook, and installed scripts. It leaves the current amplifier register state unchanged and does not change other audio configuration.

## Limits and advice for other Huawei boards

- This workaround is validated on one `BoF-XX-PCB` machine. A MateBook D 15 name alone does not establish that another unit has the same codec, amplifier, I2C bus, addresses, DMI values, or register profile.
- Do not copy the `BOD-WXX9` GPIO number, I2C bus number, or register profile to another Huawei board without checking that board's ACPI devices, sysfs I2C path, device reads, and board-specific evidence.
- Start by recording `lspci -nnk`, `/proc/asound/cards`, `wpctl status`, DMI fields under `/sys/class/dmi/id/`, kernel audio logs, and ACPI codec/amplifier devices. Distinguish “no sound card”, “sound card exists but playback is silent”, and “headphone jack/routing problem”; they have different causes.
- Avoid force-writing I2C registers while a kernel driver owns the device. This script exits if `HWSP0001:00` has a bound driver and uses exact DMI and observed-value guards before forcing access.
- For a different board, capture its own read-only baseline and confirm the physical result before creating a persistent service. Treat experimental RFC patches and single-board community fixes as leads, not universal instructions.

## References

- Huawei, [supported device and product-code listing](https://consumer.huawei.com/cn/support/content/zh-cn15945089/)
- Linux sound mailing-list archive, [HWSP0001 support RFC](https://patchew.org/linux/20260614161028.10405-1-tgaraev653@gmail.com/) — experimental discussion, not an upstream driver
- Community investigation, [MateBook D15 BOD-WXX9 speaker amplifier fix](https://github.com/MaximushkaBed/huawei-matebook-d15-speaker-fix) — different board; use only as comparative evidence

## License

MIT. See [LICENSE](LICENSE).
