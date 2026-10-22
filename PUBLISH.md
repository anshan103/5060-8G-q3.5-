# 怎么发布到 GitHub

这份仓库已经在本机初始化好 git（`D:\ninfer\share`，已有一次提交），
内容完整、无敏感信息。因为这台机器连不上 `github.com`，推送需要你来执行。

---

## 方式一：用 git 推送（推荐，保留提交历史）

本机已有便携 git：

```powershell
$git = 'D:\ninfer\tools\git\cmd\git.exe'

# 1. 先在 GitHub 网页上建一个空仓库（不要勾 README / .gitignore / license）
# 2. 进入本地仓库
cd D:\ninfer\share

# 3. 指到你自己的仓库
& $git remote add origin https://github.com/<你的用户名>/<仓库名>.git
& $git branch -M main

# 4. 推送（会提示输入用户名和 Personal Access Token）
& $git push -u origin main
```

> GitHub 现在不接受密码推送，要用 **Personal Access Token**：
> Settings → Developer settings → Personal access tokens → Generate new token（勾 `repo` 权限）。

---

## 方式二：网页上传（不用装 git）

1. GitHub 网页建一个空仓库
2. 点 **uploading an existing file**
3. 把 `D:\ninfer\share` 里的**全部文件和文件夹**拖进去（注意要包括 `docs/`、`scripts/`、`logs/` 三个目录）
4. Commit

> 不要直接传 `ternary-27b-on-8gb-notes.zip`——GitHub 不会自动解压，
> 别人点进去只会看到一个 zip。

---

## 方式三：先解压再传

`D:\ninfer\ternary-27b-on-8gb-notes.zip` 是完整归档（37.8 KB），
解压到任意目录后按方式二上传。

---

## 推送前建议再确认一次

```powershell
# 检查有没有漏进来的个人信息
Select-String -Path (Get-ChildItem D:\ninfer\share -Recurse -File) `
  -Pattern 'Users\\\w+|LAPTOP-|sk-[A-Za-z0-9]{20}' -ErrorAction SilentlyContinue
```

当前版本已扫描过：无用户名、无机器名、无密钥。

---

## 建议的仓库设置

- **描述**：`在 8GB 笔记本显卡上跑 27B 三元量化模型的完整踩坑与复现记录`
- **Topics**：`llama.cpp` `ternary-quantization` `nvidia` `windows` `niner` `gguf` `low-vram`
- **License**：文档 CC BY 4.0 / 脚本 MIT（见仓库内 `LICENSE`）

---

## 如果之后想加内容

这份记录最容易继续补充的是：

- **CUDA 版 llama.cpp 的编译实测**（本机只编了 CPU 版）
- **PrismML fork 真身拿到后，27B PTQ1_0 在 llama.cpp 上的速度**
- **其他显卡的对照数据**（12 GB / 16 GB 卡跑同样的模型会舒服很多）

欢迎提 issue 补充你的实测数据。
