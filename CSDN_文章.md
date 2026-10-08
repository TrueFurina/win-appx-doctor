# 修了 3 小时才明白：Win11「照片」打不开，根本不是组件存储坏了（附排错工具开源）

> **摘要**：系统自带「照片」应用突然打不开，第一反应是组件存储损坏，结果 `DISM /RestoreHealth` 卡 0 字节、uupdump 离线装的 ISO 还因构建号偏低被拒降级……折腾一下午，最后发现真因只是一个 AppX 累积更新卡在「已暂停」。本文完整记录排查全过程、关键反转与根因，并开源一套一键诊断/修复工具，照着做 1 分钟就能解决同类问题。

---

## 一、问题现象

系统环境：**Windows 11 Insider 预览版，build 10.0.26200.9457**（Dev/Canary 通道）。

从某天起，系统自带「照片」应用（`Microsoft.Photos`）彻底打不开，卡在 `DeploymentInProgress, Servicing` 状态；连带微软 Store 也启动失败。AppX 类应用启动直接报错，但系统本身、文件管理器、浏览器都正常——所以一开始判断是**组件存储（Component Store）层面的损坏**。

---

## 二、第一波排查：以为组件存储坏了

### 2.1 DISM /RestoreHealth 卡在 0 字节

第一反应是跑组件存储修复：

```powershell
dism /Online /Cleanup-Image /RestoreHealth
```

结果卡在 **63.4%** 不动。查 `C:\Windows\Logs\CBS\CBS.log`，发现它在从 Windows Update 下载修复源，但**字节数恒为 0**：

```
DWLD: Downloading update (0 of 0 bytes)...0%
```

初步结论：组件存储损坏，且在线修复源拉不下来 → 没法在线修。

### 2.2 sfc /scannow 跑完等于没修

```powershell
sfc /scannow
```

能跑完，但它只负责扫描，**真正补文件依赖 DISM 修好的存储**。而 DISM 这条路已经废了，所以 `sfc` 对这个问题无效。

> **误区记录**：此时我误以为"存储坏了、没法在线修复"，这个假设后面被 DISM 自己推翻。

---

## 三、第二波排查：走上 UUP 离线 ISO 的不归路

既然在线修不了，就走"就地升级修复"（in-place repair）——挂载同版本或更高版本 ISO，跑 `setup.exe` 选"保留个人文件和应用"，重建组件存储与 AppX。

### 3.1 官方 Insider ISO 这条路不通

微软官方 Insider ISO 下载页**认登录态而不是本机版本**，本机是 26200 预览版却被告知"需要成为 Windows Insider 计划成员"，下载被挡。

### 3.2 uupdump 离线下载 + 本地转换

改用 **uupdump.net**（无需会员，可指定 ≥26200 的构建）：下载 UUP 转换包 → 本地 `convert-UUP.cmd` 离线组装 ISO。这一步顺带把"在线修复源拉不到"的锅甩给了公网 WU（UUP 是从微软 CDN 直接拉源，所以不卡）。

缓存约 11GB，转换中途两次撞错：

```
Dism.exe failed adding LCU update{s}
错误码 0xc144012f
```

一度以为**宿主 DISM / 组件存储已死**。

### 3.3 反转：组装出的 ISO 比当前系统还低

好不容易生成 `ISOFOLDER`，准备跑 `setup.exe`，结果一查 `install.wim`：

- 生成的镜像是 **build 26100.1**
- 当前系统是 **26200.9457**

Windows 安装程序**拒绝"降级"就地升级**——26100 < 26200，直接被拒。

> 这条 3 小时的路，最终没用上。但它有一个**关键价值**：逼着我去单独验证组件存储到底坏没坏（见第四节）。

---

## 四、关键反转：组件存储其实很健康

单独跑健康检查（不下载任何东西）：

```powershell
dism /Online /Cleanup-Image /CheckHealth
dism /Online /Cleanup-Image /ScanHealth
```

两者都返回 **"操作成功完成，无组件存储损坏"**，宿主 DISM 版本 `10.0.26100.8972` 工作正常。

回过头看，第三节那个 `0xc144012f` 根本不是宿主 DISM 坏了——它是 **UUP 离线注入脚本（`:uups_msu`）在离线 servicing 时的源排序问题**。脚本对 build ≥ 25336 会强制调用 DISM 注入 LCU，而这次离线注入恰好抽风。这与"宿主组件存储健康与否"无关。

**最初"存储坏了、没法在线修"的假设，被 DISM 自己推翻了。**

> 补充：之前 `/RestoreHealth` 卡 0 字节，是因为预览版的修复源在公网 Windows Update 上**根本不存在**（CBS.log 实证），不是组件存储真坏。

---

## 五、真正的根因：AppX 累积更新卡在「已暂停」

既然存储是健康的，问题就在 AppX 注册层。重注册 `Microsoft.Windows.Photos` 的全部用户包，发现它其实有**两个包**：

| 包版本 | 状态 | 结果 |
|--------|------|------|
| `2026.11090.22001.0`（活动版本） | 重注册成功 | `Status: Ok` |
| `2026.11080.24002.0`（旧版） | 重注册失败 | 报错 `0x80073CF9` |

旧版报错含义：**"程序包已暂停，必须暂存才能继续"** —— 即**一个半完成的 AppX 累积更新残留**，卡在"已暂停/暂存"状态。

好消息是：旧版**不是活动版本**，只是无害残留。活动版本重注册 + `Reset-AppxPackage` 成功后 → `Status: Ok` → 「照片」立刻能打开。

```
Reset-AppxPackage 成功，活动版本 Status: Ok
```

至此确认：照片打不开的真正病根，是 AppX 更新卡在"已暂停"，**与组件存储无关**。

---

## 六、解决方案与工具使用

把"诊断 + 修复"固化成两套脚本，普通用户双击即可：

| 文件 | 作用 | 提权方式 |
|------|------|----------|
| `photos_repair.cmd` | 自提权包装器，双击弹 UAC，内部调用 `photos_repair.ps1` 重注册 + 重置 Photos 包 | 自动提权（推荐） |
| `photos_repair.ps1` | 重注册 + 重置 `Microsoft.Windows.Photos` 全部用户包 | 需手动管理员 PowerShell |
| `dism_check.cmd` | 自提权跑 DISM 健康检查，结果写入 `dism_check.log` | 自动提权 |

**使用步骤**：

1. 「照片」打不开 → 右键 `photos_repair.cmd` →「以管理员身份运行」（或双击点「是」）。
2. 打开「照片」验证是否恢复。
3. 想先确认是不是存储损坏、值不值得做就地升级 → 双击 `dism_check.cmd`，看 `dism_check.log`。

---

## 七、避坑指南（给后来者）

### 7.1 排错决策树

```
AppX 应用（照片/Store）打不开
   │
   ├─ 跑 dism_check.cmd
   │    ├─ 报"组件存储损坏"且能在线修复 → 跑 dism /RestoreHealth 后重试
   │    ├─ 报"损坏"但 /RestoreHealth 卡 0 字节
   │    │    └─ 多为 Insider 预览版，修复源公网不存在 → 用 ≥ 当前构建的 ISO 就地升级
   │    └─ 报"无损坏"（健康）→ 问题在 AppX 注册层
   │
   └─ 跑 photos_repair.cmd（重注册 + 重置活动包）
        ├─ 活动包 Status: Ok → 应用应能打开 ✅
        └─ 仍失败、日志见 0x80073CF9（某包"已暂停/暂存"）
             └─ 提权 Remove-AppxPackage 清掉那个卡住的旧包再重置
```

### 7.2 UUP 离线 ISO 的两个坑

如果你也走到"下载 UUP 离线组装 ISO 做就地升级"这一步，记住：

1. **生成的 ISO 构建号不能低于当前系统**，否则 Windows 安装程序拒绝降级升级。uupdump 默认拉的有时是较旧基础 build，需确认 UUP 集包含 ≥ 当前 build 的 LCU，或手动注入 LCU 再升级 WIM。
2. **UUP 转换脚本对 build ≥ 25336 会强制用宿主 DISM 注入 LCU**。若离线注入抽风（如 `0xc144012f`），需要在 `convert-UUP.cmd` 里加 `if %SkipLCUmsu% equ 0` 守卫，让 `SkipLCUmsu=1` 真正生效——否则每次都死在同一步，还顺手把半成品 `ISOFOLDER` 删掉。

> 大多数情况你根本不需要走到这一步。**先跑 `dism_check.cmd` + `photos_repair.cmd`，多半一两分钟就解决了。**

---

## 八、工具开源

完整工具集已开源，含脚本 + 详细排错 README：

- **仓库地址**：https://github.com/TrueFurina/win-appx-doctor
- 文件：`photos_repair.ps1` / `photos_repair.cmd` / `dism_check.cmd` / `README.md`
- 适用：Windows 10 / 11，PowerShell 5.1+

工具**不下载任何东西、不修改系统文件、不做就地升级**，仅对本机已安装 AppX 包做重注册 / 重置，风险极低。

---

## 九、总结

- 照片打不开，**九成不是组件存储坏了**，而是某个 AppX 累积更新卡在"已暂停"（`0x80073CF9`）。
- `DISM /RestoreHealth` 卡 0 字节，在 Insider 预览版上**通常是修复源公网不存在**，不是你电脑的问题，别被吓到。
- 排错第一性原则：**先诊断、再动手**。一句 `dism /CheckHealth` 能省掉你一下午的 ISO 折腾。
- 真要就地升级，记得 ISO 构建号必须 ≥ 当前系统。

希望能帮你少走这三小时的弯路。

---

**版权声明**：本文为原创，转载请注明出处与作者。文中工具遵循仓库 LICENSE。代码与脚本仅供学习研究，使用风险自负。
