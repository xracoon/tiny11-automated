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

工具会先验证 SHA-256，再创建和配置虚拟机。它不会把"成功导入"当作"成功启动"。

## 必须在真实节点执行的验收

1. 开启 Secure Boot 启动，确认 Windows 完成首次启动且没有进入修复模式。
2. 确认首次界面和系统 UI 为简体中文，没有明显英文回退。
3. 切换微软拼音并实际输入中文；检查微软雅黑、宋体文本没有方框或乱码。
4. 在设备管理器确认启动存储和网卡没有缺失驱动。
5. 确认 `QEMU-GA` 与 `cloudbase-init` 服务存在并运行；失败时检查 `%WINDIR%\Temp\pve-firstboot.log` 和 MSI 日志。
6. 通过 ConfigDrive2 下发主机名、网络配置和临时密码并验证生效；镜像自身不得包含固定密码。
7. 在 PVE 侧验证 Agent IP、正常关机、快照恢复、克隆、discard/TRIM、balloon 和磁盘扩容。
8. 对每个计划使用的 Windows 构建号和映像索引重复验收。

## N5105 范围

验收只覆盖普通虚拟显示。GPU 共享、SR-IOV、GVT-g 和 PCI 直通均不属于本分支支持范围；没有真实硬件测试时不得将它们标为受支持。
