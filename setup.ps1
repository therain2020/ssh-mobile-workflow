# SSH Mobile 一键配置脚本
# 必须以管理员身份运行
# 用法: .\setup.ps1

param(
    [switch]$Status,
    [switch]$Troubleshoot
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "SSH Mobile Setup"

# ============================================================
# 配置变量（改这里适配你的环境）
# ============================================================
$GITOPS_PASSWORD = ""        # gitops 用户密码（留空则交互输入）
$DB_PASSWORD     = ""        # MySQL 密码
$DASHSCOPE_KEY   = ""        # DashScope API Key
$ANTHROPIC_KEY   = ""        # Anthropic/DeepSeek API Key
$MAIN_USER       = $env:USERNAME  # 当前主用户
$MAVEN_HOME      = "D:\Maven\apache-maven-3.9.9"
$JAVA_HOME       = "D:\developer\Java\jdk-21"
$NODEJS_HOME     = "D:\developer\nodejs"
$CLAUDE_BIN      = "C:\Users\$MAIN_USER\.local\bin"

# ============================================================
# 工具函数
# ============================================================
function Write-Step { Write-Host "`n>>> $args" -ForegroundColor Cyan }
function Write-OK    { Write-Host "  OK: $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "  WARN: $args" -ForegroundColor Yellow }
function Write-Fail  { Write-Host "  FAIL: $args" -ForegroundColor Red }
function Write-Info  { Write-Host "  INFO: $args" -ForegroundColor Gray }

function Test-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Fail "此脚本必须以管理员身份运行。右键 PowerShell → 以管理员身份运行，然后重新执行。"
        exit 1
    }
}

function Invoke-Step($Name, $ScriptBlock) {
    Write-Step $Name
    try { & $ScriptBlock; Write-OK $Name; return $true }
    catch { Write-Fail "$Name : $_"; return $false }
}

# ============================================================
# 状态检查
# ============================================================
function Show-Status {
    Write-Host "`n======== SSH Mobile 状态检查 ========" -ForegroundColor Cyan

    # Tailscale
    $ts = Get-Process "tailscale*" -ErrorAction SilentlyContinue
    if ($ts) {
        try { $ip = & "C:\Program Files\Tailscale\tailscale.exe" ip -4 2>$null; Write-OK "Tailscale: Running (IP: $ip)" }
        catch { Write-OK "Tailscale: Running" }
    } else { Write-Fail "Tailscale: 未运行" }

    # sshd
    $sshd = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshd -and $sshd.Status -eq "Running") { Write-OK "sshd: Running (Port 22)" }
    else { Write-Fail "sshd: 未运行或未安装" }

    # gitops 用户
    $gitops = Get-LocalUser -Name "gitops" -ErrorAction SilentlyContinue
    if ($gitops) { Write-OK "gitops 用户: 已创建" }
    else { Write-Fail "gitops 用户: 未创建" }

    # 环境变量
    foreach ($v in @("JAVA_HOME","MAVEN_HOME","ANTHROPIC_AUTH_TOKEN")) {
        $val = [Environment]::GetEnvironmentVariable($v, "Machine")
        if ($val) { Write-OK "$v = $val" }
        else { Write-Fail "$v: 未设置" }
    }

    # Dev 工具
    foreach ($tool in @("java","mvn","node","pnpm")) {
        try { $null = Get-Command $tool -ErrorAction Stop; Write-OK "$tool: 可用" }
        catch { Write-Fail "$tool: 不可用" }
    }

    # 符号链接
    $link = Get-Item "C:\Users\gitops\.claude" -ErrorAction SilentlyContinue
    if ($link -and $link.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-OK ".claude symlink: gitops → $MAIN_USER"
    } else { Write-Warn ".claude symlink: 未创建" }
}

if ($Status) { Show-Status; return }

# ============================================================
# 交互式排查
# ============================================================
if ($Troubleshoot) {
    Show-Status
    Write-Host "`n常见问题：" -ForegroundColor Yellow
    Write-Host "  1. mvn 拒绝访问 → 检查 C:\ 和 D:\ 根目录是否有 DENY，运行: icacls C:\ /remove:d gitops"
    Write-Host "  2. java 无输出 → 检查 PATH 中 Oracle javapath 是否排在 JDK 前面"
    Write-Host "  3. mvn 下载依赖失败 → 检查 C:\Users\gitops\.m2\settings.xml 代理配置"
    Write-Host "  4. 手机连不上 → 检查 Tailscale 双方在线，防火墙 22 端口放行"
    return
}

# ============================================================
# 主安装流程
# ============================================================
Clear-Host
Write-Host @"
╔══════════════════════════════════════╗
║   SSH Mobile 一键配置               ║
║   Windows → Tailscale → 手机 Claude ║
╚══════════════════════════════════════╝
"@ -ForegroundColor Cyan

Test-Admin
Show-Status

Write-Warn "脚本会修改系统配置。确认继续？(Ctrl+C 取消)"
pause

# ---- 1. OpenSSH Server ----
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $sshd) {
    Invoke-Step "安装 OpenSSH Server" {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }
}
if ((Get-Service sshd).Status -ne "Running") {
    Invoke-Step "启动 sshd" {
        Start-Service sshd
        Set-Service -Name sshd -StartupType 'Automatic'
    }
}

# 改默认 Shell 为 PowerShell
Invoke-Step "设置 SSH 默认 Shell 为 PowerShell" {
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -PropertyType String -Force -ErrorAction SilentlyContinue
    Restart-Service sshd
}

# ---- 2. gitops 用户 ----
$gitops = Get-LocalUser -Name "gitops" -ErrorAction SilentlyContinue
if (-not $gitops) {
    if (-not $GITOPS_PASSWORD) { $GITOPS_PASSWORD = Read-Host "为 gitops 设置密码" -AsSecureString }
    Invoke-Step "创建 gitops 用户" {
        $pwd = if ($GITOPS_PASSWORD -is [SecureString]) { $GITOPS_PASSWORD } else { ConvertTo-SecureString $GITOPS_PASSWORD -AsPlainText -Force }
        New-LocalUser -Name "gitops" -Password $pwd -FullName "Git SSH Operator" -PasswordNeverExpires
        Add-LocalGroupMember -Group "Users" -Member "gitops"
    }
}

# ---- 3. NTFS 权限 ----
Invoke-Step "配置 D:\GitHub 读写权限" {
    icacls "D:\GitHub" /grant "gitops:(OI)(CI)M" 2>$null
}
Invoke-Step "配置 .claude 读写权限" {
    icacls "C:\Users\$MAIN_USER\.claude" /grant "gitops:(OI)(CI)M" /T 2>$null
}
Invoke-Step "配置主目录穿透权限" {
    icacls "C:\Users\$MAIN_USER" /grant "gitops:(NP)(RX)" 2>$null
}
Invoke-Step "配置 .m2 只读权限" {
    if (Test-Path "C:\Users\$MAIN_USER\.m2") {
        icacls "C:\Users\$MAIN_USER\.m2" /grant "gitops:(OI)(CI)(RX)" /T 2>$null
    }
}
Invoke-Step "配置 dev 工具目录只读" {
    if (Test-Path $MAVEN_HOME) { icacls $MAVEN_HOME /grant "gitops:(OI)(CI)(RX)" /T 2>$null }
    if (Test-Path $JAVA_HOME)  { icacls $JAVA_HOME /grant "gitops:(OI)(CI)(RX)" /T 2>$null }
    if (Test-Path $NODEJS_HOME) { icacls $NODEJS_HOME /grant "gitops:(OI)(CI)(RX)" /T 2>$null }
}
Invoke-Step "配置 gitops 家目录完整权限" {
    if (Test-Path "C:\Users\gitops") {
        icacls "C:\Users\gitops" /grant "gitops:(OI)(CI)F" /T 2>$null
    }
}
# 精准 DENY 敏感目录
Invoke-Step "保护主用户敏感目录" {
    $dirs = @("Desktop","Documents","Downloads","Pictures","AppData")
    foreach ($d in $dirs) {
        icacls "C:\Users\$MAIN_USER\$d" /deny "gitops:(W)" 2>$null
    }
}

# ---- 4. 环境变量 ----
Invoke-Step "添加 dev 工具到系统 PATH" {
    $path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $append = @($MAVEN_HOME + "\bin", $NODEJS_HOME, $CLAUDE_BIN)
    # 移除 Oracle javapath
    $path = ($path -split ';' | Where-Object { $_ -notmatch 'Oracle.*javapath' }) -join ';'
    foreach ($p in $append) {
        if ($p -and $path -notmatch [regex]::Escape($p)) { $path += ";$p" }
    }
    [Environment]::SetEnvironmentVariable("Path", $path, "Machine")
}

Invoke-Step "设置系统环境变量" {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $JAVA_HOME, "Machine")
    [Environment]::SetEnvironmentVariable("MAVEN_HOME", $MAVEN_HOME, "Machine")
    if (-not $DB_PASSWORD) { $DB_PASSWORD = Read-Host "MySQL 数据库密码 (回车跳过)" }
    if ($DB_PASSWORD) { [Environment]::SetEnvironmentVariable("DB_password", $DB_PASSWORD, "Machine") }
    if (-not $DASHSCOPE_KEY) { $DASHSCOPE_KEY = Read-Host "DashScope API Key (回车跳过)" }
    if ($DASHSCOPE_KEY) { [Environment]::SetEnvironmentVariable("ALI_TONGYI_KEY", $DASHSCOPE_KEY, "Machine") }
    if (-not $ANTHROPIC_KEY) { $ANTHROPIC_KEY = Read-Host "Anthropic/DeepSeek API Token (回车跳过)" }
    if ($ANTHROPIC_KEY) { [Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $ANTHROPIC_KEY, "Machine") }
}

# ---- 5. Claude 符号链接 ----
Invoke-Step "创建 Claude 配置符号链接" {
    if (Test-Path "C:\Users\gitops\.claude") {
        Remove-Item "C:\Users\gitops\.claude" -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType SymbolicLink -Path "C:\Users\gitops\.claude" -Target "C:\Users\$MAIN_USER\.claude" -Force
}

# ---- 6. Maven 代理 ----
Invoke-Step "配置 Maven 代理 (Clash: 127.0.0.1:7890)" {
    $m2 = "C:\Users\gitops\.m2"
    if (-not (Test-Path $m2)) { New-Item -ItemType Directory -Path $m2 -Force }
    @"
<settings>
  <proxies>
    <proxy>
      <id>clash</id>
      <active>true</active>
      <protocol>http</protocol>
      <host>127.0.0.1</host>
      <port>7890</port>
      <nonProxyHosts>localhost</nonProxyHosts>
    </proxy>
  </proxies>
</settings>
"@ | Out-File -FilePath "$m2\settings.xml" -Encoding UTF8
}

# ---- 完成 ----
Restart-Service sshd
Write-Host "`n==============================" -ForegroundColor Green
Write-Host "  配置完成！" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
Write-Host "`n手机 Termius 连接信息："
Write-Host "  Host:     Tailscale IP (电脑端运行: tailscale ip -4)"
Write-Host "  Port:     22"
Write-Host "  Username: gitops"
Write-Host "  Password: 你刚设的密码"
Write-Host "`n连接后: cd D:\GitHub\<项目> && claude"
Show-Status
