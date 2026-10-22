# 在 8 GB 笔记本显卡上跑 27B 三元量化模型：一次完整的踩坑与复现记录

> 硬件：AMD Ryzen 9 9955HX / NVIDIA RTX 5060 Laptop 8 GB / 15.2 GB RAM / Windows 11 25H2 (build 26200)
> 软件：NInfer 0.11.0 sm_120a 引擎 + llama.cpp (PrismML fork)
> 日期：2026-10-21

---

## TL;DR

**能跑，但取决于你拿的是哪个模型文件。**

| 路线 | 模型 | 结果 |
|---|---|---|
| NInfer（GPU 全驻留） | `bonsai2_27b_ternary_ptq1_native_mtp.ninfer`（5.96 GB） | ✅ **decode 24.3 tok/s**，TTFT 236 ms |
| NInfer | `Ternary-Bonsai-2-27B-ninfer-v3.ninfer`（9.08 GB） | ❌ 权重 7.12 GiB，显存差 196 MiB |
| NInfer | `...-mtponly.ninfer`（7.13 GB） | ❌ 权重 6.70 GiB，仍差 196 MiB |
| llama.cpp（CPU） | `Ternary-Bonsai-8B-TQ2_0.gguf`（1.97 GiB） | ✅ 14.1 tok/s，答案正确 |
| llama.cpp | `Ternary-Bonsai-2-27B-PTQ1_0.gguf`（5.54 GiB） | ❌ 张量类型 143，镜像分支只到 41 |
| Ollama | 同上的 PTQ1_0 | ❌ `unsupported tensor "token_embd.weight" size overflows` |

**核心教训：同一代模型的不同"打包变体"体积差 3 GB，能不能装进 8 GB 全看选对了没。**

---

## 一、这台机器的硬边界

```
GPU   : RTX 5060 Laptop, 8,151 MiB, compute_cap 12.0 (sm_120), driver 617.14, CUDA UMD 13.4
CPU   : Ryzen 9 9955HX 16C/32T
RAM   : 15.2 GB
OS    : Windows 11 25H2 build 26200（注册表仍写 Windows 10 Home China，属已知显示问题）
```

8 GB 显存在 2026 年是"能装下 27B 三元，但一点余量都没有"的档位。扣除桌面占用 ~400 MiB，
引擎可用的显存窗口大约 7.2 GB。

---

## 二、最值得看的一节：196 MiB 的鸿沟是怎么来的

用完整版模型时，引擎日志长这样：

```
loading weights | 7.12 GiB
weights ready   | 7.12 GiB | 2.8s | 2.55 GiB/s
ERROR startup failed | finalizing target
FATAL server failed during startup | requested Engine runtime reservation
      requires 1863950080 bytes, but only 0 bytes are available for runtime capacity
```

换成 `mtponly` 变体：

```
loading weights | 6.70 GiB（去掉 MTP 头）
FATAL ... requires 335246592 bytes in addition to 67108864 bytes of automatic
      headroom, but only 192937984 bytes are available after weights
```

算账：

```
显存总量              8,151 MiB
三元 27B 权重        6,861 MiB   ← 已经是去掉投机头的版本
引擎固定预留        ~1,138 MiB   ← CUDA context + WDDM
────────────────────────────────
可分配给运行时         152 MiB
运行时最低需求         348 MiB
────────────────────────────────
固定缺口               196 MiB
```

**我试遍了所有能省的参数，全部无效**（详见 [docs/02](docs/02-NInfer部署与踩坑.md)）：

- KV 池 17920 → 8192 → 4096 → **1024**
- KV 精度 `k8v4` → `rk2v4-e8`（最省）
- `--prefill-chunk 128`、`--no-cuda-graph`
- `--kv-headroom-mib 64`（必须配 `--kv-capacity auto`）
- `--embedding-q4` / `--lm-head-q4`（模型不是 Q8_G32 存储，直接拒绝）
- `--wddm-evictable-budget`（该构建未编入 `NINFER_D3D12_RESIDENCY`）
- **关掉所有占卡程序**，把空闲显存从 7,349 MiB 提到 7,626 MiB
- 强制 `--device-profile calibrate` 重新校准

最后一项说明问题本质：**空闲显存 +277 MiB，引擎报告的"可用运行时预算"仍是 152 MiB，一个字节没变。**
它按卡型算固定预算，不看实时占用。

### 破局点

真正能跑的是第三个变体——**`bonsai2_27b_ternary_ptq1_native_mtp.ninfer`，只有 5.96 GB**。
配合 `--kv-capacity auto --kv-headroom-mib 512`（让它自己按剩余显存定池），权重 5.5 GiB 左右，
装得下，还能留出几百 MiB 余量。

```
加载后显存占用: 7,217 MiB / 8,151 MiB（空闲 682 MiB）
decode 24.3 tok/s | prefill 161.9 tok/s | TTFT 236 ms
```

---

## 三、第二课：GGUF 不是万能格式，"三元"有好几种互不兼容的打包

| 名称 | 位宽 | 谁认 |
|---|---|---|
| `TQ1_0` / `TQ2_0` | 1.69 / 2.06 bpw | **llama.cpp 上游原生** |
| `Q1_0` / `Q1_0_g128` | — | 某个 llama.cpp 分支（类型号 40/41） |
| `PTQ1_0` / `PQ2_0` | 1.75 / 2.13 bpw | **仅 PrismML 自家 fork（类型号 143）** |

我们下载的 `prism-ml` 官方 GGUF 用的是最后一种，上游和 Ollama 全部拒绝：

```text
# Ollama
Error: unsupported tensor "token_embd.weight" size overflows

# 自编译的 llama.cpp（镜像分支，支持到类型 41）
tensor 'token_embd.weight' has invalid ggml type 143. should be in [0, 42)
```

**唯一能在上游跑的三元 GGUF** 是社区重打包的 `Minarut/Ternary-Bonsai-8B-GGUF-llamacpp-compatible`
（把权重转成 `TQ2_0`），实测可用、答案是准的。

---

## 四、Windows 上从零编译 llama.cpp（不需要管理员权限的部分）

这台机器初始状态：**没有 MSVC、没有 CMake、没有 CUDA、没有 Git**。

完整流程见 [docs/03](docs/03-llama.cpp编译.md)，要点：

1. `vs_BuildTools.exe`（4.3 MB 引导器）带 `VCTools` + `VC.CMake.Project` 安装 —— 需要点一次 UAC
2. VS 装完自带 CMake 3.31.6 和 Ninja，不用另下
3. MinGit 便携版（38 MB，来自 npmmirror）用来克隆源码，GitHub 直连不通
4. 源码用 HF 镜像克隆，注意 git-lfs 会卡住，要禁用 filter
5. `cmake -G Ninja -DGGML_CUDA=OFF` + `cmake --build -j 16`

**实际耗时：配置 ~8 秒，编译 326 个目标 90 秒**（16 线程）。

CPU 版跑 8B 三元：`17+25` → `42`，生成 **14.1 tok/s**。

---

## 五、网络这一关（中国大陆环境实测）

| 目标 | 状态 |
|---|---|
| `github.com` | 超时 |
| `api.github.com` | ✅ 通（可查 release 元数据） |
| GitHub release 资产（release-assets.githubusercontent.com） | 0.07~0.13 MB/s，677 MB 要 90 分钟 |
| `raw.githubusercontent.com` | ✅ 通 |
| `hf-mirror.com` 小文件 | ✅ 通 |
| `hf-mirror.com` 大文件（xet CDN） | 单流 0.16~6 MB/s 波动；**超过 2 条并发会被挂起或 429** |
| `pypi.org` | 超时（清华/阿里镜像可用） |
| `developer.download.nvidia.com` | ✅ 通（CUDA redist 可下） |
| `cmake.org` / `aka.ms` / `npmmirror.com` | ✅ 通 |
| 夸克网盘 | 页面可读，**下载需登录 + 网盘有余量** |

**最反直觉的一条**：hf-mirror 上用 6~10 路并发下大文件，总吞吐反而低于单流，
而且请求会全部卡在 0 字节。**单流断点续传（`curl -C -`）是唯一稳定的方式**，峰值能到 6 MB/s。

---

## 六、仓库内容

```
docs/
  01-环境.md                  硬件/驱动/系统实测
  02-NInfer部署与踩坑.md       196 MiB 鸿沟的完整排查记录
  03-llama.cpp编译.md          Windows 无预装环境编译全过程
  04-GGUF与引擎匹配.md         三元量化的类型号地图
  05-网络与镜像.md             各下载源的实测速度与坑
  06-复现步骤.md               从零到能跑的完整命令序列
  07-对话轮次.md               按轮次还原的排查过程（含绕远路的部分）
scripts/
  check-env.ps1               采集本机环境，生成可比对的环境报告
  fetch-tools.ps1             下载便携工具链（cmake/ninja/git）
  build-llama-cpp-cpu.bat     一键编译（需已装 VS BuildTools）
  run-llama-cli.bat           加载 GGUF 跑一次推理
  bench-api.ps1               对 NInfer 服务打基准，输出 tok/s
logs/
  env.txt                     本机环境原始输出
  ninfer-8g-service.err.log   27B 服务端日志（含 TTFT/decode 计时）
  build-llama-cpp-cpu.log      编译输出（首尾节选）
  llama-8b-run.log            8B 推理输出
```

---

## 七、如果你只有 8 GB 显存，按这个顺序试

1. **先找小变体**。同一代三元模型常有 `full` / `mtponly` / `native_mtp` 三种打包，体积能差 3 GB。
   文件名里带 `ptq1_native_mtp` 的那类通常最小。
2. **让引擎自己定 KV 池**（`--kv-capacity auto`），别手写数字。手写容易撞上固定预算。
3. 关掉所有占卡程序再启动，虽然引擎预算可能是静态的，但至少给 CUDA context 腾地方。
4. 如果还是差一两百 MB，**别浪费时间调参**——换模型变体比调参有效一个数量级。
5. GGUF 路线要先确认张量类型号，`llama-gguf.exe` 或加载报错里都写了。

---

## 八、内存预算：我把自己机器搞崩过一次

写下来是因为很容易犯：**跑着 27B 引擎的时候，别再开第二个大模型进程。**

NInfer 的 8 GB 配方带 `--host-kv-mib 8192`，也就是向系统要 8 GB 给主机侧 KV。
这台机器只有 15.2 GB 物理内存：

```
15.2 GB 总内存
- 8.0 GB  主机 KV（引擎要的）
- 1.7 GB  DSH / 编辑器等
- 2~3 GB  Windows 自身
──────────────────
剩 2~3 GB
```

这时候再去 `llama-cli` 加载一个 2 GB 的 8B 模型，就会把系统压到开始杀进程。
我实际遇到的后果是：**DSH 进程被系统终止，它名下的引擎子进程也跟着没了**，
表现为"服务突然消失、GUI 端口号变了"。

正确做法：

- 跑 NInfer 服务时，别同时启动别的推理进程
- 真要对比两个引擎，**先停一个再起另一个**
- 或者把 `--host-kv-mib` 调小（比如 2048），代价是长上下文检索能力下降

还有一个容易忽略的点：`--host-kv-mib` 的内存是 **pinned（不可换页）**，
所以它比同样大小的普通内存更"硬"，实际压力比"任务管理器里看着还剩几 GB"更大。

---

## 九、许可

文档部分 CC BY 4.0。脚本部分 MIT。
NInfer 引擎、llama.cpp、各模型权重遵循各自上游许可，本仓库不再分发二进制。
