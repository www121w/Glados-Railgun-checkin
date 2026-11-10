# 从上游 Devilstore/Glados-Railgun-checkin 同步更新，同时保留我们加的邮件通知功能
#
# 用法：
#   .\sync-upstream.ps1            # 只检查有无更新，不动代码
#   .\sync-upstream.ps1 -Apply     # 检查并实际合并
#
# 原理：上游是原版（没有 EmailBackend），我们在此基础上加了 +79 行邮件代码。
# 直接 merge 会在 checkin.py 冲突。脚本合并后会逐项检查邮件功能是否还在。

param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
Push-Location $repo
try {
    Write-Host "=== 1. 拉取上游 ===" -ForegroundColor Cyan
    git fetch upstream --quiet
    if ($LASTEXITCODE -ne 0) { throw "fetch 失败，检查 upstream remote 和网络" }

    $behind = [int](git rev-list --count HEAD..upstream/master)
    Write-Host "上游新提交数：$behind"

    if ($behind -eq 0) {
        Write-Host "已是最新，无需同步。" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "=== 2. 上游新增的提交 ===" -ForegroundColor Cyan
    git log --oneline --no-decorate HEAD..upstream/master

    if (-not $Apply) {
        Write-Host ""
        Write-Host "仅预览模式。确认要合并请加 -Apply 参数。" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "=== 3. 备份当前分支 ===" -ForegroundColor Cyan
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "backup-before-sync-$stamp"
    git branch $backup
    Write-Host "已创建备份分支：$backup  （出问题可 git checkout $backup）"

    Write-Host ""
    Write-Host "=== 4. 合并上游 ===" -ForegroundColor Cyan
    git merge upstream/master --no-edit
    $mergeOk = ($LASTEXITCODE -eq 0)

    if (-not $mergeOk) {
        Write-Host ""
        Write-Host "出现冲突。checkin.py 的冲突需要保留我们的邮件功能：" -ForegroundColor Yellow
        Write-Host "  冲突文件用 git status 查看。解决原则："
        Write-Host "    · EmailBackend 类             —— 必须保留（我们加的）"
        Write-Host "    · Config._load_email()        —— 必须保留"
        Write-Host "    · PushService 里的 Email 注册  —— 必须保留"
        Write-Host "    · Config 里的 6 个 ENV_EMAIL_* —— 必须保留"
        Write-Host "    · EmailBackend._render()      —— 必须保留（压平双空格）"
        Write-Host "    · 其余部分                     —— 取上游新版"
        Write-Host ""
        Write-Host "  解决后：git add checkin.py .github/workflows/gladosCheck.yml"
        Write-Host "          git commit"
        Write-Host "          git push origin master"
        Write-Host "  想放弃：git merge --abort"
        return
    }

    Write-Host ""
    Write-Host "=== 5. 验证邮件功能还在 ===" -ForegroundColor Cyan
    $needles = @(
        @{ n = 'EmailBackend 类';        p = 'class EmailBackend' },
        @{ n = '_load_email 方法';       p = 'def _load_email' },
        @{ n = 'PushService 注册';       p = 'self.backends.append\(EmailBackend' },
        @{ n = '邮件正文压平';           p = 're\.sub\(r" \{2,\}"' }
    )
    $missing = @()
    foreach ($x in $needles) {
        if (Select-String -Path "$repo\checkin.py" -Pattern $x.p -Quiet) {
            Write-Host "  [OK] $($x.n)" -ForegroundColor Green
        } else {
            Write-Host "  [缺失] $($x.n)" -ForegroundColor Red
            $missing += $x.n
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "警告：合并后邮件功能缺失，请不要推送。" -ForegroundColor Red
        Write-Host "用 git reset --hard $backup 回退。" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "合并成功，邮件功能完整。" -ForegroundColor Green
    Write-Host "下一步：git push origin master" -ForegroundColor Yellow
}
finally {
    Pop-Location
}
