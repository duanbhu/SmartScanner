#!/usr/bin/env python3
"""Export PP-OCRv6 Tiny training weights to experimental ARM Paddle Lite models.

Requires PaddleOCR v3.7.0 source and Paddle 3.2.2. See docs/ppocrv6-paddle-lite.md.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def export_legacy(root, checkpoint, output, kind):
    import paddle
    from paddle.base.framework import Variable
    from paddle.base.layer_helper import LayerHelper
    import paddle.nn.functional as functional
    import paddle.jit.dy2static.utils as static_utils

    # Keep Paddle's generated Python sources inside a writable temporary folder.
    cache = tempfile.mkdtemp(prefix="smartscanner-paddle-static-")
    static_utils.get_temp_dir = lambda: cache

    # Paddle 3.x generated wrappers lack legacy Variable handling for these ops.
    # Emit the same operators, with their original attributes and weights.
    original_gelu, original_sigmoid = functional.gelu, functional.sigmoid

    def gelu(x, approximate=False, name=None):
        if isinstance(x, Variable):
            helper = LayerHelper("gelu", **locals())
            result = helper.create_variable_for_type_inference(dtype=x.dtype)
            helper.append_op(type="gelu", inputs={"X": x}, outputs={"Out": result},
                             attrs={"approximate": approximate})
            return result
        return original_gelu(x, approximate, name)

    def sigmoid(x, name=None):
        if isinstance(x, Variable):
            helper = LayerHelper("sigmoid", **locals())
            result = helper.create_variable_for_type_inference(dtype=x.dtype)
            helper.append_op(type="sigmoid", inputs={"X": x}, outputs={"Out": result})
            return result
        return original_sigmoid(x, name)

    functional.gelu, functional.sigmoid = gelu, sigmoid
    paddle.multiply = lambda x, y, name=None: x * y
    sys.path.insert(0, str(root))
    os.chdir(root)
    from tools.program import load_config
    from ppocr.utils import export_model

    original_to_static = export_model.to_static

    def fixed_to_static(model, input_spec, **kwargs):
        if kind == "rec":
            input_spec = [paddle.static.InputSpec([1, 3, 48, 320], "float32")]
        return original_to_static(model, input_spec=input_spec, **kwargs)

    export_model.to_static = fixed_to_static
    config = load_config(str(root / f"configs/{kind}/PP-OCRv6/PP-OCRv6_tiny_{kind}.yml"))
    config["Global"].update(pretrained_model=str(checkpoint),
                            save_inference_dir=str(output),
                            export_with_pir=False, use_gpu=False)
    export_model.export(config)
    if not (output / "inference.pdmodel").is_file():
        raise RuntimeError("Legacy export did not produce inference.pdmodel")


def fold_rec_filters(source, destination):
    import numpy as np
    import paddle

    paddle.enable_static()
    place = paddle.CPUPlace()
    with paddle.pir_utils.OldIrGuard():
        executor = paddle.static.Executor(place)
        program, feeds, fetches = paddle.static.load_inference_model(str(source), executor)
        block = program.global_block()
        producers = {name: op for op in block.ops for name in op.output_arg_names}
        folded = []
        for op in block.ops:
            if op.type not in ("conv2d", "depthwise_conv2d"):
                continue
            original = name = op.input("Filter")[0]
            if block.var(name).persistable:
                continue
            chain = []
            while name in producers and producers[name].type in ("assign", "unsqueeze2"):
                parent = producers[name]
                chain.append(parent.type)
                name = parent.input("X")[0]
            if chain != ["unsqueeze2", "assign"] or not block.var(name).persistable:
                raise RuntimeError(f"Unexpected filter graph: {original}: {chain}")
            shape = block.var(original).shape
            array = np.array(paddle.static.global_scope().find_var(name).get_tensor())
            array = array.reshape(shape)
            constant = original + ".lite_constant"
            block.create_var(name=constant, shape=shape, dtype="float32", persistable=True)
            paddle.static.global_scope().var(constant).get_tensor().set(array, place)
            op.desc.set_input("Filter", [constant])
            folded.append({"filter": original, "shape": list(shape)})
        if len(folded) != 2:
            raise RuntimeError(f"Expected 2 Tiny CTC guide filters, found {len(folded)}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        paddle.static.save_inference_model(str(destination), [block.var(x) for x in feeds],
                                          fetches, executor, program=program)

    def predict(prefix, data):
        with paddle.pir_utils.OldIrGuard(), paddle.static.scope_guard(paddle.static.Scope()):
            executor = paddle.static.Executor(place)
            program, feeds, fetches = paddle.static.load_inference_model(str(prefix), executor)
            return executor.run(program, feed={feeds[0]: data}, fetch_list=fetches)[0]

    errors = []
    rng = np.random.default_rng(42)
    for _ in range(3):
        data = rng.uniform(-1, 1, (1, 3, 48, 320)).astype("float32")
        before, after = predict(source, data), predict(destination, data)
        if not np.isfinite(before).all() or not np.isfinite(after).all():
            raise RuntimeError("Non-finite recognition output")
        np.testing.assert_allclose(before, after, rtol=1e-5, atol=1e-6)
        errors.append(float(np.max(np.abs(before - after))))
    return {"folded_filters": folded, "output_shape": list(after.shape),
            "max_absolute_errors": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=["det", "rec"], required=True)
    parser.add_argument("--paddleocr-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True, help="Training .pdparams file")
    parser.add_argument("--opt", type=Path, required=True, help="Lite v2.14-rc opt executable")
    parser.add_argument("--output-dir", type=Path, required=True, help="A new output directory")
    args = parser.parse_args()
    root, checkpoint, opt, output = (p.expanduser().resolve() for p in
                                    (args.paddleocr_root, args.checkpoint, args.opt, args.output_dir))
    if not checkpoint.is_file() or checkpoint.suffix != ".pdparams":
        parser.error("--checkpoint must be an existing training .pdparams file")
    if not opt.is_file() or not (root / "tools/export_model.py").is_file():
        parser.error("Missing opt executable or PaddleOCR source")
    output.mkdir(parents=True, exist_ok=False)
    export_legacy(root, checkpoint, output / "legacy", args.kind)
    prefix = output / "legacy/inference"
    report = {"kind": args.kind, "experimental": True, "iphone_verified": False}
    if args.kind == "rec":
        folded = output / "folded/inference"
        report.update(fold_rec_filters(prefix, folded))
        prefix = folded
        shutil.copyfile(root / "ppocr/utils/dict/ppocrv6_tiny_dict.txt", output / "ppocrv6_tiny_dict.txt")
    target = output / f"PP-OCRv6_tiny_{args.kind}_opt"
    command = [str(opt), f"--model_file={prefix}.pdmodel", f"--param_file={prefix}.pdiparams",
               "--valid_targets=arm", f"--optimize_out={target}", "--optimize_out_type=naive_buffer"]
    with (output / "opt.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    model = target.with_suffix(".nb")
    if not model.is_file() or model.stat().st_size == 0:
        raise RuntimeError("opt did not produce a nonempty .nb model")
    with model.open("rb") as stream:
        header = stream.read(18)
    report.update(model_bytes=model.stat().st_size,
                  lite_version=header[2:18].split(b"\0")[0].decode("ascii"))
    import paddle
    report["paddle_version"] = paddle.__version__
    report["paddleocr_commit"] = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    (output / "conversion.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
