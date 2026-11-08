# WsDoctor — 工作区体检工具（PowerShell 7 练习项目）

用一个真实可用的 CLI 工具练习 **PowerShell 7 全栈知识点**，从 v0.1 逐步迭代到 v1.0。

当前进度：**v1.4.0**（扫描/Clean/重复检测/JSON 配置/多格式报告/规则体检；lint 0 error/0 warn + **Pester 47 用例** + **代码覆盖率 70.98%**；Tab 补全/帮助/版本；可打包发布、`-DryRun` 演练、计划任务周体检）。

## 快速开始

```powershell
cd D:\1Work\项目\ws-doctor

# 体检某个目录（默认排除 .git / node_modules / .dsh-snapshots / 回收站）
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Top 5

# 帮助 / 版本
Get-Help .\wsdoctor.ps1 -Detailed
pwsh -NoProfile -File .\wsdoctor.ps1 -Version

# 预览空目录清理（不会真删）
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work\项目\ws-doctor -CleanEmptyDirs -WhatIf

# 找重复文件（同大小才做 SHA256，默认跳过 <1KB）
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work\tools -FindDuplicates -MinDupSize 1024

# 性能对照基准（EnumerateFiles vs Get-ChildItem）
pwsh -NoProfile -File .\bench\scan-benchmark.ps1 -Path D:\1Work\项目 -Top 10

# 用自定义配置 + 导出 JSON/CSV/HTML 报告
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work\项目 -FindDuplicates -OutDir .\reports -Format All
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work\项目 -ConfigPath .\my-config.json

# 并行扫描（Subtree：枚举+聚合都并行；Chunk：只并行聚合）
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Parallel -ThrottleLimit 8
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Parallel -ParallelMode Chunk

# 三种扫描模式基准对比
pwsh -NoProfile -File .\bench\parallel-benchmark.ps1 -Path D:\1Work\项目 -ThrottleLimit 8

# 工作区体检（规则来自配置 workspace 节：快照保留数 / 残留目录 / 空 temp）
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Audit

# 门禁：lint + Pester + 代码覆盖率（阈值默认 60，低于则失败）
pwsh -NoProfile -File .\build.ps1 -Coverage -MinCoverage 70

# 打包发布（zip + SHA256 校验和；-WhatIf 只预览文件清单）
pwsh -NoProfile -File .\pack.ps1

# 注册「每周体检」计划任务（实际注册要在本机普通终端执行）
powershell -File .\install\Register-WsDoctorTask.ps1 -Path D:\1Work -DayOfWeek Saturday -Time 09:00
# 删除计划任务：加 -Unregister

# 质量门禁：AST lint + Pester 测试
pwsh -NoProfile -File .\build.ps1
```

## 目录结构

```
ws-doctor/
├── WsDoctor.psm1          # 模块实现：enum / class / 高级函数 / 私有函数
├── WsDoctor.psd1          # 模块清单（Exports / PowerShellVersion 7.0）
├── wsdoctor.ps1           # CLI 入口（CmdletBinding + SupportsShouldProcess + 退出码）
├── lint-wsdoctor.ps1      # AST 静态检查（离线替代 PSScriptAnalyzer）
├── build.ps1              # 构建门禁：import → lint → Pester
├── bench\scan-benchmark.ps1 # 性能基准：EnumerateFiles vs Get-ChildItem
├── bench\parallel-benchmark.ps1 # 性能基准：串行 / Subtree 并行 / Chunk 并行
├── config\default.json    # 默认配置（scan/duplicates/report 三节）
├── formats\WsDoctor.format.ps1xml # 自定义格式化视图（清单 FormatsToProcess 加载）
├── tests\WsDoctor.Tests.ps1  # Pester 3.4 兼容测试
└── docs\README.md / CHANGELOG.md
```

## v0.1 / v0.2 已完成的知识点

| 知识点 | 落点 |
|---|---|
| `Set-StrictMode -Version Latest` | `WsDoctor.psm1` 顶部 |
| `enum` / `class`（含构造函数、方法、类型化属性） | `Severity` / `WsFileItem` / `WsScanItem` / `WsScanResult` |
| 高级函数：`[CmdletBinding()]`、`[OutputType()]`、`param()` 位置参数 | `Invoke-WsScan`、`Remove-WsEmptyDirectory` |
| 参数校验：`[ValidateScript]`、`[ValidateRange]` | 路径必须存在、`-Top` 1–1000 |
| `ShouldProcess` / `-WhatIf` / `-Confirm` | `Remove-WsEmptyDirectory`（ConfirmImpact=Medium） |
| 管道与对象：`Get-ChildItem → 聚合 → class 对象` | `Invoke-WsScan` 只输出对象，渲染交给 CLI |
| 错误处理：`-ErrorVariable` 收集不可访问路径、`try/catch`、`Write-Warning` | 扫描错误计数 + 清理异常不中断 |
| 字典 + 排序 + `Measure-Object` / `Sort-Object` / `Select-Object` | 目录聚合、TopFiles |
| CLI 脚本：common parameters 透传（`-WhatIf`/`-Verbose`）、退出码 0/1 | `wsdoctor.ps1` |
| AST 静态检查：`Parser::ParseFile`、`FindAll`、规则引擎 | `lint-wsdoctor.ps1`（4 条规则 + 退出码） |
| Pester：`Describe/It/Should`、`TestDrive`、`-WhatIf` 断言 | `tests\WsDoctor.Tests.ps1` |
| 文件枚举性能：`[System.IO.EnumerationOptions]` + `DirectoryInfo.EnumerateFiles`（惰性、IgnoreInaccessible、包含隐藏文件） | `Invoke-WsScan` 默认路径；`-LegacyEnumerator` 保留旧实现做对照 |
| 编译正则：多条排除规则合并为单个 `[regex]::new(..., Compiled)`，每文件只匹配一次 | `Get-WsExcludeMatcher` |
| TopN 无全量排序：小顶堆思路只维护 N 条（插入即排序） | `Invoke-WsScan` 的 `$topFiles` |
| 两阶段去重：先按大小分组，只对同大小候选算 SHA256，再按哈希聚合 | `Find-WsDuplicateFile` + `WsDuplicateGroup` |
| 基准测试与等价性校验：`Measure-Command`、新旧实现结果必须一致 | `tests\...` 等价性用例 + `bench\scan-benchmark.ps1` |
| JSON 配置：`ConvertFrom-Json -AsHashtable`、`Test-Json` 预校验、递归深合并、字段级校验 | `Import-WsConfig` + `config\default.json` |
| 报告生成：`ConvertTo-Json`（DTO 组装）、`Export-Csv`、`ConvertTo-Html -Fragment`（自动转义） | `Export-WsReport`（JSON/CSV/HTML，支持 `-WhatIf`） |
| 自定义格式化视图：`.format.ps1xml` + 清单 `FormatsToProcess`（PropertyName 优先，避免 ScriptBlock） | `formats\WsDoctor.format.ps1xml`（WsScanResult 列表视图 / WsDuplicateGroup 表格视图） |
| 配置优先级：默认 → 用户文件 → CLI -Override 三层合并 | wsdoctor.ps1 的 $override 组装 |
| 并行：ForEach-Object -Parallel + -ThrottleLimit、$using: 传只读参数、runspace 内自建 hashtable（不共享可变状态） | Invoke-WsSubtreeAggregate / Invoke-WsParallelAggregate |
| 并行模式设计：Subtree（枚举+聚合并行，受负载均衡影响）/ Chunk（串行枚举+分块聚合，受 Amdahl 限制） | -ParallelMode 参数 + ench\parallel-benchmark.ps1 |
| 确定性排序：同大小按路径升序兜底，多种实现输出可逐项对比 | TopN 排序逻辑 + 等价性测试 |
| DirBucket 并行：`.NET BFS` 枚举目录（带排除剪枝）→ 目录轮流分桶 → runspace 内扫直属文件，只保留有界 TopN | `Get-WsDirectoryList` + `Invoke-WsDirBucketAggregate` |
| 规则体检：配置驱动的检查项（快照保留数/残留名称正则/空目录），输出 WsFinding（Severity/Category/Target/Action） | Invoke-WsWorkspaceAudit + 配置 workspace 节 |
| 覆盖率门禁：Pester -CodeCoverage、命令级覆盖率百分比、-MinCoverage 阈值、未覆盖明细落文件 | uild.ps1 -Coverage -MinCoverage 70 |
| AST 规则分级：Error/Warn、Get-Verb 批准动词、导出函数 [CmdletBinding()]/[OutputType()]、参数 PascalCase、函数长度上限、绝对路径字面量 | lint-wsdoctor.ps1 |

## 环境说明（本机实测）

- PowerShell **7.6.9**
- Pester 仅 **3.4.0**（PSGallery 不可达、系统目录不可写，无法安装 Pester 5），测试语法保持 3.4 兼容
- 无 PSScriptAnalyzer → 用 `lint-wsdoctor.ps1`（AST）承担离线静态检查，后续网络可用时可加回

## 路线图（后续阶段要补的知识点）

| 版本 | 内容 | 新增知识点 |
|---|---|---|
| v0.3 ✅ | 重复文件检测（两阶段哈希）、EnumerateFiles 性能优化 | 已完成（见下方性能基准） |
| v0.4 ✅ | JSON 配置、JSON/CSV/HTML 报告、自定义格式化视图 | 已完成 |
| v0.5 ✅ | 并行扫描（Subtree/Chunk 双模式 + 基准对比） | 已完成（见下方并行基准） |
| v0.6 ✅ | 工作区规则体检（快照保留/残留目录/空 temp）+ DirBucket 并行 | 已完成（见下方基准与体检） |
| v0.7 ✅ | 代码覆盖率门禁（Pester 3.4 -CodeCoverage，阈值可配）+ lint 分级/批准动词/命名检查 | 已完成（见下方质量门禁） |
| v0.8 ✅ | 打包 zip + SHA256、CLI `-DryRun` 全局演练、计划任务安装脚本 | 已完成（见下方交付与运维） |
| v1.0 ✅ | 命令补全（`ArgumentCompleter`）、脚本帮助、`-Version` | 已完成（v1.0.0 收尾） |


## 性能基准（v0.3 实测）

同一目录 `D:\1Work\项目`（29,952 文件 / 2.32 GB）对比三种实现：

| 实现 | 耗时 | 速率 | 说明 |
|---|---|---|---|
| v0.2 旧实现（逐文件 class + `-ErrorVariable`） | **47.9 s** | ~625 files/s | 基线（v0.2 实测） |
| v0.3 默认（`EnumerateFiles` + 聚合重写） | **3.34 s** | ~8,969 files/s | 约 **14x** 提速 |
| v0.3 `-LegacyEnumerator`（只换回枚举器） | 4.96 s | ~6,039 files/s | 枚举器单项贡献约 1.5x |

> 结论：大头来自"别再逐文件建对象/别再开 `-ErrorVariable`"，枚举器升级是第二层优化。
> 日常默认排除 `.venv` 后，`D:\1Work\项目` 只剩 3,391 文件 / 979 MB，v0.3 扫描 **1.27 s**（旧实现 2.93 s，2.3x）。

## 并行与扫描基准（v0.5 / v0.6 实测）

`D:\1Work\项目` 四种模式对比（ThrottleLimit=8）：

包含 `.venv`（29,937 文件 / 2.32 GB）：

| 模式 | 耗时 | 加速比 |
|---|---|---|
| 串行（默认） | 4.46 s | 1.00x |
| **DirBucket（目录分桶）** | **2.11 s** | **2.11x** |
| Subtree（子树） | 3.30 s | 1.35x |
| Chunk（只并行聚合） | 3.96 s | 1.12x |

排除 `.venv`（3,376 文件）：DirBucket **2.66x**、Subtree 1.19x、Chunk 1.06x。

结论与踩坑：
- 第一版 DirBucket 反而只有 0.34x——BFS 用逐目录 `Get-ChildItem`（几千次 cmdlet）＋ 每文件建记录对象；
  改成 .NET `EnumerateDirectories` 剪枝 + 每桶只维护有界 TopN 后 → 2.1–2.7x
- Chunk 模式受串行枚举限制（Amdahl）；Subtree 受"单棵大树"负载不均限制
- 并行模式默认 `DirBucket`；小目录（<1k 文件）时并行启动开销可能吃掉收益，按需选择


## 兼容性与最低标准（v1.4）

| 维度 | 最低标准 | 说明 |
|---|---|---|
| 操作系统 | Windows 10 22H2（19045）/ Windows 11，x64 | .NET 10 支持范围；Win7/8.1 不支持 |
| .NET 运行时 | **self-contained 包：无需安装**；框架依赖包：.NET 10 Desktop Runtime 10.0.x | 优先分发 self-contained |
| PowerShell | **PowerShell 7（必需）** | GUI 通过 pwsh 调用桥接脚本；启动时自动检测并引导安装 |
| 架构 | x64（ARM64 需单独 publish） | |
| 权限 | 普通用户（asInvoker），无需管理员 | |
| 签名 | Authenticode SHA256；对外建议 CA OV 证书 + RFC3161 时间戳 | 当前自签名（内部可用） |

- 自包含发布：`cd gui; .\publish-selfcontained.ps1` → `dist-selfcontained\WsDoctorGui.exe`（154 MB 目录，免 .NET）
- 环境检查：`.\WsDoctorGui.exe --check-env`（日志：`%TEMP%\wsdoctor-gui\check-env.log`）

## 代码签名（开源免费路线：SignPath Foundation）

**Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).**

- 申请与接入清单：[SIGNPATH-APPLICATION.md](SIGNPATH-APPLICATION.md)
- 签名工作流：`.github/workflows/release-signed.yml`；artifact 配置：`signpath/artifact-configuration.xml`
- 本地自签名（开发用）：`gui\sign-exe.ps1`；正式发布由 SignPath HSM 签名（Status=Valid）

## 代码签名发布（v1.3·自签名，开发用）

GUI 可执行文件使用自签名代码签名证书（SHA256 Authenticode）签名：

```powershell
cd gui
.\build-exe.ps1              # 构建
.\sign-exe.ps1               # 签名 dist-exe\WsDoctorGui.exe 与 .dll
.\sign-exe.ps1 -NewCertificate  # 重新生成证书（会换指纹）
```

- 发布包内附公钥证书 `WsDoctorGui-CodeSigning.cer`
- 校验：`Get-AuthenticodeSignature .\WsDoctorGui.exe`（未安装信任前 Status=UnknownError 属正常）
- 信任（可选，需普通终端）：`Import-Certificate -FilePath .\WsDoctorGui-CodeSigning.cer -CertStoreLocation Cert:\CurrentUser\TrustedPeople`
- ⚠️ 自签名不会消除 SmartScreen「未知发布者」提示；正式对外分发需购买 CA 代码签名证书（OV/EV）替换本流程

## 重复文件检测性能（v1.2 实测）

`D:\1Work`（17.59 GB 候选：3,635 个文件若全量哈希需要读 17.59 GB）：

| 实现 | 耗时 | 说明 |
|---|---|---|
| v1.1（剪枝前 + 全量 SHA256） | **203.9 s** | 枚举会遍历排除目录 + 所有候选全量哈希 |
| v1.2 两阶段哈希 | **5.6 s（热缓存）/ 40 s（冷缓存）** | 先取样 64KB（约 124 MB）过滤，仅对"大小+前缀"相同的 897 个文件做全量校验（约 442 MB） |
| 枚举剪枝 | **1.8 s**（原 68.7 s） | 直接跳过 `.dsh-snapshots`/`.venv` 等排除目录，不再遍历 13 万+ 文件 |

- 自动策略：小目录两阶段无收益时自动退化为全量哈希（`D:\1Work\项目` 1.6 s）
- GUI 体验：点「重复文件」先估算（约 2 s，读盘 124 MB 级的取样统计不读内容），弹窗显示"预计约 X 秒，是否继续"，用户可选择取消
## 工作区规则体检（v0.6）

`pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Audit

# 门禁：lint + Pester + 代码覆盖率（阈值默认 60，低于则失败）
pwsh -NoProfile -File .\build.ps1 -Coverage -MinCoverage 70

# 打包发布（zip + SHA256 校验和；-WhatIf 只预览文件清单）
pwsh -NoProfile -File .\pack.ps1

# 注册「每周体检」计划任务（实际注册要在本机普通终端执行）
powershell -File .\install\Register-WsDoctorTask.ps1 -Path D:\1Work -DayOfWeek Saturday -Time 09:00
# 删除计划任务：加 -Unregister`

- 规则来自配置 `workspace` 节：`snapshotKeep`（快照保留数）、`residuePatterns`（残留目录名正则）
- 输出 `WsFinding[]`：Severity / Category / Target / Message / Action；也可在脚本里 `Invoke-WsWorkspaceAudit`
- 真实运行示例：在 `D:\1Work` 命中 3 条「疑似残留」（`2287723691`、`nt_qq`、`All Users`）

## 质量门禁（v0.7）

```powershell
pwsh -NoProfile -File .\build.ps1                  # lint + 41 个测试
pwsh -NoProfile -File .\build.ps1 -Coverage -MinCoverage 70

# 打包发布（zip + SHA256 校验和；-WhatIf 只预览文件清单）
pwsh -NoProfile -File .\pack.ps1

# 注册「每周体检」计划任务（实际注册要在本机普通终端执行）
powershell -File .\install\Register-WsDoctorTask.ps1 -Path D:\1Work -DayOfWeek Saturday -Time 09:00
# 删除计划任务：加 -Unregister   # 再加代码覆盖率门禁
```

| 门禁 | 当前状态 |
|---|---|
| AST lint（Error 失败 / Warn 提示） | **0 error / 0 warn**（禁用别名、模块禁 Write-Host、批准动词、导出函数 CmdletBinding+OutputType、参数 PascalCase、函数长度 ≤150 行、模块禁绝对路径字面量） |
| Pester 测试 | **41 个用例全通过** |
| 代码覆盖率 | **70.98%**（609/858 条命令），低于 `-MinCoverage` 直接失败；未覆盖明细写入 `coverage-missed.txt` |

> 本机 PSGallery 不可达，Pester 仍为 3.4；其 `-CodeCoverage` 在 PS 7 上可用（无 `-Show` 参数）。
> 覆盖率提升策略：先覆盖"分支逻辑"（配置校验/错误路径/单位换算），再补并发等价性用例；只追数字会写一堆无意义断言。

## 交付与运维（v0.8）

```powershell
pwsh -NoProfile -File .\pack.ps1                 # 输出 dist\wsdoctor-<version>.zip + .sha256
pwsh -NoProfile -File .\pack.ps1 -WhatIf         # 只预览打包清单（不落盘）

# 周体检计划任务（Windows；实际注册需在本机普通终端跑，沙箱会拦截 CIM）
powershell -File .\install\Register-WsDoctorTask.ps1 -Path D:\1Work -DayOfWeek Saturday -Time 09:00
powershell -File .\install\Register-WsDoctorTask.ps1 -Path D:\1Work -Unregister   # 删除

# CLI 全局演练：所有写盘/删除动作走预览
pwsh -NoProfile -File .\wsdoctor.ps1 -Path D:\1Work -Audit -CleanEmptyDirs -DryRun
```

- `-DryRun` 等价于全局 `-WhatIf`：清理/报告导出/审计都只预览，不删除不写文件
- 打包内容：模块 + 三个脚本 + config/formats + bench/tests/docs/install；`dist/` 已 gitignore
- 发布包附带 SHA256 校验和，便于分发后校验完整性
- 计划任务以当前用户、RunLevel Limited 运行 `wsdoctor.ps1 -Path <工作区> -Audit`；`-WhatIf` 可先预览


## 前端 GUI（v1.1 新增，C# WinForms）

`gui\` 下是用 **C# 写的桌面交互窗口**（PowerShell 7 自带 Roslyn 编译，无需 .NET SDK）：

```powershell
cd .\gui
.\run.cmd                    # 或 pwsh -STA -File .\run.ps1
```

- 功能：选目录、扫描/重复/清理/体检/导出报告五类动作、Top/并行模式/DryRun/输出目录选项、
  概览统计卡 + 目录/大文件/重复/体检/清理/报告表格、彩色日志、双击打开位置、拖拽目录、F5–F9 快捷键、取消运行
- 架构：C# WinForms `WsDoctorGui.dll`（Roslyn 编译）→ 启动 `bridge.ps1` 子进程调用 WsDoctor 模块 → 结果 JSON 回读
- 验证：C# 自检 73 项断言、桥接集成测试 6 项、离屏截图回归
- 构建独立 exe（.NET SDK，离线）：`cd gui; .\build-exe.ps1` → `dist-exe\WsDoctorGui.exe`（约 296 KB，依赖已安装的 .NET 10 Desktop Runtime）
- 重复检测前会先估算耗时并弹窗确认（枚举剪枝 + 两阶段取样哈希；实测 D:\1Work 全量 203.9s → **5.6s（热缓存）/ 40s（冷缓存）**）
- 详情与 **C# 知识点地图**：[gui/README.md](gui/README.md)

![GUI 截图](gui/screenshot.png)

## 帮助与 Tab 补全（v1.0）

```powershell
Get-Help .\wsdoctor.ps1 -Detailed          # 脚本自带 comment-based help
.\wsdoctor.ps1 -Version                    # WsDoctor 1.0.0

# Tab 补全（参数值都带 ArgumentCompleter）：
.\wsdoctor.ps1 -Path <TAB>                 # 目录补全
.\wsdoctor.ps1 -ConfigPath <TAB>           # 文件补全
.\wsdoctor.ps1 -OutDir <TAB>               # 目录补全
.\wsdoctor.ps1 -ParallelMode <TAB>         # DirBucket / Subtree / Chunk
.\wsdoctor.ps1 -Format <TAB>               # Json / Csv / Html / All
```

## 项目状态（v1.0.0 完成）

| 维度 | 状态 |
|---|---|
| 功能 | 扫描（串行 / DirBucket 2.1–2.7x / Subtree / Chunk）、重复文件、空目录清理、规则体检、JSON/CSV/HTML 报告 |
| 质量 | lint 0 error/0 warn、Pester **47** 用例、覆盖率 **70.98%**（≥70% 门禁） |
| 交付 | `pack.ps1` 打包 zip + SHA256、`-DryRun` 演练、计划任务周体检 |
| 易用 | 帮助文档、Tab 补全、`-Version`、配置三层合并 |
| 未做 | `SecretManagement` 凭据管理、PSGallery 发布（当前场景不需要，留作扩展） |
## License

MIT
