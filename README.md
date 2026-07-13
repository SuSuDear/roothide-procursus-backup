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


## 重要：为什么会“大小应为 xx，获得了 130”？

因为 `*.deb` 使用了 **Git LFS**。

- GitHub Pages / `raw.githubusercontent.com` 返回的是 **LFS 指针文件**（大约 130 字节）
- 软件源记录的是真实 deb 大小（几 MB ~ 几百 MB）
- 所以 Sileo/apt 会报：文件大小应为 16049894，获得了 133

### 解决办法（已内置）

`Packages` 里的 `Filename` 改为绝对地址：

```text
https://media.githubusercontent.com/media/SuSuDear/roothide-procursus-backup/main/debs/xxx.deb
```

这个地址会返回真实 deb（`!<arch>`），而不是指针。

刷新软件源缓存后再安装。


## 安装失败“大小应为 xx，获得了 130”的根因与修复

根因：`*.deb` 曾用 **Git LFS** 存储。  
GitHub Pages / `susuboy.cn` **不会**返回 LFS 真实文件，只会返回约 130 字节指针。

### 正确托管方式（已切换）

- **<=100MB**：普通 Git 文件 + `Filename: ./debs/xxx.deb`（同域下载）
- **>100MB**：上传到 GitHub Release `debs-large`，`Filename` 用 Release 绝对地址

请重新跑一次 Actions：`Update APT Repo`，把仓库里的 LFS 指针替换成真实 deb。
