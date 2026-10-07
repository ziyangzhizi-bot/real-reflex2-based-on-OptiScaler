# Reflex2 latewarp — 两版发布

同一个 latewarp（NGX feature 15）有两套正确的用法，按你**开不开帧生成**选一版：

| | **v2-mfg**（适配帧生成） | **v1-legacy**（不适配帧生成） |
|---|---|---|
| 什么时候用 | 开帧生成（MFG / 多帧生成） | 不开帧生成 |
| 扭曲在哪 | DLSS 输出上（机制 C）→ **生成帧继承 warp**，延迟下降 | OptiScaler 自己的帧生成 + present 链帧扭曲（老启用路径） |
| 武器掩码 | 由游戏的 HUDLessColor tag 驱动（**只在它生成帧时存在**） | 老路径自带（当年验证过） |
| 产物 | `v2-mfg/OptiScaler-v2-mfg.dll` + 补丁包 `Reflex2-P2-OptiScaler-1.0.0.zip` | `v1-legacy/OptiScaler-v1-legacy.dll`（2026-09-28 构建） |

## 安装（两版一样，替换游戏里的 dxgi.dll）

1. **关闭游戏**；
2. 备份 `Cyberpunk 2077\bin\x64\dxgi.dll`；
3. 把对应版本的 DLL 复制成 `Cyberpunk 2077\bin\x64\dxgi.dll`：
   - v2：`v2-mfg/OptiScaler-v2-mfg.dll`
   - v1：`v1-legacy/OptiScaler-v1-legacy.dll`
4. 切配置（只改 ini 的四个键，不动其它）：
   ```powershell
   .\latewarp_mode.ps1 -Mode mfg    # 用 v2 时
   .\latewarp_mode.ps1 -Mode old    # 用 v1 时
   ```
5. 启动游戏，在面板里勾上 **「接管开关 latewarp takeover: running」** 与 **「静态元素可视化 Show static elements」**。

## 已知边界（如实写）

- **v2**：武器掩码只在**游戏生成帧**时工作；关掉帧生成后 v2 只有扭曲、没有掩码（hudless 平面没有来源）。
- **v1-legacy**：这是 2026-09-28 的旧二进制，**没有**后来的果冻修复、掩码阈值标定、深度裁切修正等改进；它能提供的是当年那条链路上验证过的扭曲 + 掩码。
- 两版都要求 `[Reprojection] UseNvidiaLatewarp = true`、`[Latewarp] Rewrite = true`；不要动 FrameGen 的 FG Output / FG Input 下拉（用 `latewarp_mode.ps1` 改）。

## 文件

- `latewarp_mode.ps1` — 两套配置一键切换（只写 ini 四个键）
- `USAGE_two_sets.md` — 更详细的配置说明与验证方法（看日志哪几行）
- `install_p2_into_game.ps1` — 安装/卸载/指定 DLL
- `v2-mfg/` — v2 的 DLL（E2c48）与补丁包 zip（含全部补丁脚本与源码）
- `v1-legacy/` — v1 的老 DLL

## 许可

加入的代码是 GPL-3.0-or-later（它链接进 OptiScaler，OptiScaler 是 GPL-3）。
## 设置怎么保存（重要）

- 面板里的开关/滑块：**立即生效，但重启就丢**（它们不写 ini）。
- 面板的 **Save Settings**：会写 ini，但它写的是 OptiScaler 自己解析后的状态 —— `FGOutput`/`FGInput` 会变成 `auto`，调试键也会被写回去。**不要用它保存 latewarp 的配置。**（按了之后画面会出现黄/绿诊断热力图、模式也会跑丢，就是这个原因。）
- 正确做法：
  - 切模式：`.\latewarp_mode.ps1 -Mode mfg` 或 `-Mode old`，然后重启游戏；
  - 被 Save 弄乱之后一键恢复：`.\latewarp_fix_ini.ps1`（把 14 个关键键写回出厂值）；
  - 或者关闭游戏后直接编辑 `OptiScaler.ini`，重启生效。
## 面板（2026-10-07 清理后）

**能调且生效的（保留）**：接管开关、静态元素可视化、遮罩阈值、warp 修正强度、深度截止、武器遮罩、warp 幅度、PresentOnly、Use NVIDIA latewarp。
**已隐藏**：P3-3 诊断滑块、Feed composite 勾选框（它们的 ini 键仍然有效）。

面板里的长标签已经移到控件**上方**，面板不会再被拉得很宽。

## 文件清单（2026-10-07）

- `latewarp_mode.ps1` —— 两套配置一键切换（`-Mode mfg` / `-Mode old`），写 ini 前自动备份
- `latewarp_fix_ini.ps1` —— 面板 Save Settings 把配置弄乱后，一条命令写回出厂值，写前自动备份
- `install_p2_into_game.ps1` —— 安装 / 卸载 / 指定 DLL（游戏在跑时会拒绝）
- `USAGE_two_sets.md` —— 详细配置说明与日志验证方法
- `BUGS_AND_ROBUSTNESS.md` —— 已知问题与健壮性记录（含 4 条待修，附实测证据）