# CI 环境：一台 Apple Silicon Mac 上的 VMware Fusion Pro

CI 服务器：一台 Apple Silicon Mac（国内网络）。主机地址、SSH 用户等本地信息放仓库根的 `.env`（gitignored，模板见 `.env.example`），不在本文件出现。

## 一次性搭建

### 1. 装 VMware Fusion Pro

- 2024 起个人免费。到 Broadcom 官网注册账号下载 VMware Fusion Pro。
  - 国内网络下 Broadcom 下载可能慢，必要时走代理。
- 装好后，`vmrun` 在 `/Applications/VMware Fusion.app/Contents/Public/vmrun`，加进 PATH：
  ```bash
  echo 'export PATH=$PATH:"/Applications/VMware Fusion.app/Contents/Public"' >> ~/.zshrc
  ```
- 验证：`vmrun -T fusion list`

### 2. 建两台模板 VM

#### Linux ARM（Ubuntu 24.04 ARM Server）
1. 下 Ubuntu 24.04 ARM64 live ISO（国内可走清华镜像 `https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/releases/24.04/release/`）。
2. Fusion 新建虚拟机 → 安装 Ubuntu Server ARM64 → 最小安装 + OpenSSH server。
3. 装好后进系统执行 `ci/provision-linux-vm.sh`（见同目录）：装 git/curl/python3、VMware Tools（open-vm-tools）、配 SSH key 免密。
4. 关机，打快照：`vmrun -T fusion snapshot "<vmx>" clean-base`。

#### Windows 11 ARM
1. 下 Windows 11 ARM64 VHDX（微软官网 UUP Dump 生成，或 `https://uupdump.net/`；国内可能需代理）。也可用 Fusion 内置的 Windows 11 ARM 下载（Fusion 提供 Windows 11 ARM 下载向导，最省事）。
2. 装系统时建管理员账户；装好后：
   - 设 PowerShell 执行策略：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`（为 `irm|iex` 放行）。
   - 开 OpenSSH Server：`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`，`Start-Service sshd`，`Set-Service sshd -StartupType Automatic`。
   - 配置管理员公钥免密（` administrators_authorized_keys`）。
   - 装 winget（App Installer，商店）。
   - 装 VMware Tools。
3. 关机，打快照：`vmrun -T fusion snapshot "<windows-vmx>" clean-base`。

> 两台 VM 的 `.vmx` 路径记到 `.env`（gitignored），如：
> ```
> LINUX_VMX=/Users/<you>/Library/Application Support/VMware Fusion/Virtual Machines/ubuntu-arm.vmx
> WIN_VMX=/Users/<you>/Library/.../win11-arm.vmx
> ```

### 3. 测试密钥

模型连通性验证需要一个真实 API key。用一把**专用测试 key**（DeepSeek 官方最便宜，充几块钱够测），存到 `.env`（gitignored，不入仓库）：
```bash
# .env
TEST_PROVIDER=deepseek
TEST_API_KEY=sk-...
```

## 日常回归

见 `run-test.sh`。手动触发（主机地址与用户在 `.env`）：
```bash
ssh <CI_USER>@<CI_HOST> 'cd <repo path> && git pull && bash ci/run-test.sh'
```
稳定后可挂 crontab（如每次 push 后或每日一次），结果写进 `ci/logs/`。

## CI 环境体检（2026-09-02，重跑前就绪清单）

一次完整 CI 前，先确认三件事（任一项不满足就是环境问题，不是被测代码问题，修好后再 `bash ci/run-ci.sh`）：

```bash
ssh yuan@<CI_HOST>
# 1) CI 主机有外网（installer 要下 Node/npm/VS Code/uv/crawl4ai；run-test 开头要 git pull）
nc -z -G 6 github.com 443 && echo OK
nc -z -G 6 registry.npmjs.org 443 && echo OK
# 2) Linux VM 能正常起 sshd + open-vm-tools（VMware Tools 必须在 guest 内跑）
export PATH="$PATH:/Applications/VMware Fusion.app/Contents/Public"
VMX="/Users/yuan/Virtual Machines.localized/Ubuntu 64-bit Arm 26.04.vmwarevm/Ubuntu 64-bit Arm 26.04.vmx"
vmrun start "$VMX" nogui         # 等 ~1-2 分钟
nc -z -G 3 172.16.97.129 22      # 应为 OPEN
vmrun getGuestIPAddress "$VMX"   # 应返回 IP，不是 "VMware Tools are not running"
# 3) 主机虚拟化可用（Apple Silicon 上 VMware 依赖 Virtualization.framework）
sysctl -n kern.hv_vmm_present    # 应为 1；为 0 说明本机是嵌套虚拟化实例，guest 会起不来/极慢
```

2026-09-02 实测三查全挂：主机无外网（github/npmjs/baidu 均 CLOSED）；Linux VM 还原 clean-base 后 10 分钟仍无 sshd、Tools 不跑（guest 网络层在、进程不达多用户）；`kern.hv_vmm_present=0`（疑似云上嵌套虚拟化）。历史 08-27 `ci/logs/linux-verify-20260827-131335.log` 是 `12 passed, 0 failed`，说明环境是后来退化，修好即可重跑。Windows 腿 08-27 已 `1 passed, 8 failed`，优先级次之。
