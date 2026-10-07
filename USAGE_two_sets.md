# 使用说明 — 两套配置（Reflex2/NGX latewarp）

> **更正（14:50）**：两套 = 两套**真实可用的配置**，不是"在新代码里把老路径跑通"。
>
> | | **开帧生成（MFG）** | **关帧生成** |
> |---|---|---|
> | 模式名 | `-Mode mfg` | `-Mode old` |
> | `[FrameGen] FGOutput` | `nofg`（游戏/ReShade 拥有 MFG） | **`Reprojection`**（OptiScaler 自己插帧 = 老那套） |
> | `[FrameGen] FGInput` | `DLSSG` | **`upscaler`** ← 关键，缺它输入层不喂 |
> | `[Latewarp] TagWarpInPlace` | `true` | `false` |
> | `[Latewarp] PresentOnly` | `false` | `true` |
> | 实测状态 | 已验证（13:39：`mask 7.67%`、扭曲、MFG 吃 warp） | 待你验（历史记录里这套的掩码是工作的） |
>
> 之前 14:19 那次"切到老路径也不显示"，原因是只切了 `FGOutput`，`FGInput` 还是 `DLSSG` ⇒ 输入层不喂（`SetResource 0 / latewarp-diag 0 / eval 0`）。

> 一句话：**开帧生成用 A 套（机制 C），关帧生成用 B 套（老路径 / present 链）。**

## 1. 一键切换（改 ini，重启游戏生效）

```powershell
Set-Location "C:/Users/ZhuanZ/Downloads/Reflex2Demo2/Reflex2Demo2"
$G = "E:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64"

# 关帧生成 -> B 套（老路径：present 链扭曲，掩码/粉色遮罩在 present 链产出）
& "_re/reflex2_mod/p2/latewarp_mode.ps1" -Mode nofg -GameDir $G

# 开帧生成 -> A 套（机制 C：MFG 生成帧继承扭曲，延迟下降）
& "_re/reflex2_mod/p2/latewarp_mode.ps1" -Mode fg   -GameDir $G
```

- 只改 `[Latewarp] TagWarpInPlace` 与 `PresentOnly` 两个键，**其它键一个字节都不动**（`MaskThreshold = 5.0`、`DepthCutoff`、`DiagMap`、`WarpScale` 全部保留）。
- ini 只在**游戏启动时**读 ⇒ 切完必须重启游戏。
- ini 只在**游戏启动时**读 ⇒ 切完必须重启游戏。

### ⚠️ 最重要的一条：`[FrameGen] FGOutput` 必须是 `nofg`

`FGOutput` 一旦被改成 `Reprojection`（面板里那个 FG Output 开关会把它写进 ini），**OptiScaler 就成了帧生成的主人**：

- `activeFgOutput != NoFG` ⇒ **latewarp-only presenter 根本不会启动**（日志里 `presenter bootstrapped` 0 次）；
- 于是**两套都不工作**：没有平面喂图、没有掩码、没有粉色遮罩、也没有扭曲。

实测（2026-10-01 14:19，108 秒那一局）：`FGOutput = Reprojection` + `PresentOnly = true` ⇒ `SetResource` 全类型 **0 次**、`latewarp-diag` **0 行**、`latewarp-latelatch/src/ui` 全 0 —— 这就是"切到老路径也不显示"的原因。

`latewarp_mode.ps1` 现在会**自动把 FGOutput 保证为 `nofg`**；如果你在面板里手动动过 FG Output / FG Input，切完模式记得用脚本再跑一次。
- 加 `-DryRun` 可以先看它要改什么，不落盘。

## 2. 两套分别是什么

| 键 | A 套（帧生成开） | B 套（帧生成关） |
|---|---|---|
| `TagWarpInPlace` | `true` | `false` |
| `PresentOnly` | `false` | `true` |
| 扭曲发生位置 | DLSS evaluate 之后，**in-place 扭 `ScalingOutputColor`**（DLSS 输出、UI 合成之前） | **present 链**：扭显示就绪帧到我们的 `_lwOut`，再拷回后缓冲 |
| 帧生成是否吃到 warp | **是**（MFG 的生成帧继承扭曲 ⇒ 延迟下降） | 不是（生成帧拿的是没扭过的输入） |
| 掩码 / 粉色遮罩从哪来 | 游戏的 `HUDLessColor` tag（帧生成在跑时才有）→ present 链合成 | present 链合成；游戏不 tag hudless 时由我们补（E2c45：拿 `ScalingOutputColor` 当 hudless 平面） |
| 高光 | 偏暗（已知，未解） | 待测（这条路的 warp 在显示帧上） |

两套都要求：`[Reprojection] UseNvidiaLatewarp = true`、`[Latewarp] Rewrite = true` —— **千万别关这两个**。

## 3. 怎么验证生效（30 秒，看日志就够）

```powershell
& "_re/reflex2_mod/p2/test/check_highlight.ps1"     # 本次配置 + 管线健康 + 亮度分桶
```

日志 `E:\...\bin\x64\OptiScaler.log` 里：

| 期望看到 | A 套 | B 套 |
|---|---|---|
| `Reprojection_Dx12::SetResource Making a resource copy of: Depth` | 有 | **每帧都有**（上采样器输入补的，E2c44 起） |
| `... of: HudlessColor` | 有（游戏 tag） | 有（E2c45 起我们补的） |
| `latewarp-diag: frame ... mask X% (cutout Y%)` | 有 | **必须有**（0 行 = present 链那道门没开） |
| 面板「静态元素可视化」 | 出粉色 | 出粉色 |
| 武器/手 | 不被扭出双影 | 不被扭出双影 |

B 套如果 `latewarp-diag` 仍然是 0 行，或者粉色还是不出来 —— 把这一局的 `OptiScaler.log` 给 Lead，问题一定在那道 present 链的门上。

## 4. 代价与注意

- **A 套**：拿到 MFG 吃 warp + 延迟下降；代价是转动时灯的高光偏暗（未解，属独立议题）。
- **B 套**：没有 MFG 的延迟收益，warp 只作用在显示帧上；高光表现按理更接近原样。
- 两套都**不要**在游戏运行中切换帧生成：实测在运行中关掉帧生成会让喂图断掉（`SetResource` 归零）。要换就换配置 + 重启。
- 面板里的 `深度截止 (Depth cutoff)` 是实时的，B 套下配合「静态元素可视化」调到武器整片变粉即可。

## 5. 回滚

```powershell
# 配置回滚（回到 A 套）
& "_re/reflex2_mod/p2/latewarp_mode.ps1" -Mode fg -GameDir $G
# 当前装机版（E2c45）
& "_re/reflex2_mod/p2/install_p2_into_game.ps1" -GameDir $G -OptiScalerDll "_re/reflex2_mod/versions/OptiScaler_P3E2c45_9D4FB659B701.dll"
# 历史已验证版本（E2c38b）
& "_re/reflex2_mod/p2/install_p2_into_game.ps1" -GameDir $G -OptiScalerDll "_re/reflex2_mod/versions/OptiScaler_P3E2c38b_AF24F38B1859.dll"
# 完全卸载（回原厂 DLL）
& "_re/reflex2_mod/p2/install_p2_into_game.ps1" -GameDir $G -Uninstall
```

## 6. 当前装机状态

- 版本 E2c46：`dxgi.dll` SHA256 `86474FA947BDBCC7B1B17EF48A6199C67F4BDB29BCA2C7AC36E9E3EA7E18A6EB`（B 套的门禁修复：T101 hudless 判据 + T102 NoFG 深度 validity）
- 上一版 E2c45：`9D4FB659B701957C5AA7FF8D6D7A5E23A538541F074C5269178E98D00CAE875A`
- 补丁 212 条 / 16 个文件 / `new files : 16`；`VERIFY-P2: PASS`、补丁审查 PASS、发布包 PASS
- 存档：`_re/reflex2_mod/versions/OptiScaler_P3E2c45_9D4FB659B701.dll`
- 本次 E2c44/E2c45 解决的问题：关帧生成时 `Reprojection_Dx12::SetResource` 从 **0** 变成每帧都有（深度 + hudless），目的是把 present 链的掩码/粉色遮罩拉回来。
## 热切换（不用重启游戏）

面板的中文快捷面板里多了一行：**「经典模式 Classic mode (present chain)」**

| 勾选状态 | 等于 | 扭曲发生在 | 帧生成继承 warp？ |
|---|---|---|---|
| 不勾 | `-Mode mfg` | DLSS 输出（机制 C） | 是 |
| 勾上 | `-Mode old` | present 链（显示帧） | 否 |

- 它**立即生效**（两个键都是每帧读的），并且**不碰** `[FrameGen] FGOutput/FGInput` —— 那一对在运行中改动会打断平面喂图（见 `BUGS_AND_ROBUSTNESS.md` 的 B2），所以热切换只动 `TagWarpInPlace` + `PresentOnly`。
- 切换时日志会打印一行：`latewarp hot mode: classic/present-chain (TagWarpInPlace false, PresentOnly true)` 或 `... mechanism-C/MFG ...`。
- 想**持久化**这次选择：用 `latewarp_mode.ps1 -Mode mfg|old`（改 ini，重启后仍然生效）。
- 注意：热切换只切"扭曲在哪一环"。要从"游戏/插件拥有帧生成"切到"OptiScaler 自己插帧"（`FGOutput=Reprojection` + `FGInput=upscaler`），仍然需要改 ini + 重启。