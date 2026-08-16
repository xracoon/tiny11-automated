# Nano11 简体中文 Proxmox VE 候选镜像

[![构建 Nano11 简体中文 PVE 候选镜像](https://github.com/xracoon/tiny11-automated/actions/workflows/build-nano11.yml/badge.svg?branch=pve-nano-zh-cn)](https://github.com/xracoon/tiny11-automated/actions/workflows/build-nano11.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`pve-nano-zh-cn` 是从 `pve-template` 派生的专用分支。它只提供一个自包含 GitHub Actions 构建流程，将官方 Windows 11 x64 简体中文镜像裁剪为 Nano11，并输出适合导入 Proxmox VE 的压缩 QCOW2 候选磁盘。

> 候选镜像只经过静态检查。GitHub 托管运行器无法证明它已在真实 PVE、N5105 或具体业务负载上正常运行。

## 中文支持范围

构建器要求所选 Windows 映像索引原生使用 `zh-CN`，不向英文 ISO 动态添加语言包。这样可以避免 Language Pack、Features on Demand 与 Windows 构建版本不匹配。

保留：

- 简体中文系统 UI 和区域设置
- 微软拼音及 `InputMethod\CHS`
- `Language.Basic~~~zh-CN~0.0.1.0`
- 微软雅黑、宋体、黑体、仿宋、楷体、等线等基础中文字体

为维持 Nano 定位，仍移除中文手写、OCR、语音和文本转语音组件，并移除繁体中文、日文和韩文输入组件。

脚本会在裁剪前和裁剪后分别检查中文 UI、系统区域、0804 输入配置、Language.Basic、CHS 目录和关键字体；任何一项缺失都会终止构建。

## GitHub Actions 构建

1. 打开仓库的 **Actions** 页面。
2. 选择 **构建 Nano11 简体中文 PVE 候选镜像**。
3. 点击 **Run workflow**。
4. 提供有效的官方 Windows 11 x64 简体中文 ISO URL。
5. 选择正确的映像索引和虚拟磁盘容量。
6. 构建完成后下载 `nano11-zh-cn-pve-candidate` Artifact。

工作流完全包含下载、依赖校验、ISO 挂载、Nano 裁剪、PVE 磁盘构建和 Artifact 上传，不再调用多变体 reusable workflow。产物保留 7 天，不发布到 GitHub Releases 或 SourceForge。

Artifact 包含：

```text
nano11-zh-cn-pve-candidate.qcow2
nano11-zh-cn-pve-candidate.qcow2.sha256
nano11-zh-cn-pve-candidate.qcow2.manifest.json
```

如果 ISO 或所选索引不是原生 zh-CN，构建会明确失败；不会静默退回英文。

## 本地 Windows 构建

需要管理员权限、PowerShell 5.1+、DISM、`qemu-img.exe`、官方 zh-CN x64 ISO，以及依赖清单中固定版本的 VirtIO ISO 和 Cloudbase-Init MSI。

```powershell
.\scripts\nano11builder-headless.ps1 `
  -ISO E `
  -INDEX 6 `
  -VirtioISOPath C:\build\virtio-win.iso `
  -CloudbaseInitMSIPath C:\build\CloudbaseInitSetup.msi `
  -QemuImgPath 'C:\Program Files\qemu\qemu-img.exe' `
  -DiskSizeGB 32
```

可选参数包括 `-SCRATCH`、`-SkipCleanup` 和 `-PreserveWinRE`。

## PVE 配置

候选镜像采用：

- Q35 + OVMF/UEFI
- Secure Boot 兼容 EFI 分区
- 默认 32 GiB 动态 GPT 磁盘
- VirtIO SCSI single、IO thread、discard
- VirtIO 网卡和 balloon
- QEMU Guest Agent
- Cloudbase-Init + ConfigDrive2
- 可选 TPM 2.0

导入示例：

```bash
sudo ./scripts/import-pve-template.sh \
  120 \
  ./nano11-zh-cn-pve-candidate.qcow2 \
  local-lvm \
  vmbr0 \
  nano11-zh-cn
```

完整真实节点验收清单见 [`docs/PVE.md`](docs/PVE.md)。

## 清单与验证边界

产物清单包含：

```json
{
  "variant": "nano",
  "language": "zh-CN",
  "chinese_support": [
    "ui",
    "microsoft-pinyin",
    "basic-fonts",
    "basic-language-features"
  ],
  "target": "Proxmox VE 8.4/9.x",
  "validation_level": "static-only",
  "runtime_validated": false,
  "hardware_validated": false
}
```

CI 能检查依赖哈希、中文静态组件、VirtIO 路径、QCOW2 格式、虚拟容量、`qemu-img check`、SHA-256 和清单字段，但不能证明：

- Windows 一定能在目标 PVE 节点完成首次启动
- 微软拼音在实际用户会话中一定正常
- QEMU Agent 和 Cloudbase-Init 已在目标环境工作
- Nano 裁剪满足特定业务软件依赖
- Intel N5105 已完成硬件验证

## N5105 显卡边界

此分支不集成 N5105/Jasper Lake GPU 共享、SR-IOV、GVT-g、PCI 直通或 Intel GPU 客体驱动，只使用普通 PVE 虚拟显示。

## 归属和许可证

项目基于 [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder)，无头自动化来自 [kelexine/tiny11-automated](https://github.com/kelexine/tiny11-automated)。代码按仓库的 [MIT License](LICENSE) 发布。

使用者必须自行提供合法授权的 Windows 源镜像并遵守微软许可条款；本仓库不包含 Windows 二进制文件。
