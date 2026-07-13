# roothide-procursus-backup

苏苏自用 APT 源仓库。

## 结构

```text
debs/                 # 所有 .deb 平铺，禁止子目录
Packages
Packages.gz
Packages.bz2
Release
CydiaIcon.png
scripts/
  sync_pool_debs.sh   # 从 SuSuDear/roothide.github.io 的 1900 全量拉 deb
  generate_packages.sh
  commit_and_push.sh
.github/workflows/update_apt_repo.yml
```

## 源地址（发行版）

```text
URL: https://susudear.github.io/roothide-procursus-backup/
Suites: ./
Components:
```

## GitHub Actions

工作流 `Update APT Repo` 会：

1. 拉取  
   `SuSuDear/roothide.github.io/procursus/pool/main/iphoneos-arm64e/1900/**`  
   下**全部** `.deb`（不只是 llvm）
2. **平铺**保存到 `debs/`  
   例如：`debs/swift_5.7.2~RELEASE_iphoneos-arm64e.deb`  
   **不会**出现 `debs/llvm/...` 或 `debs/bash/...`
3. 生成 `Packages` / `Packages.gz` / `Packages.bz2`
4. 更新 `Release` 校验和并 push（`*.deb` 走 Git LFS）

手动触发：GitHub → Actions → Update APT Repo → Run workflow

## 本地生成

```bash
./scripts/sync_pool_debs.sh
./scripts/generate_packages.sh
```

## 大文件说明（Git LFS）

GitHub 普通文件上限 100MB。大 deb 通过 **Git LFS** 存储。
