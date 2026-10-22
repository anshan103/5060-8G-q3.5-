# 02 · NInfer 部署与踩坑：196 MiB 的鸿沟

这份文档记录的是**失败路径的完整排查过程**。失败的原因很有教育意义：
不是软件坏了，而是"拿错了模型文件"。

---

## 一、先说结论

| 模型文件 | 体积 | 载入权重 | 结果 |
|---|---|---|---|
| `Ternary-Bonsai-2-27B-ninfer-v3.ninfer`（完整版） | 9.08 GB | 7.12 GiB | ❌ 运行时需 1.86 GB，可用 0 |
| `Ternary-Bonsai-2-27B-ninfer-v3-mtponly.ninfer` | 7.13 GB | 6.70 GiB（去掉 MTP 头） | ❌ 需 348 MiB，可用 152 MiB |
| **`bonsai2_27b_ternary_ptq1_native_mtp.ninfer`** | **5.96 GB** | ~5.5 GiB | ✅ **能跑，decode 24.3 tok/s** |

同一个 27B 三元模型，三种打包，体积差 3 GB，**能不能装进 8 GB 全看选对没**。

---

## 二、能跑的那条命令行（照抄即可）

```bat
D:\ninfer-120a\infer-engine-sm120a-20261002\engine\ninfer-serve-120a.exe ^
  D:\ninfer-120a\infer-engine-sm120a-20261002\models\bonsai2_27b_ternary_ptq1_native_mtp.ninfer ^
  --host 127.0.0.1 --port 8095 --model-id ninfer-local ^
  --kv-capacity auto --kv-headroom-mib 512 ^
  --kv-dtype rk4v4-e8 ^
  --max-context 131072 --max-concurrency 1 --prefill-chunk 256 ^
  --gdn-state-fp16 --no-cuda-graph --host-kv-mib 8192 ^
  --default-reasoning-effort none --default-max-tokens 1024
```

两个关键参数：

- **`--kv-capacity auto`**：让引擎按"剩余显存 − `--kv-headroom-mib`"自己决定 KV 池大小。
  手写一个数字（比如 `--kv-capacity 1024`）反而会撞上固定预算，报"0 bytes available"。
- **`--gdn-state-fp16`**：把 GDN 循环状态压成 FP16，省的虽在主机侧，但配合 auto 能把池定得更合适。

---

## 三、失败路径全记录

### 3.1 完整版：权重就把显存吃光

```
INFO  device profile nvidia-geforce-rtx-5060-laptop-gpu-sm120: 55 routed keys (calibration)
INFO  loading weights | 7.12 GiB
INFO  weights ready   | 7.12 GiB | 2.8s | 2.55 GiB/s
ERROR startup failed  | finalizing target
FATAL requested Engine runtime reservation requires 1863950080 bytes,
      but only 0 bytes are available for runtime capacity
```

7.12 GiB = 7,291 MiB，8,151 MiB 的卡剩不到 900 MiB，运行时一张口要 1.74 GiB。
**这里已经有 0 可用**——说明引擎在扣掉固定预留后一滴不剩。

### 3.2 mtponly：少了 0.42 GiB，缺口缩到 196 MiB

去掉 MTP 投机头后权重降到 6.70 GiB：

```
FATAL minimum Engine runtime reservation requires 335246592 bytes (320 MiB)
      in addition to 67108864 bytes (64 MiB) of automatic headroom,
      but only 192937984 bytes (184 MiB) are available after weights
```

缺口 320 + 64 − 184 = **200 MiB**。

### 3.3 所有省显存的尝试（全部无效）

| 尝试 | 效果 |
|---|---|
| `--kv-capacity` 17920 → 8192 → 4096 → 1024 | 运行时 1.86 GB → 431 MB → 348 MB，**撞到下限** |
| `--kv-dtype` `k8v4` → `rk2v4-e8` | 已是最省精度 |
| `--prefill-chunk 128` + `--no-cuda-graph` | 已用 |
| `--embedding-q4` / `--lm-head-q4` | 报错：`requires text/token_embedding to be stored as row-split Q8_G32` |
| `--kv-headroom-mib 64` | 报错：`requires --kv-capacity auto` |
| `--kv-capacity auto --kv-headroom-mib 64` | 仍差 384 − 184 = 200 MiB |
| `--wddm-evictable-budget` | 报错：`needs a Windows build with NINFER_D3D12_RESIDENCY=ON` |
| 关掉 QQ / Edge / 夸克 / 奥创 / 罗技 / Steam | 空闲显存 7,349 → **7,626 MiB** |
| 强制 `--device-profile calibrate`（86 秒校准） | 可用值仍是 **152 MiB** |
| 去掉 `--spec`（完全不加载投机头） | 权重 6.70 GiB，缺口 175 MiB |

**最后两行是关键证据**：空闲显存多了 277 MiB，引擎的"可用运行时预算"纹丝不动（152 MiB）。
它按卡型算固定预算，不看实时空闲。

### 3.4 引擎能不能把权重放到 CPU？

把 1.27 GB 的二进制分块扫了一遍，提取出全部 **43 个 `NINFER_*` 环境变量** 和 44 个 CLI 参数：

- `--host-kv-mib` / `NINFER_HOST_PAGEABLE` → KV 页可以放主机
- `--host-state-slots` → 检查点状态可以放主机
- `--disk-kv-path` → 被淘汰的 KV 可以落盘
- `--vision-residency cpu` → **视觉塔**可以走 CPU
- **没有任何"文本权重放主机"的开关**

原因也说得通：这个引擎是纯 CUDA 实现，三元 GEMM 是 `sm_120a` 专用 kernel
（变量里一堆 `NINFER_T2_*`、`NINFER_PTQ1_*`），**没有 CPU 计算后端**。
就算能把权重留在内存里，也没有代码能算它。

### 3.5 换成 2B 小模型？几何不兼容

```
INFO  loading weights | 608.4 MiB
INFO  weights ready   | 608.4 MiB | 273 ms
FATAL text/layers/0: input projection: unsupported logical projection geometry
```

引擎的 kernel 按 27B 的层形状编译死了（head 数、hidden size、投影维度）。
**这条引擎线里没有"用小模型兜底"这个选项。**

---

## 四、实测数据（能跑的那套）

来自服务端日志 `logs/ninfer-8g-service.err.log`：

```
req#1 done | openai-chat | stop token | prompt 28 | output 3
          | TTFT 589 ms | total 671 ms | prefill 47.6 tok/s | decode 24.6 tok/s

req#2 done | openai-chat | stop token | prompt 30 | output 150
          | TTFT 236 ms | total 6.4s | queue 33.4 ms
          | prefill 161.9 tok/s | decode 24.3 tok/s
```

- **decode 24.3 ~ 24.6 tok/s**
- prefill 随 chunk 大小波动（47.6 ~ 161.9 tok/s）
- TTFT 236 ~ 589 ms
- 显存占用 7,217 MiB / 8,151 MiB（空闲 682 MiB）

### 一个已知的质量告警

日志里反复出现：

```
[ninfer] kvmem harvest: fused rmsnorm+rope branch cannot expose the pre-RoPE key
        (layer 0, N tokens); this chunk is NOT in the index
```

含义：某些很小的分块（这里 N=3/4/21）拿不到 pre-RoPE key，**不会进 KVMem 检索索引**。
短上下文无影响；如果做长文检索命中率不对，这里是第一个要怀疑的地方。

---

## 五、可复用的排查顺序

1. 看 `loading weights` 的 GiB 数，和 8,151 MiB 对一下，先估算够不够
2. 看 `available for runtime capacity` 是不是 0 —— 是 0 就是权重阶段就吃满了
3. 看 `available after weights` 和 `minimum runtime reservation` 的差值
4. 差值在 200 MiB 以内 → 先试 `--kv-capacity auto` 和更小的模型变体，**别调参**
5. 差值在 1 GB 以上 → 直接换模型变体，调参没有意义

---

## 六、一条诚实的备注

这份文档最初写下的结论是"27B 装不下"，后来在同一台机器上发现 `ptq1_native_mtp` 那个 5.96 GB 的变体
可以跑通，才把结论改正过来。

**教训不是"多试参数"，而是"先确认自己拿的是哪个打包变体"。**
三元量化在 2026 年还没有统一命名，`full` / `mtponly` / `native_mtp` / `PQ2_0` / `PTQ1_0` / `TQ2_0`
这些后缀背后的体积差异，比任何参数优化的影响都大。
