# 快照命名与维护

CI 依赖两台模板 VM 各有一个名为 `clean-base` 的干净快照（安装脚本未跑过的基线）。

## 命名

- `clean-base` — 唯一回归基线。每次测试 `revertToSnapshot clean-base` 回到这里。
- 如需阶段性基线（如升级系统包后），另打 `baseline-YYYYMMDD`，但 `clean-base` 始终保留未装状态。

## 维护

- 升级模板机系统包 / VMware Tools 后，先开机跑一次 `provision-*` 确认无报错，再关机**新建** `clean-base`（不要用旧的）：
  ```bash
  vmrun -T fusion snapshot "<vmx>" clean-base   # 若已存在会失败，先 delete 再建
  ```
- 不要在 `clean-base` 上跑过安装脚本后才打快照，否则后续每次 revert 都带着已装状态，测不出干净路径。

## 破坏性恢复

如果某台 VM 被测试跑坏（快照也回不去的罕见情况），从原始 ISO/VHDX 重装并重跑 `ci/provision-*.sh`，再打 `clean-base`。模板机原始镜像最好留一份备份。
