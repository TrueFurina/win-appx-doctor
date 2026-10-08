# win-appx-repair-kit

Windows AppX / 「照片」应用修复小工具集（PowerShell + CMD）。

## 适用场景
- 系统自带「照片」(Microsoft.Photos) 应用打不开、启动崩溃，或 Store 类 AppX 应用异常。
- 想快速判断**组件存储（Component Store）是否真的损坏**，再决定是否值得做就地升级（in-place upgrade）。

## 文件说明
| 文件 | 作用 | 是否需要管理员 |
|------|------|----------------|
| `photos_repair.cmd` | 自提权包装器（双击即弹 UAC 请求管理员），内部调用 `photos_repair.ps1`。**推荐直接用这个。** | 自动提权 |
| `photos_repair.ps1` | 重新注册 + 重置 `Microsoft.Windows.Photos` 的所有用户包。若直接跑此文件，**必须用管理员 PowerShell** 执行（脚本本身不提权）。 | 需手动管理员 |
| `dism_check.cmd` | 自提权运行 `dism /Online /Cleanup-Image /CheckHealth` 与 `/ScanHealth`，结果写入 `dism_check.log`。用于确认组件存储健康状态。 | 自动提权 |

## 用法
1. 照片打不开时：右键 `photos_repair.cmd` →「以管理员身份运行」（或直接双击，弹窗点「是」）。
2. 修复完成后打开「照片」验证。
3. 若想先确认是不是组件存储损坏：双击 `dism_check.cmd`，看 `dism_check.log` 是否报损坏。

## 原理与边界
- 这两个脚本**不修改系统文件、不下载任何东西**，仅对**本机已安装**的 AppX 包做重注册 / 重置，风险极低。
- 照片应用打不开的常见真因是某个 AppX 累积更新**卡在「已暂停 / 暂存」状态**（重注册报错 `0x80073CF9`），而非组件存储损坏。本工具专门处理这类情况。
- 若 `dism_check.cmd` 报组件存储损坏且无法在线修复（常见于 Windows Insider 预览版——修复源在公网 Windows Update 上不存在，`/RestoreHealth` 会卡 0 字节），再考虑用同版本或更高版本的 ISO 做就地升级，而不是先依赖本工具。

## 日志
- `photos_repair.log`：重注册 / 重置的逐包结果。
- `dism_check.log`：DISM 健康检查输出。
