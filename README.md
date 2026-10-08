# win-appx-doctor

Windows AppX / 系统自带「照片」应用诊断与修复小工具集（PowerShell + CMD）。
**不下载任何东西、不碰系统文件、不做就地升级**，只对本机已安装的 AppX 包做重注册 / 重置，风险极低。

> 一句话定位：照片 / Store 类应用打不开时，先用它；不确定是不是组件存储损坏时，也先用它（自带健康检查）。

---

## 目录
- [背景故事：一次真实的排错全过程](#背景故事一次真实的排错全过程)
- [什么时候用这个工具](#什么时候用这个工具)
- [文件说明](#文件说明)
- [用法](#用法)
- [排错决策树](#排错决策树)
- [原理与边界](#原理与边界)
- [日志](#日志)
- [关于那条 UUP 弯路（经验教训）](#关于那条-uup-弯路经验教训)
- [免责声明](#免责声明)

---

## 背景故事：一次真实的排错全过程

这套工具是从一次**折腾了整整一下午**的真实故障里提炼出来的。把弯路记下来，是为了让你别再走一遍。

**症状（Windows 11 Insider 预览版 build 26200.9457）**
- 系统自带「照片」(Microsoft.Photos) 应用从 9/27 起打不开，卡在 `DeploymentInProgress, Servicing` 状态。
- 微软 Store 也打不开（AppX 启动失败，非联网问题）。

**弯路 1：DISM /RestoreHealth 卡在 0 字节**
- 第一反应是组件存储损坏，跑 `dism /Online /Cleanup-Image /RestoreHealth`。
- 结果卡在 63.4%，CBS.log 实证它在从 Windows Update 下载修复源，但**字节数恒为 0**（`DWLD: Downloading update (0 of 0 bytes)...0%`）。
- 根因：预览版的修复源在公网 WU 上**根本不存在**（即使开代理也拉不到）。所以 `/RestoreHealth` 卡死 ≠ 组件存储真坏。

**弯路 2：sfc /scannow 跑完等于没修**
- `sfc /scannow` 能跑完，但它只扫描、依赖 DISM 修好的存储才能补文件，而 DISM 这条路已废 → 无效。

**弯路 3：uupdump 离线 ISO（3 小时白忙，但有价值）**
- 官方 Insider ISO 下载页认登录态不认本机版本，此路不通；改用 uupdump.net 指定 ≥26200 构建下载 UUP 源。
- 缓存 11GB，本地用 `convert-UUP.cmd` 离线组装。中途两次撞 `0xc144012f`（Dism failed adding LCU）——一度以为宿主 DISM / 组件存储已死。
- 终于组装出 `ISOFOLDER`，准备跑 `setup.exe` 就地升级，结果一查：**生成的 `install.wim` 是 build 26100.1，比当前系统 26200.9457 还低**。
- Windows 安装程序**拒绝"降级"就地升级**。这条 3 小时的路，最终没用上。

**反转：组件存储其实没坏**
- 单独跑了 `dism /Online /Cleanup-Image /CheckHealth` 与 `/ScanHealth` → 全部 **"操作成功完成，无损坏"**。
- 原来 `0xc144012f` 是 UUP 离线注入脚本的**源排序问题**，不是宿主 DISM 真的坏了（DISM 本身能正常跑）。
- 最初"存储坏了、没法在线修"的假设被 DISM 自己推翻。

**真正的病根：AppX 更新卡在"已暂停"**
- `Microsoft.Windows.Photos` 有两个包：活动版本 `2026.11090.22001.0` 和一个旧版 `2026.11080.24002.0`。
- 旧版重注册时报 `0x80073CF9`——"程序包已暂停，必须暂存才能继续"——即**一个半完成的 AppX 累积更新残留**，拖死了照片应用。
- 但旧版不是活动版本，活动版本重注册 + `Reset-AppxPackage` 成功 → `Status: Ok` → 照片立刻能打开。

**结局**
- 没做就地升级、没挂载 ISO、没清组件存储，一行重注册 + 重置就修好。
- 这套工具就是把"诊断 + 修复"固化下来的产物。

---

## 什么时候用这个工具

| 场景 | 动作 |
|------|------|
| 「照片」/ Store / 任意 AppX 应用打不开、启动崩溃 | 跑 `photos_repair.cmd` |
| 想确认是不是组件存储损坏，**再决定是否值得做就地升级** | 先跑 `dism_check.cmd` |
| 准备花 1 小时做就地升级前，想排除"其实只是 AppX 卡住" | 两个都跑，先 `dism_check` 再 `photos_repair` |

---

## 文件说明

| 文件 | 作用 | 提权方式 |
|------|------|----------|
| `photos_repair.cmd` | 自提权包装器（双击即弹 UAC），内部调用 `photos_repair.ps1`。**推荐直接用这个。** | 自动提权 |
| `photos_repair.ps1` | 重新注册 + 重置 `Microsoft.Windows.Photos` 的所有用户包。直接跑此文件**必须用管理员 PowerShell**（脚本本身不提权）。 | 需手动管理员 |
| `dism_check.cmd` | 自提权运行 `dism /Online /Cleanup-Image /CheckHealth` 与 `/ScanHealth`，结果写入 `dism_check.log`。 | 自动提权 |

> 自提权原理：`.cmd` 检测到非管理员时，用 `powershell Start-Process -Verb RunAs` 重新拉起自身并弹 UAC，由你点「是」完成提权——比手动开管理员 PowerShell 省事。

---

## 用法

1. 照片打不开时：右键 `photos_repair.cmd` →「以管理员身份运行」（或双击，弹窗点「是」）。
2. 修复完成后打开「照片」验证。
3. 若想先确认是不是组件存储损坏：双击 `dism_check.cmd`，看生成的 `dism_check.log` 是否报损坏。

---

## 排错决策树

```
AppX 应用（照片/Store）打不开
        │
        ├─ 跑 dism_check.cmd
        │     ├─ 报"组件存储损坏"且能在线修复 → 跑 dism /RestoreHealth 后重试应用
        │     ├─ 报"组件存储损坏"但 /RestoreHealth 卡 0 字节
        │     │     └─ 多为 Insider 预览版，修复源在公网 WU 不存在
        │     │         → 用 ≥ 当前构建的 ISO 做就地升级（注意：生成的修复源不能低于当前 build，否则被拒）
        │     └─ 报"无损坏"（健康）
        │           └─ 问题在 AppX 注册层，不是存储层 → 继续 ↓
        │
        └─ 跑 photos_repair.cmd（重注册 + 重置活动包）
              ├─ 活动包 Status: Ok → 应用应能打开 ✅
              └─ 仍失败、日志见 0x80073CF9（某包"已暂停/暂存"）
                    └─ 提权 Remove-AppxPackage 清掉那个卡住的旧包再重置
```

---

## 原理与边界

- 这两个脚本**不修改系统文件、不下载任何东西**，仅对**本机已安装**的 AppX 包做重注册 / 重置，风险极低。
- 照片应用打不开的常见真因是某个 AppX 累积更新**卡在「已暂停 / 暂存」状态**（重注册报错 `0x80073CF9`），而非组件存储损坏。本工具专门处理这类情况。
- 若 `dism_check.cmd` 报组件存储损坏且无法在线修复（常见于 Windows Insider 预览版——修复源在公网 Windows Update 上不存在，`/RestoreHealth` 会卡 0 字节），再考虑用**同版本或更高版本**的 ISO 做就地升级，而不是先依赖本工具。

---

## 日志

- `photos_repair.log`：重注册 / 重置的逐包结果（含版本号与 `Status`）。
- `dism_check.log`：DISM 健康检查输出（CheckHealth / ScanHealth）。

---

## 关于那条 UUP 弯路（经验教训）

如果你也走到"下载 UUP 离线组装 ISO 做就地升级"这一步，记住两个坑：

1. **生成的 ISO 构建号不能低于当前系统**，否则 Windows 安装程序拒绝降级升级。uupdump 默认拉的有时是较旧的基础 build，需确认 UUP 集包含 ≥ 当前 build 的 LCU，或手动注入 LCU 再升级 WIM。
2. **UUP 转换脚本对 build ≥ 25336 会强制用宿主 DISM 注入 LCU**，若宿主 DISM 在离线 servicing 时抽风（如 `0xc144012f`），需要在 `convert-UUP.cmd` 里加 `if %SkipLCUmsu% equ 0` 守卫，让 `SkipLCUmsu=1` 真正生效——否则每次都死在同一步、还顺手把半成品 `ISOFOLDER` 删掉。

大多数情况下，你根本不需要走到这一步。**先跑 `dism_check.cmd` + `photos_repair.cmd`，多半一两分钟就解决了。**

---

## 免责声明

- 本工具仅做 AppX 包重注册 / 重置，不修改系统文件。但仍建议在执行任何系统维护前，对重要数据自行备份。
- 作者不对使用本工具导致的任何问题负责；如不确定，请先在虚拟机或测试机验证。
- 适用于 Windows 10 / 11 的 PowerShell 5.1+ 环境。
