# 04 · GGUF 与三元量化的类型号地图

2026 年了，"三元量化"还没有统一标准。同一个模型可能有五六种互不兼容的打包，
**文件后缀都叫 `.gguf`，但能读它的引擎完全不同**。这份文档是踩过之后整理的类型号地图。

---

## 一、核心事实：类型号决定谁能读

GGUF 文件头里每个张量都带一个 `ggml_type` 编号。加载器先看这个号，
不认识的直接拒绝，**不会尝试兼容**。

| 类型名 | 编号 | 位宽 | 谁能读 |
|---|---|---|---|
| `Q4_0` / `Q8_0` | 2 / 8 | 4.5 / 8.5 bpw | 所有 llama.cpp 系 |
| `TQ1_0` | 34 | 1.69 bpw | **llama.cpp 上游原生** |
| `TQ2_0` | 35 | 2.06 bpw | **llama.cpp 上游原生** |
| `Q1_0` | 40 | — | 某个 llama.cpp 分支 |
| `Q1_0_g128` | 41 | — | 同一分支 |
| `PTQ1_0` | **143** | 1.75 bpw | **仅 PrismML 自家 fork** |
| `PQ2_0` | 142/143 系 | 2.13 bpw | 同上 |

> 143 这个号远超过上游的 `GGML_TYPE_COUNT = 42`，所以上游会报
> `invalid ggml type 143. should be in [0, 42)`。

---

## 二、三种失败长相，一眼判断问题

### 2.1 上游 llama.cpp / Ollama 遇到 PTQ1_0

```
tensor 'token_embd.weight' has invalid ggml type 143. should be in [0, 42)
```

Ollama 的说法更含糊：

```
Error: unsupported tensor "token_embd.weight" size overflows
```

### 2.2 镜像分支（只支持到 41）遇到 143

```
gguf_init_from_file_impl: tensor 'output.weight' has invalid ggml type 143.
llama_model_load: error loading model
```

### 2.3 文件本身坏了 / 下了一半

```
error loading model: invalid magic
```
或者 `llama-gguf.exe` 直接报结构错误。用文件大小和发布页的字节数对一下最快。

---

## 三、哪个仓库给的是哪种

实测查过的（2026-10-21）：

| 仓库 | 文件 | 类型 | 上游可用 |
|---|---|---|---|
| `prism-ml/Ternary-Bonsai-2-27B-gguf` | `PTQ1_0`（5.54 GB） | 143 | ❌ |
| 同上 | `PQ2_0`（7.21 GB） | 142 系 | ❌ |
| `OS-Software/Ternary-Bonsai-2-27B-Uncensored-Heretic-v2-GGUF` | `PTQ1_0` / `PQ2_0` | 143 | ❌ |
| `dealignai/Bonsai-2-27B-Ternary-CRACK-GGUF` | `PQ2_0`（6.71 GB） | 142 系 | ❌ |
| `Hikari07jp/Ternary-Bonsai-2-27B-Abliterated-GGUF` | `PQ2_0` | 142 系 | ❌ |
| `CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF` | `PTQ1_0`（5.96 GB） | 143 | ❌ |
| **`Minarut/Ternary-Bonsai-8B-GGUF-llamacpp-compatible`** | **`TQ2_0`（1.97 GB）** | **35** | ✅ **能跑** |

**27B 这一档，截至 2026-10 没有上游可用的三元 GGUF。** 只有 8B 有社区重打包版。

---

## 四、为什么 27B 没人重打包

`TQ2_0` 是 2.06 bpw，27B 的 `TQ2_0` 大约 7.2 GB；`PTQ1_0` 是 1.75 bpw，约 5.5 GB。
重打包到 `TQ2_0` 会让 27B 在 8 GB 卡上更难放下——这大概就是社区只做了 8B 的原因。

8B 的 `TQ2_0` 只有 1.97 GiB，任何 8 GB 卡都轻松，所以有人愿意做。

---

## 五、怎么自己判断一个 GGUF 能不能读

### 方法 1：看 llama.cpp 报错里的类型号

直接 `llama-cli -m file.gguf -n 1`，报错里如果出现 `invalid ggml type N`，
拿 N 去和上表对照。

### 方法 2：用 llama-gguf.exe 看结构

自编译的 `build-cpu\bin\llama-gguf.exe` 可以打印张量列表和类型。

### 方法 3：看发布页的说明

作者通常会写"需要我们的 fork"或"upstream compatible"。**这句话比任何猜测都准。**

例如 `prism-ml` 的 README 里明确写着：

> These files need our llama.cpp build. Stock llama.cpp will **not** run these files.
> It rejects `PQ2_0` and `PTQ1_0` as unknown types.

看到这句就别浪费时间试上游了。

---

## 六、如果你要自己重打包

思路是把自定义打包的张量解包，再用标准 `TQ2_0` 重新量化。
需要：

1. 能读原始打包的 fork（否则连解包都做不到）
2. `llama-quantize` 支持目标类型
3. 一倍以上的磁盘空间

本机没有做这件事——因为 NInfer 那条路已经跑通了 27B，GGUF 只是备选。

---

## 七、一句话总结

> **`.gguf` 不等于"通用"。先确认类型号，再决定装哪个引擎。**
> 三元量化目前至少有三套互不兼容的类型编号，读懂发布页那句 "requires our fork"
> 能省下几个小时。
