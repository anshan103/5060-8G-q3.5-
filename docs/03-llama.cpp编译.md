# 03 · Windows 上从零编译 llama.cpp（含无管理员权限的应对）

这台机器的初始状态是 **没有 MSVC、没有 CMake、没有 Ninja、没有 CUDA、没有 Git**。
下面是把它变成"能编译 llama.cpp"的完整过程，包含每一步的实际耗时和踩到的坑。

---

## 一、总览

| 步骤 | 下载量 | 实际耗时 | 需要管理员 |
|---|---|---|---|
| 1. 装 VS BuildTools（含 CMake + Ninja） | ~2.5 GB | 十几分钟（看网速） | **是（UAC 一次）** |
| 2. 装便携 MinGit | 38 MB | 30 秒 | 否 |
| 3. 克隆源码 | 67 MB | 2~5 分钟 | 否 |
| 4. 配置 + 编译 | — | **配置 8 秒 + 编译 90 秒** | 否 |

编译 326 个目标只用了 90 秒（16 线程），比预期快得多。

---

## 二、装 MSVC（唯一需要 UAC 的一步）

下载引导器（4.3 MB）：

```powershell
curl.exe -sSL -o vs_BuildTools.exe https://aka.ms/vs/17/release/vs_BuildTools.exe
```

静默安装，**带上 CMake 组件**，这样不用另外下 CMake：

```powershell
Start-Process -FilePath .\vs_BuildTools.exe -Wait -ArgumentList @(
  '--quiet','--wait','--norestart','--nocache',
  '--add','Microsoft.VisualStudio.Workload.VCTools',
  '--add','Microsoft.VisualStudio.Component.VC.CMake.Project',
  '--includeRecommended'
)
```

> **坑**：`--quiet` 不会跳过 UAC，屏幕上仍会弹授权框，必须点「是」。
> 如果没有点，进程会一直挂着，而且不会有任何报错。

装好后验证：

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' `
    -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
```

应该输出 `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`。

**VS 自带的东西**（不用另外装）：

```
CMake : ...\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe   (3.31.6)
Ninja : ...\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe
MSVC  : ...\BuildTools\VC\Tools\MSVC\14.44.35207
```

---

## 三、装便携 Git（不需要管理员）

GitHub 直连不通，`git-scm.com` 的下载也会跳到 GitHub。可用 **npmmirror**：

```powershell
curl.exe -sSL -o mingit.zip `
  https://registry.npmmirror.com/-/binary/git-for-windows/v2.56.0.windows.2/MinGit-2.56.0.2-64-bit.zip
Expand-Archive mingit.zip -DestinationPath D:\ninfer\tools\git -Force
```

验证：`D:\ninfer\tools\git\cmd\git.exe --version`

---

## 四、克隆源码（三个坑）

源码来自 `PrismML-Eng/llama.cpp`。GitHub 直连不通，用 HF 上的镜像：

```powershell
git clone --depth 1 https://hf-mirror.com/OpenTransformer/llama.cpp-prismml
```

### 坑 1：`--filter=blob:none` 会失败

```
error: RPC failed; HTTP 500
fatal: could not fetch ... from promisor remote
```

镜像不支持按需拉 blob。**去掉 `--filter`**，直接 `--depth 1`。

### 坑 2：git-lfs 会卡住

仓库里 `docs/**.jpg` 是 LFS 对象，MinGit 不带 `git-lfs`：

```
git-lfs filter-process: line 1: git-lfs: command not found
fatal: docs/android/imported-into-android-studio.jpg: smudge filter lfs failed
warning: Clone succeeded, but checkout failed.
```

解决：克隆时把 LFS filter 全部禁用（我们不需要那些图片）：

```powershell
git -c filter.lfs.smudge= -c filter.lfs.required=false -c filter.lfs.process= `
    -c http.postBuffer=524288000 clone --depth 1 <url> <dir>
```

### 坑 3：`http.postBuffer`

大 pack 传输容易断，加 `-c http.postBuffer=524288000` 稳妥些。

克隆完应该是 **67 MB**，顶层能看到 `CMakeLists.txt` / `ggml/` / `src/` / `common/` / `include/`。

---

## 五、配置与编译

`scripts/build-llama-cpp-cpu.bat` 就是完整脚本，核心三行：

```bat
call "...\VC\Auxiliary\Build\vcvars64.bat"
cmake -S . -B build-cpu -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=OFF -DGGML_NATIVE=ON -DLLAMA_BUILD_TESTS=OFF
cmake --build build-cpu -j 16
```

说明：

- **必须先 `vcvars64.bat`**，否则 CMake 找不到编译器
- `-DGGML_NATIVE=ON` 让编译器按本机 CPU 生成指令（Ryzen 9 9955HX 支持 AVX-512）
- `-DGGML_CUDA=OFF` 是我们当时的选择：为了赶时间，且没装 CUDA Toolkit。
  想用 GPU 就装 CUDA Toolkit 后改成 `ON`
- `-DLLAMA_BUILD_TESTS=OFF` 能省掉一堆测试目标

产物在 `build-cpu\bin\`，`llama-cli.exe`、`llama-server.exe` 等 40 多个可执行文件。

---

## 六、跑一次

```bat
llama-cli.exe -m model.gguf -p "17+25=?" -n 32 -t 16 --no-warmup
```

### 坑 4：Start-Process 会把带空格的 prompt 拆开

```powershell
# 错误写法 → error: invalid argument: is
Start-Process llama-cli.exe -ArgumentList @('-p','What is 17 + 25?')
```

PowerShell 的 `-ArgumentList` 是拼接字符串，不加引号就会被拆成多个参数。
最省事的办法：**prompt 里不要空格**，或者写成 `.bat` 文件。

### 实测输出

```
> 17+25=?
17 + 25 = 42

[ Prompt: 8.2 t/s | Generation: 14.1 t/s ]
llama_memory_breakdown_print: | Host | 11542 = 2014 + 9216 + 312 |
```

**纯 CPU、16 线程、8B 三元模型：生成 14.1 tok/s，prefill 8.2 tok/s。**

---

## 七、如果之后要编 CUDA 版

1. 装 CUDA Toolkit **13.1+**（`sm_120a` 的硬要求，12.x 会错误编译）
2. `-DGGML_CUDA=ON`，并把 `CUDACXX` 指向 `nvcc.exe`
3. 编译时间会显著变长（CUDA 的 PTX 生成很慢）
4. 运行时需要 `cudart64_13.dll` 等在 PATH 里

本机没有实测 CUDA 版，这条路径未验证。

---

## 八、时间线参考

```
17:27 开始下载 vs_BuildTools（4.3 MB）
17:35 用户点 UAC，安装开始
17:47 安装完成，vswhere 能查到路径
17:52 MinGit 下好并解压
17:55 源码克隆成功（67 MB）
17:57 配置 8 秒
17:59 编译完成（326 目标，90 秒）
18:35 8B 三元模型跑出 42
```

从"什么都没有"到"跑出结果"，**约 1 小时 10 分钟**，其中大部分时间花在下载 VS 上。
