# WsDoctor 更新日志

## v1.4.0（2026-11-08）

### 新增：self-contained 发布（免安装 .NET）
- `gui\publish-selfcontained.ps1`：
  - 优先 `dotnet publish -r win-x64 --self-contained true -p:PublishSingleFile=true`（需联网下载 runtime packs）
  - **离线回退**：用本机已装的 shared runtime（.NET 10.0.14 + WindowsDesktop 10.0.14）+ hostfxr 手工组装 self-contained 目录
    （251 个文件 / **154.3 MB**，自动生成 runtimeconfig `includedFrameworks` 与完整 deps.json）
  - 支持 `-Sign` 自动签名、`--selftest` 自动验证（73/73）
- 产物 `gui\dist-selfcontained\WsDoctorGui.exe`：**目标机器无需安装 .NET** 即可运行

### 新增：PowerShell 7 检测与引导（②）
- `BridgeService.TryResolvePowerShell`：按 `WSDOC_PWSH` 覆盖 → 当前进程 → PATH → `Program Files\PowerShell\7` → `WindowsApps` 顺序探测
- GUI 启动时若未找到 pwsh：弹窗说明 + 下载链接，用户可选择"仍要打开界面"
- 未检测到时执行动作会给出友好错误（而不是底层的"系统找不到指定的文件"）
- 新增 `--check-env` 环境检查：OS / .NET / AppBase / ProjectRoot / 模块 / PowerShell 7 → 输出到控制台并写入 `%TEMP%\wsdoctor-gui\check-env.log`，退出码 0/1

### 发布与签名
- 两个发布包均签名：`wsdoctor-gui-1.4.0-signed.zip`（框架依赖，~160 KB）、`wsdoctor-gui-1.4.0-selfcontained-signed.zip`（~154 MB 解压后，免 .NET）
- ③「桥接逻辑改写成 C#、彻底去掉 PowerShell 依赖」按用户决定放弃（不做）

### 验证
| 项 | 结果 |
|---|---|
| 模块测试 | 50/50 |
| 框架依赖 exe `--check-env/--selftest/--uitest/--integration` | 全部 exit 0 |
| self-contained exe `--check-env/--selftest/--uitest/--integration/--action Scan` | 全部 exit 0 |
| PS7 缺失模拟（WSDOC_PWSH 指向不存在） | `--check-env` exit 1，动作返回友好错误 |
| 签名 | exe + dll Authenticode SHA256（自签名，指纹 F3D393AA…） |

## v1.3.0（2026-11-08）

### 新增
- **扫描前预计耗时**：`Measure-WsScanWork`（只做剪枝枚举统计，不聚合/不读内容）
  - bridge 新增 `-Action EstimateScan`；GUI 点「扫描」先估算约 2 秒，弹窗显示"预计约 X 秒 / 文件数 / 目录数 / 模式"，用户可继续或取消
  - 实测校准（`D:\1Work` 11,766 文件）：串行估算 3s（实际 2.67s）、并行估算 2s（实际 1.78s）
- **代码签名发布**：`gui\sign-exe.ps1` 生成自签名 CodeSigning 证书并签名 `WsDoctorGui.exe` / `WsDoctorGui.dll`
  - 证书：CN=WsDoctor GUI (Self-Signed)，SHA256，5 年，Code Signing EKU，指纹 `F3D393AA389CA0FDDCAB3EB04CD8C989DBF5145A`
  - 发布包附带公钥证书 `.cer`、SIGNING-README（校验/信任步骤）；私钥 `.pfx` 只留本地、已被 .gitignore 排除
  - 校验：`Get-AuthenticodeSignature` 签名链处理通过（自签名未受信任时状态为 `UnknownError`，属正常；信任后变 `Valid`）

### 修复
- bridge `Estimate` 动作参数名笔误（`-MinDupSize` → `-MinSize`），集成测试已覆盖

### 验证
| 项 | 结果 |
|---|---|
| 模块测试 | 50/50 |
| GUI 集成（Roslyn / 签名 exe） | 0 项失败 |
| exe 签名 | 签名已写入，证书链校验通过（仅缺信任根） |
| GUI `--action` Scan/Estimate/Duplicates | exit 0 |

## v1.2.2（2026-11-08）

### 修复与诊断
- **「桥接未生成结果文件（exit=1）」偶发失败**：典型原因是在脚本/程序热更新窗口期点击了动作（bridge 脚本被读到半截、或子进程被杀）
  - `bridge.ps1` 现在在结果文件旁写 `.log`（START / DONE / TRAP / 序列化失败），退出时 finally 兜底写 JSON
  - GUI 失败对话框会附带**桥接日志尾部**，以后可直接看到原因
- **清空目录提速**：`Remove-WsEmptyDirectory` 改用剪枝目录枚举（不再遍历 `.dsh-snapshots`/`.venv` 等）
  - `D:\1Work` 的 `-WhatIf`：33 s → **9.5 s**
- 新增 GUI 自动化回归 `WsDoctorGui.exe --action <Scan|Duplicates|Clean|Audit|Report|Estimate> --path <目录>`：
  走与界面完全相同的子进程链路，实测 6 个动作全部成功
- 版本 1.2.2

### 验证
| 项 | 结果 |
|---|---|
| 模块测试 | 50/50 |
| GUI 链路（exe --action） | Scan/Estimate/Duplicates/Report/Clean/Audit 全部 exit 0 |
| --uitest / --selftest / --integration | 全部通过 |

## v1.2.1（2026-11-08）

### 修复
- **非扫描动作会清空「目录 / 大文件」页数据**：`ApplyResult` 原先无条件用当前动作结果覆盖全部表格
  → 现在按动作类型只更新对应页（scan→目录/大文件、duplicates→重复、audit→体检、clean→清理、report→报告、estimate→不动）
  - 现象：先点「扫描」有数据，再点「重复文件」后「大文件」变空
- GUI 版本 1.2.1；两套构建、--uitest / --selftest / --integration 全部回归通过

## v1.2.0（2026-11-08）

### 性能：重复文件检测
- **枚举剪枝**：`Get-WsPrunedFiles` 递归时直接跳过排除目录（不再遍历 `.dsh-snapshots`/`.venv` 等 13 万+ 文件）
  - `D:\1Work` 枚举：68.7 s → **1.8 s**
- **两阶段哈希**：按大小分组 → 只读每个候选前 64 KB 算前缀哈希 → 仅对"大小+前缀相同"的文件做全量 SHA256
  - `D:\1Work`：203.9 s → **5.6 s（热缓存）/ 40 s（冷缓存）**，结果 988 组完全一致
  - 小目录自动策略：两阶段无收益时自动退化为全量哈希（`项目` 1.6 s）
- **并行哈希**：候选 ≥16 时按 `-ThrottleLimit` 分块并行，用 .NET `SHA256` 替代 `Get-FileHash` cmdlet；新增 `-SampleSize`（0=关闭两阶段）与 `-NoParallel`
- `Invoke-WsScan` 的默认/Chunk 路径同样改用剪枝枚举（含排除目录不再被遍历）

### 新增：重复检测预计耗时（GUI 先估算再让用户决定）
- 模块新增 `Measure-WsDuplicateWork`：只做剪枝枚举 + 取样统计，返回候选数/候选体积/预计耗时（不读文件内容）
- `bridge.ps1` 新增 `-Action Estimate`；GUI 点「重复文件」先估算约 2 秒，弹窗显示预计耗时 + 明细，用户可选择继续或取消
- 集成测试新增 estimate 校验；模块测试 47 → **50**

### 自测抓到的 bug
- 两阶段分组时用占位哈希 `prefix:size` 构造 `WsDuplicateGroup`，触发 `HashShort.Substring(0,12)` 越界
  → 小文件（≤取样长度）的前缀哈希本身就是完整 SHA256，直接作为组哈希；大文件组使用全量哈希
- `-SampleSize 0` 时仍走前缀分支且估算模型错误 → 增加显式全量分支与对应估算
- 小目录两阶段反而慢（`项目` 4.2 s vs 全量 1.3 s）→ 自动策略按"预计读盘量 ≥ 全量 50%"切换为全量

## v1.1.2（2026-11-08）

### 修复
- **点击「日志」页崩溃/弹窗死循环**（"Parameter is not valid."）：
  - 根因：`OnLogDrawItem` 里 `using var font = e.Font ?? ...` 把 **ListBox 自己的 Font 实例 Dispose** 了；
    下一次 owner-draw 重绘使用已释放字体 → GDI+ 抛 `ArgumentException("Parameter is not valid.")` → 重绘/异常循环
  - 修复：借用字体不释放，只 Dispose 自己创建的临时字体；绘制异常捕获后写 Debug，杜绝重绘死循环
  - 防御：三个自定义绘制控件（HeaderPanel/StatCard/HeadlineBar）增加空尺寸保护
- **全局异常兜底**：`Application.ThreadException` + `AppDomain.UnhandledException` → 完整堆栈写入 `%TEMP%\wsdoctor-gui\gui-error.log`，弹窗只弹一次（避免弹窗风暴）
- 新增 **UI 回归测试** `WsDoctorGui.exe --uitest`：注入日志、切到「日志」页并强制重绘 3 轮，检测绘制异常（当前 PASS）
- GUI 版本 1.1.2；Roslyn 动态编译与 csproj 两套构建均已回归（自检 73、集成 6、uitest PASS）

## v1.1.1（2026-11-08）

### 新增
- GUI 增加**标准 .NET 工程**：`WsDoctorGui.csproj`（net10.0-windows / WinExe / UseWindowsForms / Nullable / 1.1.1）+ `app.manifest` + `NuGet.config`
- `gui\build-exe.ps1`：离线构建独立 exe → `gui\dist-exe\WsDoctorGui.exe`（apphost + dll + deps + runtimeconfig，共约 294 KB，框架依赖 .NET 10 Desktop Runtime）
- `Program.Main`：exe 支持 `--selftest` / `--integration` / `--screenshot <png>` / `--help`；测试输出写入 `%TEMP%\wsdoctor-gui\*.log`
- 验证：exe 自检 exit 0、集成测试 exit 0、离屏截图 65101 字节、真实窗口可见（标题正确）
- 打包排除 GUI 构建产物（bin/obj/.dotnet-home/dist-exe）

### 背景与要点
- VS Code 的 C# 扩展在本机自动安装了 .NET SDK 10.0.403（此前没有）→ 不再只能用 Roslyn 动态编译
- 受限网络/沙箱下构建：`NuGet.config` 清空源（零包依赖可离线 restore）+ `DOTNET_CLI_HOME` 指向工作区（用户目录不可写）
- .NET 10 WinForms 新增 WFO1000 分析器对自定义控件属性报错（我们不做设计器序列化）→ csproj 里 `NoWarn`

## v1.1.0（2026-11-08）

### 新增
- **C# WinForms 前端 GUI**（`gui/`）：桌面交互窗口，覆盖「扫描 / 重复文件 / 清空目录 / 规则体检 / 导出报告」五类动作
  - 技术路线：PowerShell 7 自带 **Roslyn** 编译 C#（本机无 .NET SDK），C# 主程序通过 `bridge.ps1` 子进程调用 WsDoctor 模块，结果经 JSON 文件中转
  - UI：自定义绘制（渐变标题栏、统计卡片、HeadlineBar）、DataGridView 数据绑定、彩色 OwnerDraw 日志、拖拽目录、F5–F9 快捷键、取消运行、DryRun 二次确认
  - 验证：C# **自检 73 项断言** + **桥接集成测试 6 项** + **离屏截图回归**（`-Screenshot`）
- GUI 使用说明与 **C# 知识点地图**：`gui/README.md`（28+ 知识点 → 源码文件）
- 主 README 增加 GUI 章节与截图；打包内容加入 `gui/`（排除 bin/obj）
- 模块版本 1.1.0；测试仍为 47 项全通过

### 过程中修复的问题
- Roslyn 编译：`-ReferencedAssemblies` 会替换默认引用集，导致 record/泛型编译失败 → 直接用 Roslyn API 引用 `$PSHOME` 全部托管程序集
- `Progress<T>.Report` 是显式接口实现 → 声明为 `IProgress<T>` 才能调用
- SplitContainer 在构造期设置 MinSize/SplitterDistance 会抛异常 → 移到 `OnLoad` 且按宽度判断
- `Paths.BridgeScript` 漏了 `gui` 子目录 → 桥接 exit=64（找不到脚本）
- 取消令牌在入口未检查 → 先 `ThrowIfCancellationRequested` 保证快速取消
- Header 状态胶囊按测量文本动态宽度，避免长状态被裁剪

## v1.0.0（2026-11-08）

### 收尾特性
- **Tab 补全**：`ArgumentCompleter` 属性加到 `-Path` / `-ConfigPath` / `-OutDir`（文件/目录补全）、`-ParallelMode`（三种模式）、`-Format`（报告格式）
- **脚本帮助**：`wsdoctor.ps1` 顶部 comment-based help，`Get-Help .\wsdoctor.ps1 -Detailed` 可用
- **`-Version`**：输出 `WsDoctor 1.0.0` 后退出（便于脚本/任务探测）
- CLI 暴露 `-ParallelMode`（DirBucket / Subtree / Chunk），与配置项分离
- 测试 44 → **47 个用例**（-Version 输出、模块版本与清单一致、五个参数补全属性存在）
- 版本号 1.0.0（模块清单 / 打包 / README / CHANGELOG 一致）

### 最终状态
| 门禁 | 结果 |
|---|---|
| lint | 0 error / 0 warn |
| Pester | 47/47 通过 |
| 代码覆盖率 | 70.98%（609/858） |
| 打包 | `dist\wsdoctor-1.0.0.zip` + SHA256 |

### 自测抓到并修复的问题
- 测试用 `$_ .TypeName.Name` 判断补全属性：脚本参数属性的实际类型是 `ArgumentCompleterAttribute` 实例，"TypeName" 是 AST 节点才有的属性 → 改用 `-is [System.Management.Automation.ArgumentCompleterAttribute]`
- `-Version` 输出带前缀 "WsDoctor "，正则断言要匹配前缀而不是纯数字

## v0.8.0（2026-11-08）

### 新增
- `pack.ps1`：打包发布 zip + SHA256 校验和
  - 先计算文件清单再动手（`-WhatIf` 只预览、不产生半成品）
  - 暂存到临时目录保留相对结构 → `ZipFile.CreateFromDirectory` → 校验和文件
  - 内容：模块 + 3 个脚本 + config/formats/bench/tests/docs/install
- CLI `-DryRun`：所有会写盘/删除的动作统一切换为预览模式（等价全局 `-WhatIf`）
- `install\Register-WsDoctorTask.ps1`：注册/删除「每周工作区体检」计划任务
  - `New-ScheduledTaskAction/Trigger/Settings/Principal`，当前用户 + RunLevel Limited
  - `-WhatIf` 只打印计划（不触碰 CIM，沙箱内也能演练）；实际注册需本机普通终端
- 测试从 41 → **44 个用例**（CLI DryRun、pack -WhatIf、计划任务 -WhatIf）
- 版本号 0.8.0；`dist/` 加入 gitignore

### 实测
- 普通 build：44/44 通过
- 覆盖率 build：70.98% ≥ 70%
- 打包：`wsdoctor-0.8.0.zip`（14 个文件 / 43.8 KB）+ `.sha256`
- CLI DryRun：空目录保留、报告不落盘；计划任务 -WhatIf：只打印计划

### 自测抓到并修复的问题
- pack.ps1 第一版把暂存/复制放在 ShouldProcess 之前：`-WhatIf` 会先执行 New-Item/Copy-Item，产生 What if 噪音且可能留下半成品
  → 重构为"先算清单 → ShouldProcess → 再暂存压缩"
- 计划任务脚本第一版在 ShouldProcess 之前就调用 `New-ScheduledTaskAction`，沙箱内直接报"无法从客户端中访问 CIM 资源"
  → 把 CIM 调用移到 ShouldProcess 之后，`-WhatIf` 纯打印

## v0.7.0（2026-11-08）

### 新增
- `build.ps1` 增加 **代码覆盖率门禁**：`-Coverage`（Pester 3.4 `-CodeCoverage`）+ `-MinCoverage` 阈值（默认 60），低于阈值失败；未覆盖明细写入 `coverage-missed.txt`
- `lint-wsdoctor.ps1` 规则分级（Error 失败 / Warn 提示）并新增：
  - 导出函数批准动词检查（`Get-Verb`）、`[CmdletBinding()]`、`[OutputType()]` 要求
  - 参数名 PascalCase 检查、函数体长度 ≤150 行、模块内绝对路径字面量禁止
- 测试从 32 → **41 个用例**（Format-WsSize 三分支、类构造保护、Severity 阈值、7 类配置错误、缺失配置文件、报告 -WhatIf、体检保留数内、清理排除规则）
- 版本号 0.7.0

### 实测
| 门禁 | 结果 |
|---|---|
| lint | 0 error / 0 warn |
| Pester | 41/41 通过 |
| 代码覆盖率 | **70.98%**（609/858 条命令） |

### 自测抓到并修复的问题
- **Pester 3.4 没有 `-Show` 参数**（那是 Pester 4+），传了直接报参数错误
- **lint 对私有函数误报 CmdletBinding**：私有 helper 不需要高级函数；规则上移到"仅导出函数"检查
- 覆盖率第一版 67.37% → 补分支用例后 70.98%；剩余未覆盖主要是异常分支（I/O 失败）与 runspace 内部语句

## v0.6.0（2026-11-08）

### 新增
- **DirBucket 并行模式**（`-ParallelMode` 新增选项，且为新默认）：.NET BFS 枚举目录（排除剪枝）→ 目录轮流分成 ThrottleLimit 个桶 → 每个 runspace 扫自己的目录直属文件并聚合 → 主线程合并
  - 关键优化：每桶只保留有界 TopN（不再为每个文件建记录对象）；目录枚举改为 .NET API，避免几千次 `Get-ChildItem`
- **工作区规则体检** `Invoke-WsWorkspaceAudit`：配置驱动检查
  - `workspace.snapshotKeep`：`.dsh-snapshots` 快照数超过保留策略时，列出最旧的可删项
  - `workspace.residuePatterns`：根目录条目名称正则（如历史 QQ 数据目录）
  - 空 `temp` 目录提示；返回 `WsFinding[]`（Severity/Category/Target/Message/Action）
- 配置新增 `workspace` 节（默认 snapshotKeep=4，残留规则 `^\d{6,}$`、`^(nt_qq|All Users)$`）并做字段校验
- CLI 新增 `-Audit` 动作（可与 `-Scan`/`-FindDuplicates` 组合）
- 测试从 26 → **32 个用例**（DirBucket 等价性/排除、体检三类规则、workspace 配置）

### 实测（D:\1Work\项目，29,937 文件 / 2.32 GB，ThrottleLimit=8）
| 模式 | 耗时 | 加速比 |
|---|---|---|
| 串行 | 4.46 s | 1.00x |
| **DirBucket** | **2.11 s** | **2.11x** |
| Subtree | 3.30 s | 1.35x |
| Chunk | 3.96 s | 1.12x |

### 自测抓到并修复的问题
- **DirBucket 首版只有 0.34x**：逐目录 `Get-ChildItem` 的 cmdlet 开销 + 每文件 `pscustomobject` 分配，比串行还慢
  → 改 .NET `EnumerateDirectories` + 有界 TopN 列表 + 按目录键直接累加，提升到 2.1–2.7x
- 目录键聚合：DirBucket 里文件一定属于当前目录，可直接按 `$directory` 累加，省一次 `GetDirectoryName`

## v0.5.0（2026-11-08）

### 新增
- `Invoke-WsScan -Parallel`：两种并行模式
  - `-ParallelMode Subtree`（默认）：顶层子目录为工作单元，**枚举 + 聚合都在 runspace 内**完成，主线程合并结果
  - `-ParallelMode Chunk`：先串行枚举文件清单，再连续分块并行聚合（用于观察 Amdahl 上限）
  - `-ThrottleLimit` 控制并行度；`$using:` 只传只读参数，runspace 内自建 hashtable
- TopN 排序改为**确定性的**（大小降序 + 路径升序），串行/并行/新旧实现的 Top 列表可逐项对比
- 配置项 `scan.parallel` / `scan.throttleLimit`（默认 false / 4），CLI `-Parallel` / `-ThrottleLimit` / `-ParallelMode`
- `bench\parallel-benchmark.ps1`：三种模式耗时 + 等价性校验
- 测试从 20 → **26 个用例**（Subtree/Chunk 等价性、参数互斥、非法 ParallelMode、配置默认值）

### 实测（D:\1Work\项目，29,937 文件 / 2.32 GB，ThrottleLimit=8）
| 模式 | 耗时 | 加速比 |
|---|---|---|
| 串行 | 4.42 s | 1.00x |
| Subtree 并行 | 3.62 s | 1.22x |
| Chunk 并行 | 4.18 s | 1.06x |

分析：Chunk 受串行枚举限制（Amdahl）；Subtree 受负载不均限制（单个大子树占 ~87% 文件）；
小目录并行收益被 runspace 启动开销抵消（1.05–1.12x）。

### 自测抓到并修复的问题
- **变量名大小写不敏感冲突**：局部 `$top` 与参数 `$Top`（[int] 约束）是同一个变量，赋值数组 → Int32 转换异常；改名为 `$topList`
- **并列排序不稳定**：多种实现 TopN 在等大小文件上顺序不同 → 加路径升序做确定性兜底（否则等价性测试会误报）
- 新增 `Merge-WsAggregateParts` 统一合并逻辑，串行/并行共用，避免三处重复实现

## v0.4.0（2026-11-08）

### 新增
- `config\default.json`：scan（top/exclude）/ duplicates（minSize）/ report（formats/outDir）三节默认配置
- `Import-WsConfig`：默认配置 → 用户配置文件 → `-Override` 三层深合并；`Test-Json` 预校验 + 字段级校验（错误带字段名）
- `Export-WsReport`：一次导出 JSON（DTO + schemaVersion）、CSV（directories/top-files/duplicates 三个文件）、HTML（ConvertTo-Html，路径自动转义）；支持 `-WhatIf`
- `formats\WsDoctor.format.ps1xml`：自定义视图（`WsScanResult` 列表视图、`WsDuplicateGroup` 表格视图），由清单 `FormatsToProcess` 自动加载
- CLI：`-ConfigPath`、`-OutDir`、`-Format Json,Csv,Html,All`；配置优先级 默认 → 用户文件 → CLI 参数
- 类补充计算属性：`SizeText`/`TotalSizeText`/`DirectoryCount`/`FileCount`/`WastedText`/`HashShort`/`SampleFile`（供格式化视图用 PropertyName，避免 ScriptBlock）
- 测试从 12 → **20 个用例**（配置文件合并/校验/非法 JSON、三种报告生成与内容校验、格式化视图加载）

### 自测抓到并修复的问题（保留记录）
- **format.ps1xml 结构错误**：表格行应为 `TableColumnItems/TableColumnItem`（不是 `TableCells`），否则整个模块导入失败
- **清单路径转义**：`FormatsToProcess = @('formats\WsDoctor.format.ps1xml')` 只能一个反斜杠；双反斜杠会找不到文件
- **类属性缺失**：视图引用 `SampleFile` 但类没声明属性 → 输出对象时报 PropertyNotFound，需类声明 + 构造函数赋值
- **`Get-FormatData` 属性名**：是 `FormatViewDefinition`，不是 `ViewDefinitions`
- **显式传 `$null` 给可空 class 参数**：CLI 改为 splat 按需拼参数

## v0.3.0（2026-11-08）

### 新增
- `Find-WsDuplicateFile`：两阶段重复文件检测（先按大小分组 → 只对同大小候选算 SHA256 → 按哈希聚合），
  返回 `WsDuplicateGroup[]`（Size/Hash/Files/Wasted），按可回收空间降序
- CLI 新增动作开关：`-FindDuplicates` / `-CleanEmptyDirs` / `-Scan`（不传动作时默认扫描），`-MinDupSize` 过滤小文件
- `Format-WsSize` 公开工具函数（CLI 渲染共用，带参数校验）
- `bench\scan-benchmark.ps1`：新旧枚举器对照基准（含等价性校验，不一致退出码 1）
- 默认排除新增 `.venv`（项目目录体积从 2.27 GB 降到 979 MB，扫描 1.27 s）

### 性能
- `Invoke-WsScan` 默认改用 `DirectoryInfo.EnumerateFiles` + `EnumerationOptions`（惰性枚举、跳过无权限、包含隐藏文件）
- 排除规则合并为单个编译正则（每文件只匹配一次，而非 N 次）
- TopN 改为维护 N 条（不再全量排序），去除逐文件 class 实例化与 `-ErrorVariable`
- 实测 `D:\1Work\项目`（29,952 文件 / 2.32 GB）：**47.9 s → 3.34 s（约 14x）**；
  单看枚举器：4.96 s → 3.34 s（1.5x）；`-LegacyEnumerator` 保留旧实现用于对照

### 自测抓到并修复的 bug（保留记录）
- **TopN 输出升序**：内部列表按降序维护，收尾时却从尾部拷贝 → 改为正序拷贝（测试抓出）
- **`Format-WsSize` 未导出**：CLI 使用模块私有函数直接报"术语无法识别" → 提升为公开函数（`Export-ModuleMember` + 清单双更新）
- **`Select-Object -Property` 换行**：参数名后换行导致"Property 缺少自变量" → 先把投影存变量再传
- 回归提醒：模块导出必须在 `Export-ModuleMember` 与 `WsDoctor.psd1` **两处**同步，只改一处 CLI 会失败

## v0.2.1（2026-11-08）

构建门禁自测时发现并修复的 3 个问题（保留记录，作为后续回归提醒）：

- 模块：`$list.AddRange(管道结果)` 在管道只有 1 条结果时会被解包成标量，导致 `PSInvalidCastException`
  → 改为 `[WsFileItem[]]@(...)` 显式数组转换后再 `AddRange`
- lint：`NoWriteHost` 规则误伤 `wsdoctor.ps1` / `build.ps1`（人类入口脚本允许 Write-Host）
  → 规则只对 `.psm1` 生效
- 测试：Pester 3.4 的 `Should Throw` 捕获参数绑定校验异常不稳定
  → 改用 `try/catch + $threw | Should Be $true`，跨 Pester 版本可用

性能基线（本机沙箱文件系统较慢，供 v0.3 优化对照）：

- 扫描 `D:\1Work\项目`：29,951 文件 / 2.27 GB / **47.9 秒**
- 优化方向：`[System.IO.Directory]::EnumerateFiles`、`-Parallel`、避免逐文件 class 实例化

## v0.2.0（2026-11-08）

- 新增 `Remove-WsEmptyDirectory`：级联清理空目录，支持 `-WhatIf` / `-Confirm`（`ShouldProcess`，ConfirmImpact=Medium）
- CLI 新增 `-CleanEmptyDirs` 开关，`-WhatIf` 预览不删除
- 新增 `lint-wsdoctor.ps1`：基于 PowerShell AST 的离线静态检查（4 条规则 + 退出码）
- 新增 `build.ps1`：import → lint → Pester 一键质量门禁
- 新增 Pester 测试 7 个用例（扫描统计/排除/TopFiles/参数校验/WhatIf/级联删除/非空保护）
- 模块清单 `WsDoctor.psd1`（PowerShellVersion 7.0，仅导出 2 个函数）

## v0.1.0（2026-11-08）

- 新增模块 `WsDoctor`：`enum Severity`、`class WsFileItem/WsScanItem/WsScanResult`
- 新增 `Invoke-WsScan`：目录体积扫描（文件数/总大小/按目录聚合/最大文件 Top N）
- 默认排除 `.git`、`node_modules`、`.dsh-snapshots`、`.modules`、回收站
- 不可访问路径只计数告警，不中断扫描
- 新增 CLI `wsdoctor.ps1`（表格渲染 + 退出码约定）
