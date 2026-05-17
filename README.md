# SSH Mobile — 手机远程操作 Windows Claude Code

Tailscale + OpenSSH + Termius 一键配置脚本。配置完成后，手机随时随地 SSH 到电脑操作 Claude Code。

## 一键安装

```powershell
git clone https://github.com/therain2020/ssh-mobile-workflow.git
cd ssh-mobile-workflow
# 右键 PowerShell → 以管理员身份运行
.\setup.ps1
```

脚本支持断点续跑，已完成的步骤自动跳过。

## 手动步骤

以下两步需要人工操作：

1. **Tailscale 登录**：https://tailscale.com/download/windows 下载 → 任务栏图标 → Sign in
2. **手机装 App**：Termius + Tailscale，用同一账号登录

## 手机连接

Termius 新建连接：

| 字段 | 值 |
|------|-----|
| Host | 电脑的 Tailscale IP |
| Port | 22 |
| Username | gitops |
| Password | 安装时设的密码 |

## 状态检查

```powershell
.\setup.ps1 -Status
```

## 常见问题

```powershell
.\setup.ps1 -Troubleshoot
```

## 踩坑合集

- **C:\ 或 D:\ 根目录 DENY → mvn 拒绝访问**：Windows 对根目录的 DENY 处理特殊，影响子进程。不要 DENY 根目录。
- **Oracle javapath 排前面 → java 无输出**：从系统 PATH 删掉 Oracle 路径。
- **Tailscale Sign in 没反应**：关掉系统代理再点。
