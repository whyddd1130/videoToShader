from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch.utils.data import DataLoader
from tqdm import tqdm

from .config import load_config
from .data import VideoLuaDataset, collate_classification
from .manifest import load_manifest, split_records
from .model import VideoParamEffectClassifier, make_text_bow


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("config.yaml"))
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--split", choices=["val", "test"], default="test")
    args = parser.parse_args()

    cfg = load_config(args.config)
    base_dir = args.config.parent
    dataset_root = (base_dir / cfg["dataset_root"]).resolve()
    manifest_path = (base_dir / cfg["manifest_path"]).resolve()
    output_dir = (base_dir / cfg["output_dir"]).resolve()

    records = load_manifest(dataset_root, manifest_path)
    _, val_records, test_records = split_records(
        records,
        cfg["data"]["train_ratio"],
        cfg["data"]["val_ratio"],
        cfg["data"]["seed"],
    )
    split_records_selected = val_records if args.split == "val" else test_records

    label_to_id = json.loads((output_dir / "labels.json").read_text(encoding="utf-8"))
    id_to_label = {idx: label for label, idx in label_to_id.items()}

    dataset = VideoLuaDataset(
        split_records_selected,
        label_to_id=label_to_id,
        frame_indices=cfg["data"]["frame_indices"],
        image_size=cfg["data"]["image_size"],
        max_param_text_chars=cfg["data"]["max_param_text_chars"],
        max_lua_chars=cfg["data"]["max_lua_chars"],
        load_pixels=True,
    )
    loader = DataLoader(
        dataset,
        batch_size=cfg["train"]["batch_size"],
        shuffle=False,
        num_workers=cfg["train"]["num_workers"],
        collate_fn=collate_classification,
    )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = VideoParamEffectClassifier(
        num_classes=len(label_to_id),
        video_backbone=cfg["model"]["video_backbone"],
        temporal_model=cfg["model"].get("temporal_model", "mean"),
        freeze_video_backbone=cfg["model"]["freeze_video_backbone"],
        use_param_text=cfg["model"].get("use_param_text", True),
    ).to(device)
    model.load_state_dict(torch.load(args.checkpoint, map_location=device))
    model.eval()

    correct_1 = 0
    correct_5 = 0
    total = 0
    predictions: list[dict] = []
    for batch in tqdm(loader, desc=f"eval:{args.split}"):
        with torch.no_grad():
            logits = model(
                batch["video_frames"].to(device, non_blocking=True),
                batch["input_image"].to(device, non_blocking=True),
                make_text_bow(batch["param_text"], device=device) if model.use_param_text else None,
            )
        topk = logits.topk(k=min(5, logits.shape[1]), dim=1).indices.cpu()
        labels = batch["labels"]
        for i, label_id in enumerate(labels.tolist()):
            ranked = [id_to_label[int(idx)] for idx in topk[i].tolist()]
            correct_1 += int(ranked[0] == id_to_label[label_id])
            correct_5 += int(id_to_label[label_id] in ranked)
            total += 1
            predictions.append(
                {
                    "sample_id": batch["sample_id"][i],
                    "target": id_to_label[label_id],
                    "top_predictions": ranked,
                }
            )

    metrics = {
        "split": args.split,
        "total": total,
        "top1_acc": correct_1 / total if total else 0.0,
        "top5_acc": correct_5 / total if total else 0.0,
    }
    print(json.dumps(metrics, indent=2))
    pred_path = output_dir / f"predictions_{args.split}.jsonl"
    with pred_path.open("w", encoding="utf-8") as f:
        for row in predictions:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
