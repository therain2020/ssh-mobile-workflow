---
name: ssh-mobile
description: >
  SSH mobile development — Windows 11 host setup via Tailscale + OpenSSH for phone-based
  Claude Code access. Covers restricted user creation, NTFS permission hardening, dev tool
  PATH, Maven proxy, Claude config symlink, and troubleshooting. After setup, the phone
  can run /mobiledev or /module-audit anywhere with Tailscale connected.
install: >
  git clone https://github.com/therain2020/ssh-mobile-workflow.git;
  以管理员身份运行 setup.ps1，按提示完成配置
invoke: /ssh-mobile setup | status | troubleshoot <问题>
---

## 安装

```powershell
git clone https://github.com/therain2020/ssh-mobile-workflow.git
cd ssh-mobile-workflow
# 以管理员身份运行
.\setup.ps1
```

脚本会自动检测已完成的步骤，支持断点续跑。手动步骤会暂停等待确认。

## 使用

配置完成后，手机 Termius 连接，`cd D:\GitHub\<项目> && claude` 即可。

### Claude Code 中调用

```
/ssh-mobile setup        # 首次安装
/ssh-mobile status       # 检查各项服务状态
/ssh-mobile troubleshoot # 交互式排查
```

# SSH Mobile 远程开发工作流

手机通过 Termius（SSH）-> Tailscale（虚拟组网）-> 直连电脑 Claude Code 的完整搭建方案。

## 前置条件

- Windows 11 电脑（始终开机或随用随开）
- 手机（Android/iOS）已安装 Termius 和 Tailscale
- GitHub 账号（Tailscale 登录用）

---

## 第一步：Tailscale 组网（随时随地连）

### 电脑端
1. https://tailscale.com/download/windows 下载安装
2. 任务栏右下角 Tailscale 图标 → Sign in（同一账号）
3. 登录后获得 Tailscale IP（格式 `100.x.x.x`）

### 手机端
1. App Store / Google Play 安装 Tailscale
2. 用同一账号登录

### 遇坑：Windows 点 Sign in 没反应
- 症状：点 Sign in 无反应，Sign up 正常
- 高发原因：Clash/代理的 TUN 模式或系统代理干扰
- 解决：暂时关闭系统代理 → 登录 → 再开回
- 备选：`tailscale up --authkey=<admin-console-key>`

### 验证
```powershell
& "C:\Program Files\Tailscale\tailscale.exe" ip -4
# 输出 100.x.x.x 即成功
```

---

## 第二步：OpenSSH Server（电脑开门）

### 安装（二选一）

**方式A：GUI（推荐，快）**
设置 → 系统 → 可选功能 → 添加可选功能 → 搜 `OpenSSH Server` → 安装

**方式B：命令行（管理员）**
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

### 启动（管理员 PowerShell）
```powershell
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```

### 验证
```powershell
Get-Service sshd | Select-Object Name, Status
# Status: Running
```

---

## 第三步：创建受限用户 gitops

### 创建用户（管理员 PowerShell）
```powershell
$password = Read-Host "输入密码" -AsSecureString
New-LocalUser -Name "gitops" -Password $password -FullName "Git SSH Operator"
Add-LocalGroupMember -Group "Users" -Member "gitops"
```

### Termius 手机连接

| 字段 | 值 |
|------|-----|
| Host | 电脑的 Tailscale IP |
| Port | `22` |
| Username | `gitops` |
| Password | 你设的密码 |

### 首次连接
手机 Termius 会提示 `The authenticity of host can't be established`。
点 **Accept / Continue**，这是正常的安全确认。

### 改默认 Shell 为 PowerShell（管理员）
```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -PropertyType String -Force
Restart-Service sshd
```

---

## 第四步：NTFS 权限硬化

### 原则
- gitops 只能写 `D:\GitHub`、自己的家目录、Claude 全局配置
- **C:\ 和 D:\ 根目录不要设 DENY**——会导致 Maven/Java 启动时拒绝访问
- 精准在子目录层面控制

### 授予（管理员 PowerShell）
```powershell
# D:\GitHub 完整读写
icacls "D:\GitHub" /grant "gitops:(OI)(CI)M"

# Claude 全局配置（通过 symlink 共享，%USER% 换成你的主用户名）
icacls "C:\Users\%USER%\.claude" /grant "gitops:(OI)(CI)M" /T

# 允许穿透到 .claude
icacls "C:\Users\%USER%" /grant "gitops:(NP)(RX)"

# Maven 本地仓库只读
icacls "C:\Users\%USER%\.m2" /grant "gitops:(OI)(CI)(RX)" /T

# dev 工具目录只读
icacls "D:\Maven" /grant "gitops:(OI)(CI)(RX)" /T
icacls "D:\developer\Java" /grant "gitops:(OI)(CI)(RX)" /T
icacls "D:\developer\nodejs" /grant "gitops:(OI)(CI)(RX)" /T

# gitops 自己家目录完整读写
icacls "C:\Users\gitops" /grant "gitops:(OI)(CI)F" /T
```

### 精准 DENY 写入敏感位置（可选）
```powershell
icacls "C:\Users\%USER%\Desktop" /deny gitops:"(W)"
icacls "C:\Users\%USER%\Documents" /deny gitops:"(W)"
icacls "C:\Users\%USER%\AppData" /deny gitops:"(W)"
# 不要 DENY C:\ 或 D:\ 根目录！
```

---

## 第五步：开发工具环境变量

### 添加到系统 PATH（管理员 PowerShell）
```powershell
$path = [Environment]::GetEnvironmentVariable("Path", "Machine")
$path += ";D:\Maven\apache-maven-3.9.9\bin;D:\developer\nodejs;C:\Users\$env:USERNAME\.local\bin"
[Environment]::SetEnvironmentVariable("Path", $path, "Machine")
```

### 系统环境变量
```powershell
[Environment]::SetEnvironmentVariable("JAVA_HOME", "D:\developer\Java\jdk-21", "Machine")
[Environment]::SetEnvironmentVariable("MAVEN_HOME", "D:\Maven\apache-maven-3.9.9", "Machine")
[Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "<你的API Token>", "Machine")
[Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://api.deepseek.com/anthropic", "Machine")
[Environment]::SetEnvironmentVariable("DB_password", "<数据库密码>", "Machine")
[Environment]::SetEnvironmentVariable("ALI_TONGYI_KEY", "<DashScope Key>", "Machine")
```

### 注意
- 环境变量必须设在 `"Machine"` 作用域（系统变量），`"User"` 只有当前用户能看到
- 每次修改环境变量后要 `Restart-Service sshd`

---

## 第六步：共享 Claude Code 配置

### 符号链接（管理员 PowerShell）
```powershell
# 删除 gitops 的空 .claude（如果存在）
Remove-Item "C:\Users\gitops\.claude" -Recurse -Force -ErrorAction SilentlyContinue

# 创建符号链接（$env:USERNAME 会自动展开为当前主用户名）
New-Item -ItemType SymbolicLink -Path "C:\Users\gitops\.claude" -Target "C:\Users\$env:USERNAME\.claude"
```

### 原理
- 符号链接 = 路标，不是复制
- gitops 读写 `.claude` 都透明映射到主用户的原始数据
- 一个文件、两个门牌号，改一处两边都生效
- 包含：skills、settings.json、mcp.json、memory、CLAUDE.md（全局）

---

## 第七步：Maven 代理（如果用了 Clash）

```powershell
"<settings><proxies><proxy><id>clash</id><active>true</active><protocol>http</protocol><host>127.0.0.1</host><port>7890</port><nonProxyHosts>localhost</nonProxyHosts></proxy></proxies></settings>" | Out-File -FilePath "C:\Users\gitops\.m2\settings.xml" -Encoding UTF8
```

---

## 第八步：Git 配置

手机 Termius 连接后：
```powershell
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

### GitHub Push（需要另配 SSH Key 或 PAT）
```powershell
ssh-keygen -t ed25519 -C "your@email.com"
# 将公钥加入 GitHub Settings → SSH Keys
```

---

## 第九步：Redis（如需要外部连接）

Redis 默认只绑 `127.0.0.1`，改绑所有网卡：
```powershell
$conf = Get-Content "D:\Redis\redis.windows.conf" -Raw
$conf -replace 'bind 127.0.0.1', 'bind 0.0.0.0' | Set-Content "D:\Redis\redis.windows.conf"
Restart-Service Redis
```

---

## 踩坑记录

### 坑1：C:\ 或 D:\ 根目录 DENY(W) → `mvn` 拒绝访问
**症状**：`mvn -v` 输出 `拒绝访问*3` + 版本号
**原因**：Windows 对根目录 DENY 处理特殊，会影响 Java/JVM 的子进程
**解决**：`icacls C:\ /remove:d gitops` + `icacls D:\ /remove:d gitops`
**教训**：不要 DENY 根目录，精准 DENY 特定子目录

### 坑2：Oracle javapath 排在 JDK 前面
**症状**：`java -version` 无输出
**原因**：`C:\Program Files\Common Files\Oracle\Java\javapath\java.exe` 在 PATH 中排第一位，对非主用户不工作
**解决**：从系统 PATH 删除 Oracle javapath 路径

### 坑3：Tailscale Windows Sign in 没反应
**症状**：点 Sign in 无反应，Sign up 有反应
**原因**：Clash 系统代理拦截了浏览器弹窗
**解决**：关系统代理 → 登录 → 开代理。或用 `tailscale up --authkey=<key>`

### 坑4：Deny 不加 `(OI)(CI)` 看似不继承实则影响子目录
Windows 对根目录的特殊处理导致 DENY 即使没有继承标志也可能影响子目录的进程行为

---

## 日常使用

1. 电脑开机，Tailscale 自动连接
2. 手机开 Tailscale，Termius 一键连接
3. `cd D:\GitHub\<项目> && claude`
4. 可以运行 `/mobiledev` 或 `/module-audit`

## 手机端技能限制

| 操作 | 可用 | 备注 |
|------|:--:|------|
| git commit / log / diff | ✓ | |
| git push | ⚠️ | 需配 SSH Key |
| mvn compile / test | ✓ | 依赖代理下载 |
| pnpm dev / build / test | ✓ | |
| Claude Code 全功能 | ✓ | |
| browse（浏览器） | ✗ | SSH 无 GUI |
| gh CLI | ⚠️ | 需单独 `gh auth login` |
