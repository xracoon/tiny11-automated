# Nano11 zh-CN 的 Proxmox VE 验收

本分支输出 `nano11-zh-cn-pve-candidate.qcow2`。构建阶段只证明映像具有预期静态结构，不证明它已经在真实 PVE 节点或 N5105 上启动。

## 推荐虚拟机配置

- Q35、OVMF、预置 Secure Boot 密钥
- VirtIO SCSI single，IO thread 和 discard 开启
- VirtIO 网卡、balloon、QEMU Agent
- ConfigDrive2 cloud-init 磁盘
- TPM 2.0 可选
- 普通 PVE 虚拟显示，不配置 GPU 共享或 Intel GPU 客体驱动

可以使用仓库的导入工具：

```bash
sudo ./scripts/import-pve-template.sh 120 ./nano11-zh-cn-pve-candidate.qcow2 local-lvm vmbr0 nano11-zh-cn
```

自定义 VM 配置（4核/8G）：

```bash
sudo ./scripts/import-pve-template.sh \
  120 ./nano11-zh-cn-pve-candidate.qcow2 local-lvm vmbr0 nano11-zh-cn \
  --cores 4 --memory 8192
```

如需转为模板，添加 `--template`；添加 TPM 2.0 使用 `--tpm`。

默认部署不写入 Cloud-Init 密码，客体使用空密码的内置 `Administrator`。生产环境应显式设置密码：

```bash
sudo ./scripts/import-pve-template.sh \
  120 ./nano11-zh-cn-pve-candidate.qcow2 local-lvm vmbr0 nano11-zh-cn \
  --cipassword '请替换为强密码' --template
```

导入工具会配置 ConfigDrive2 和 DHCP。Windows 客体固定由 Cloudbase-Init 管理 `Administrator`；PVE 的 Windows ConfigDrive2 不可靠支持通过 `ciuser` 更换账户。

工具会先验证 SHA-256，再创建和配置虚拟机。它不会把"成功导入"当作"成功启动"。

## 首次启动预期

镜像内的 PVE 专用 Panther 应答文件会启用 `Administrator`、设置默认空密码、让 Windows 自动生成唯一计算机名，并跳过语言、联网、更新检查、账户和隐私等 OOBE 页面。正常结果是直接进入简体中文登录界面，而不是自动登录桌面。

Windows 计算机名与 PVE VM 显示名称彼此独立。Cloudbase-Init 首次读取 ConfigDrive2、设置密码或应用其他配置时可能自动重启一次。若仍出现 OOBE，检查 `%WINDIR%\Panther\UnattendGC\setupact.log` 和 `setuperr.log`；若集成组件失败，检查 `%WINDIR%\Temp\pve-firstboot.log`、`qemu-ga-install.log` 和 `cloudbase-init-install.log`。

空密码只建议用于隔离环境中的 PVE 控制台。Windows 默认限制空密码账户的远程网络登录；生产模板务必使用 `--cipassword`。

注意：命令行密码可能进入 Shell 历史或短暂出现在进程参数中。请在受控终端执行，并在导入后按环境策略清理历史记录。

## 必须在真实节点执行的验收

1. 开启 Secure Boot 启动，确认 Windows 跳过 OOBE、没有进入修复模式，并直接显示登录界面。
2. 使用默认空密码或 `--cipassword` 指定的密码登录 `Administrator`；确认首次界面和系统 UI 为简体中文，没有明显英文回退。
3. 切换微软拼音并实际输入中文；检查微软雅黑、宋体文本没有方框或乱码。
4. 在设备管理器确认启动存储和网卡没有缺失驱动。
5. 确认 `QEMU-GA` 与 `cloudbase-init` 服务存在并运行；失败时检查 `%WINDIR%\Temp\pve-firstboot.log` 和 MSI 日志。
6. 确认 ConfigDrive2 的 DHCP 和可选密码生效；镜像不得包含固定的非空密码。Windows 自动生成的主机名应在多个克隆间保持唯一。
7. 在 PVE 侧验证 Agent IP、正常关机、快照恢复、克隆、discard/TRIM、balloon 和磁盘扩容。
8. 对每个计划使用的 Windows 构建号和映像索引重复验收。

## N5105 范围

验收只覆盖普通虚拟显示。GPU 共享、SR-IOV、GVT-g 和 PCI 直通均不属于本分支支持范围；没有真实硬件测试时不得将它们标为受支持。
