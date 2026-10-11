# Huawei MateBook BoF-XX Linux 外放修复

[English](README.en.md) | 简体中文

在一台 HUAWEI BoF-XX 上，Linux 能识别 ES8336 播放设备，PipeWire 也提供 Speakers 输出，但内置扬声器没有声音。这台机器还枚举出独立的 ACPI 设备 `HWSP0001:00`。在这台特定机器上，向 I²C 总线 3 上地址为 `0x58` 和 `0x5b` 的两颗器件初始化后，内置扬声器恢复了声音。

本仓库将这项已在该机器上验证的处理方式封装为带硬件检查的 systemd oneshot 服务和恢复钩子。它**不是 Linux 驱动**，不运行 Windows ISST 安装程序，不修改 PipeWire/WirePlumber 路由、默认输出或蓝牙配置。

## 配套博文

完整排查过程、硬件识别、寄存器验证与持久化修复记录见：[HUAWEI MateBook D 15 2022（BoF-XX-PCB）Ubuntu Linux 外放无声修复](https://xingwangzhe.fun/posts/matebook-d15-bofxx-hwsp0001-no-speaker/)。

## 已验证的机器

| 项目 | 实测信息 |
| --- | --- |
| 华为产品系列 | HUAWEI MateBook D 15 2022 第 12 代 Intel Core 系列；华为官方支持设备列表将产品代码 `BoF` 对应到该系列 |
| Linux DMI 产品名 / 版本 | `BoF-XX` / `M1010` |
| Linux DMI 主板名 | `BoF-XX-PCB` |
| 测试时的系统 / 内核 | Ubuntu 26.04.1 LTS，`7.0.0-38-generic` |
| 音频控制器 | Intel Alder Lake PCH-P HDA，PCI ID `8086:51c8` |
| 内核音频链路 | SOF（`sof-audio-pci-intel-tgl`）和 ES8336 codec（`sof-essx8336`） |
| 额外 ACPI 设备 | `HWSP0001:00`，位于 I²C 总线 3 |
| 实测功放地址 | `0x58`、`0x5b`；两者寄存器 `0x00` 均读为 `0x5a` |

产品系列对应关系参考华为[支持设备列表](https://consumer.huawei.com/cn/support/content/zh-cn15945089/)。`BoF-XX` 是本机 DMI 字符串；脚本检查本机的精确 DMI 值，不假设所有 MateBook D 15 都使用相同主板。

## 排查过程与证据

内核成功创建了 `sof-essx8336` ALSA 声卡，PipeWire 也暴露了 Speakers 输出。SOF firmware 和 `sof-adl-es8336-dmic2ch-ssp0.tplg` topology 均已加载，因此问题不是“Linux 完全没有识别声卡”，也不是缺少 Windows 驱动。用户提供的 Windows 压缩包中包含 `ISST_10.29.0.7767.exe`，这是 Windows 安装程序，不能作为 Linux 内核模块使用。

系统还枚举出独立的 `HWSP0001:00`，但没有绑定 Linux I²C 驱动。只读检查发现总线 3 上的 `0x58`、`0x5b` 器件：初始化前两者的寄存器 `0x00` 均为 `0x5a`、寄存器 `0x01` 均为 `0x38`。应用下方配置后，两者的寄存器 `0x01` 读回 `0x69`；用户随后确认内置扬声器恢复了声音。

配置参考了一份[上游实验性 RFC 补丁](https://patchew.org/linux/20260614161028.10405-1-tgaraev653@gmail.com/)和社区的 [BOD-WXX9 外放排查](https://github.com/MaximushkaBed/huawei-matebook-d15-speaker-fix)。这两份材料讨论的是其他主板，本仓库没有把 BOD 专用参数直接当作通用配置：寄存器配置先在本文记录的 BoF-XX 机器上实测，确认写入后外放恢复。该机器上寄存器 `0x03` 和 `0x59` 的读回值分别为 `0x0c` 和 `0x00`，不会保留建议写入的值；脚本仍发送这两项写入，但会跳过它们的读回比对。

## 安装

依赖：systemd、Bash、`i2c-tools`，以及与测试机器完全匹配的 DMI / I²C 布局。若缺少 `i2cget` 或 `i2cset`，请先用发行版的软件包管理器安装 `i2c-tools`。在本仓库克隆目录中运行：

```bash title="在已验证的 BoF-XX 机器上安装"
pkexec bash "$(pwd)/scripts/install.sh"
```

安装器会拒绝不匹配的厂商、产品名、主板、总线布局、已绑定的内核驱动或异常器件标识值。运行时初始化脚本在每次写入前也会重新检查。它会向 `0x58`、`0x5b` 各写入 14 组寄存器/数值，然后读取并验证可读回的配置寄存器。

systemd 服务在开机时初始化功放；睡眠恢复钩子会在系统恢复后调用同一个受检查的脚本。脚本不会调用 `wpctl`、`pactl`、PipeWire 或 WirePlumber，也不会选择输出设备。你仍可像平常一样在桌面音频设置中选择内置扬声器或蓝牙设备。

## 验证与卸载

```bash title="查看服务状态、日志和输出设备"
systemctl status matebook-hwsp-init.service
journalctl -u matebook-hwsp-init.service -b
wpctl status
```

手动测试音时，请先在桌面音频设置中选择 Speakers sink 并解除静音，然后运行：

```bash title="播放短暂的内置扬声器测试音"
speaker-test -D 'plughw:CARD=sofessx8336,DEV=0' -c 2 -t sine -f 440
```

按 `Ctrl+C` 停止。音频流正在播放并不能证明物理扬声器确实发声，请在电脑旁实际听音确认。

只卸载本仓库新增的自动化配置：

```bash title="移除开机和恢复时的自动初始化"
pkexec /usr/local/sbin/matebook-hwsp-uninstall
```

卸载会移除服务、恢复钩子和已安装脚本；不会改动当前功放寄存器状态，也不会更改其他音频配置。

## 对其他华为主板的建议与限制

- 本方案只在一台 `BoF-XX-PCB` 机器上验证。仅凭 MateBook D 15 商品名，无法确认另一台机器使用相同 codec、功放、I²C 总线、器件地址、DMI 标识或寄存器配置。
- 未核实目标主板前，不要照搬 `BOD-WXX9` 的 GPIO 编号、I²C 总线号或寄存器配置。先确认该机 ACPI 设备、sysfs I²C 路径、器件只读值及针对该主板的证据。
- 建议先记录 `lspci -nnk`、`/proc/asound/cards`、`wpctl status`、`/sys/class/dmi/id/` 下的 DMI 字段、内核音频日志以及 ACPI codec/功放设备。要区分“没有声卡”“声卡存在但播放无声”和“耳机孔/路由问题”，它们的原因可能不同。
- 若内核驱动已经占用器件，不要强制写 I²C 寄存器。本脚本会在 `HWSP0001:00` 已绑定驱动时退出，并在强制访问前检查精确 DMI 和观测到的器件值。
- 对其他主板，先做只读基线采集，并单独验证实际外放结果，再考虑持久化服务。实验性 RFC 和单机社区方案适合作为调查线索，不能直接视为通用修复。

## 参考资料

- 华为：[支持设备及产品代码列表](https://consumer.huawei.com/cn/support/content/zh-cn15945089/)
- Linux sound 邮件列表归档：[HWSP0001 支持 RFC](https://patchew.org/linux/20260614161028.10405-1-tgaraev653@gmail.com/)——实验性讨论，并非已合入上游的驱动
- 社区排查：[MateBook D 15 BOD-WXX9 功放修复](https://github.com/MaximushkaBed/huawei-matebook-d15-speaker-fix)——不同主板，只作为对照材料

## 许可证

MIT，详见 [LICENSE](LICENSE)。
