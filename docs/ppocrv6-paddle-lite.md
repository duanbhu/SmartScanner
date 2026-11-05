# PP-OCRv6 Tiny → Paddle Lite 转换方案

2026-11-05 已实际生成检测、识别两个 ARM `.nb` 模型，并在本地 DHPaddleLiteSDK 中新增 `OCRModelV6Tiny`，Example 已切换该资源包。尚未验证 iPhone 上的实际识别效果和速度。

## 本项目现状

- `Example/Podfile.lock`：本地 DHPaddleLiteSDK 2.0.0、PaddleLiteiOS 0.0.5，Example 使用 `OCRModelV6Tiny`。
- `PaddleEngine.swift` 通过 SDK 调用 OCR；模型加载、预处理和 CTC 解码在 DHPaddleLiteSDK 中。
- 现有 v4 `.nb` 文件头记录的 Lite 版本为 `v2.14-rc`。这不是 CocoaPods 包版本号；转换工具应与实际运行库匹配。
- 本地 SDK 已新增 v6 文件查找和资源包配置；识别尺寸由资源配置控制，v6 为 `[1,3,48,320]`，v4/v5 沿用原默认值。

## 已验证的转换路径

```text
官方训练权重 .pdparams + PaddleOCR v3.7.0 配置和网络代码
  → Global.export_with_pir=False
  → inference.pdmodel + inference.pdiparams
  → 识别模型的两组 Conv1D 卷积核常量折叠
  → Lite v2.14-rc opt，valid_targets=arm
  → PP-OCRv6_tiny_det_opt.nb / PP-OCRv6_tiny_rec_opt.nb
```

使用训练权重重新导出，不把 Hugging Face 的 `inference.json` 改名为 `.pdmodel`。无需经过 ONNX 或重新训练。

实际环境：macOS、Python 3.11、PaddlePaddle 3.2.2、PaddleOCR tag `v3.7.0`（`b03f46425e8ff4442b268ce449e3eef758146cd4`）、本机现有 `PaddleALL/Paddle-Lite/opt`（x86_64，可在本机运行）。

| 产物 | 实际字节数 | 状态 |
| --- | ---: | --- |
| `build/ppocrv6/det/PP-OCRv6_tiny_det_opt.nb` | 2,002,782 | opt 转换成功，文件头 v2.14-rc |
| `build/ppocrv6/rec/PP-OCRv6_tiny_rec_opt.nb` | 4,549,014 | opt 转换成功，文件头 v2.14-rc |
| `build/ppocrv6/rec/ppocrv6_tiny_dict.txt` | 以实际文件为准 | 从同一官方源码复制 |

`build/` 已被仓库忽略；上述文件保留在本地，不进入 Git。每个输出目录还包含旧静态图、`opt.log` 和 `conversion.json`。

## 两个实际遇到的问题

1. Paddle 3.x 的部分函数包装不接受旧静态图 `Variable`。3.3.1 的 GELU、multiply，以及 3.2.2 的 multiply、sigmoid 均有复现。脚本在当前进程中为 GELU、sigmoid 发出同名旧算子，将 multiply 写为等价的 `x * y`；不修改安装包或训练权重。
2. Tiny 识别头的 Conv1D 导出成 `assign(weight) → unsqueeze2 → conv2d`。Lite 算子检查虽然通过，直接优化却退出 139。将这两组权重 reshape 为持久化四维常量后，opt 成功。脚本只接受已验证的这两种链，并检查恰好折叠两组。

识别输入固定为 `[1,3,48,320]`，输出为 `[1,40,6906]`。仅固定输入形状不足以消除 opt 崩溃，仍需上述常量折叠。

对折叠前后的 Paddle 旧静态图，使用 3 组不同随机输入进行输出比较，最大绝对误差均为 **0.0**。这仅验证卷积核折叠的数值一致性，不代表 Lite 推理精度、真实图片识别率或 iPhone 性能已验证。

## 重现

准备上述版本的 PaddleOCR 源码、Paddle Python 依赖，以及与 iOS 运行库匹配的 Lite opt。使用独立 Python 环境，不覆盖现有环境。

官方训练权重下载（链接来自官方检测、识别模块文档）：

- [Tiny 检测训练权重](https://paddle-model-ecology.bj.bcebos.com/paddlex/official_pretrained_model/PP-OCRv6_tiny_det_pretrained.pdparams)
- [Tiny 识别训练权重](https://paddle-model-ecology.bj.bcebos.com/paddlex/official_pretrained_model/PP-OCRv6_tiny_rec_pretrained.pdparams)

在 SmartScanner 仓库根目录运行，替换示例路径。输出目录必须尚不存在，以免覆盖之前的模型：

```bash
python scripts/convert_ppocrv6_lite.py \
  --kind det \
  --paddleocr-root /path/to/PaddleOCR \
  --checkpoint /path/to/PP-OCRv6_tiny_det_pretrained.pdparams \
  --opt /path/to/Paddle-Lite/opt \
  --output-dir build/ppocrv6/det

python scripts/convert_ppocrv6_lite.py \
  --kind rec \
  --paddleocr-root /path/to/PaddleOCR \
  --checkpoint /path/to/PP-OCRv6_tiny_rec_pretrained.pdparams \
  --opt /path/to/Paddle-Lite/opt \
  --output-dir build/ppocrv6/rec
```

脚本会调用官方导出器、执行识别图的常量折叠及数值对照，再运行 opt。它不会替换 SDK 模型、修改 Podfile 或安装 Python 依赖。当前仅验证 Tiny、FP32、ARM CPU；small/medium、量化和 Metal 不在已验证范围内。

## 已完成的 SDK 接入

修改位于相邻的 `PaddleALL/DHPaddleLiteSDK` 源码仓库；Example 通过本地 `:path` 引用，未直接修改生成的 Pods 源码。发布 SDK 后再切换到正式版本依赖。

1. 新增 `OCRModelV6Tiny` 资源包，打包两个新模型、6904 行专属字典、配置及复用的 v2 方向分类模型。查找命名资源包时优先选择 v6 Tiny，原 v4/v5 包继续支持。
2. v6 识别输入固定为高 48、宽 320、batch 1；RGB 在 Pipeline 入口转成 BGR，按官方顺序缩放、归一化并补零。原版本的预处理默认值保留。
3. CTC 字典加 blank 和空格后对应 6906 类；解码前校验输出维度与字典长度，避免使用错误字典。
4. v6 独立配置使用 DB 阈值 0.2、box 阈值 0.4、unclip 比例 1.4；方向分类默认关闭，可继续使用已有开关启用。
5. Example 的 Podfile 和 lockfile 已切换到本地 SDK 的 v6 包。其他源码位置可设置 `SMARTSCANNER_PADDLE_SDK_PATH`。

待实机验证：两个 `.nb` 的完整执行、运行库算子兼容性、方向分类效果，以及业务面单上手机号/虚拟号/隐私号正确率和帧耗时。SmartScanner 有 0.14 秒实时识别节流和 2 秒相册等待逻辑，需用实际耗时评估。

接入验证已完成：`pod install --no-repo-update` 成功；`SmartScanner-Example` 的 Debug、iphoneos、arm64 目标在关闭签名时构建成功。构建产物中的两个模型 SHA-256 与转换产物一致，Lite 版本为 v2.14-rc；字典为 6904 行，补上 blank/空格后为 6906 类；v6 配置和分类模型均已打入 App，未包含 v4 资源包。

## 官方依据

- [PaddleOCR 旧静态图导出分支](https://github.com/PaddlePaddle/PaddleOCR/blob/v3.7.0/ppocr/utils/export_model.py)：`export_with_pir=False` 使用 OldIrGuard。
- [Tiny 识别配置](https://github.com/PaddlePaddle/PaddleOCR/blob/v3.7.0/configs/rec/PP-OCRv6/PP-OCRv6_tiny_rec.yml)：输入高度、字典及 CTC 头。
- [CTC guide_layer 的 Conv1D](https://github.com/PaddlePaddle/PaddleOCR/blob/v3.7.0/ppocr/modeling/heads/rec_ctc_head.py)。
- [官方 Lite 部署流程](https://github.com/PaddlePaddle/PaddleOCR/blob/main/deploy/lite/readme.md)：opt 参数及转换器、推理库版本匹配原则；该文档的现成模型示例较旧，不是 v6 实机支持证明。
