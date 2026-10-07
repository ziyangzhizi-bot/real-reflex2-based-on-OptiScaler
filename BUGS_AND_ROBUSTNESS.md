# BUGS_AND_ROBUSTNESS — 2026-10-07

本轮按用户要求做三件事：健壮性、潜在 bug 定位、面板多余选项。记录在案，供下一轮接手。

## 一、本轮已修

| # | 问题 | 处理 |
|---|---|---|
| 1 | **面板上的调试项删不掉**（删/改会打断后继补丁的锚点，DryRun 报 `anchor matched 0 times`） | 新补丁 T103：用 `Queue-Patch`（正则）在**最终文本**上改，不动任何早先锚点。命中 10 处：2 个调试行改 `if (false && ...)`（不渲染），3 行长标签移到控件上方（`TextUnformatted` + `##id` + `SetNextItemWidth(-1.0f)`），并删掉 3 行调试提示 |
| 2 | **面板 Save Settings 把配置打回 auto**：`FGOutput`/`FGInput` 变 `auto`、调试键被写回、模式跑丢 | `latewarp_fix_ini.ps1`：一条命令把 14 个关键键写回出厂值；`README.md` 写明"不要用 Save Settings 保存 latewarp 配置" |
| 3 | **`DiagMap = 1` 在 present 链模式下把诊断热力图铺到屏幕上**（用户看到的黄/绿遮罩） | ini 改为 `DiagMap = 0`；`latewarp_fix_ini.ps1` 强制该值；README 说明它是什么 |
| 4 | **操作脚本没有备份、也不检测游戏是否在运行** | `latewarp_mode.ps1` / `latewarp_fix_ini.ps1` 增加：写 ini 前自动时间戳备份（`OptiScaler.ini.bak-yyyyMMdd-HHmmss`）、游戏运行中给出警告 |

## 二、待修（都有实测证据，下一轮动手）

### B1 `hkslSetTag` 的提前返回会吞掉 hudless 喂图  ★最高优先
`hooks/Streamline_Hooks.cpp`（pristine 387-392）：
```cpp
if (hasDepth && hasMVs && !hasHudless)          // inside: activeFgInput == DLSSG && gameQuirks[IgnoreTagsWithoutHudlessForFG]
{
    LOG_DEBUG("Skipping the FG tagging of potential DLSS resources");
    return o_slSetTag(viewport, tags, numTags, cmdBuffer);   // <-- 后面我们的 lwProbeBackbufferTag 与 T101 喂图全部被跳过
}
```
- **症状**：present 链那道门要 `hudless && depth`，hudless 永远进不来 ⇒ 没有掩码、没有粉色、没有扭曲（关帧生成那套）。
- **实测**（15:07 局）：`latewarp-diag: active true paused false | gate paced true armed false | hudless -1 depth 1 velocity true extent 2560x1600`，`TAG INVENTORY=0`、`reportResource=0`。
- **建议修法（安全）**：把 T101 的喂图循环从函数结尾**移到这个 `if` 之前**，或在 skip 条件末尾加 `&& !Config::Instance()->ReprojectionUseNvidiaLatewarp.value_or_default()`。前者不改变 MFG 路径的任何行为。

### B2 运行中切换帧生成会让喂图彻底停掉
- **实测**（13:39 局）：`Making a resource copy` 最后一次在 13:40:26，之后 69 秒 **0 次**，同一时段 present 1952 次、`reportResource` 3292 次 ⇒ 后端收不到任何平面，掩码停止刷新。
- **影响**：运行中关掉帧生成 = 当次游戏里 latewarp 变哑巴。
- **建议**：文档写死"切帧生成必须重启游戏"；或加守护：连续 N 帧没有 `SetResource` ⇒ 重建 presenter 并重新注册 FG 上下文。

### B3 失败链仍然会执行 install
- **实测**（E2c44 链）：`[build] REFUSED: Cyberpunk2077.exe is running` 之后 install 仍然被执行（这次被文件锁挡住，否则会把旧 DLL 再装一遍）。
- **影响**：链路中途失败时，装机 hash 不变却以为"装好了"。
- **建议**：链路脚本在任一步非零退出时跳过 install；install 脚本在"目标 DLL 与当前装机 DLL 哈希相同"时打印显著警告。

### B4 用 `Set-Content -Encoding ASCII` 重写补丁脚本会破坏 9 个非 ASCII 字节
- 该脚本里有 9 个非 ASCII 字节（T58 注释里的中文），ASCII 重写会变成 `???`。relay 遇到过，本轮我又遇到过。
- **建议**：脚本编辑一律用 read/edit 或 UTF-8(no BOM) 写；不要再整文件 ASCII 重写。

## 三、面板（用户可见项）最终清单

**保留（能调且生效）**：接管开关、静态元素可视化、遮罩阈值、warp 修正强度、深度截止、武器遮罩、warp 幅度、PresentOnly、Use NVIDIA latewarp。
**隐藏（本轮 T103）**：P3-3 诊断滑块、Feed composite 勾选框（+3 行提示）。
**更早清掉**：高光保护开关、峰值提升两行滑块。
## 四、2026-10-07 本轮实际落地

- **T103（面板）**：10 处改动 —— 2 个调试行改成 `if (false && ...)`（控件不再渲染，但**标签文本保留**，因为门禁断言 `latewarp diag offset map` 必须在文件里出现一次）；7 个长标签移到控件上方（4 个滑块加 `SetNextItemWidth(-1.0f)` + `##id`，3 个勾选框 `##id`）；删掉调试行下面 3 行提示。
- **T104（探针）**：在 `hkslSetTag` 入口加一次性日志 `latewarp-tag: hkslSetTag entered (tags …, numTags …, api …)`。目的：B1 的根因（老模式下 tag 钩子到底有没有被调用、在哪一步提前返回）下一轮能一次看清，不再靠猜。
- **构建门禁**：本轮起，链路里 **verify 不为 PASS 就不执行 install**（`if ($ok) {...} else { SKIPPED }`），直接消灭 B3 的一半风险。
- 补丁计数：213 → **224**（T103×10、T104×1），`verify_p2` 的断言同步到 224。

## 五、下一轮的第一件事（B1 收口）

1. 装好本版后，用 `-Mode old` 跑一局，在 `OptiScaler.log` 里找：
   - `latewarp-tag: hkslSetTag entered` —— **有** ⇒ 钩子在跑，那就是被后面的提前返回吞了（继续看第 2 点）；**没有** ⇒ 钩子没装上或游戏没走这条路（查 T58/T59 的安装条件）。
   - `latewarp-e2c11: TAG INVENTORY` —— 有 ⇒ 函数跑到了结尾；没有 ⇒ 中途返回（`tags == nullptr` / 非 DX12）。
2. 若确认是跳过块吞掉的：把 T101 的 hudless 喂图循环搬到跳过块**之前**（只加调用，不改任何既有行为）。