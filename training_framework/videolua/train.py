from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader
from tqdm import tqdm

from .config import load_config
from .data import VideoLuaDataset, collate_classification
from .manifest import load_manifest, split_records
from .model import VideoParamEffectClassifier, make_text_bow


def accuracy(logits: torch.Tensor, labels: torch.Tensor) -> float:
    preds = logits.argmax(dim=1)
    return (preds == labels).float().mean().item()


def run_epoch(model, loader, optimizer, device, train: bool) -> dict[str, float]:
    model.train(train)
    total_loss = 0.0
    total_acc = 0.0
    total_count = 0
    iterator = tqdm(loader, desc="train" if train else "val")
    for batch in iterator:
        video_frames = batch["video_frames"].to(device, non_blocking=True)
        input_image = batch["input_image"].to(device, non_blocking=True)
        labels = batch["labels"].to(device, non_blocking=True)
        param_bow = make_text_bow(batch["param_text"], device=device) if model.use_param_text else None

        with torch.set_grad_enabled(train):
            logits = model(video_frames, input_image, param_bow)
            loss = F.cross_entropy(logits, labels)
            if train:
                optimizer.zero_grad(set_to_none=True)
                loss.backward()
                optimizer.step()

        batch_size = labels.shape[0]
        total_loss += loss.item() * batch_size
        total_acc += accuracy(logits.detach(), labels) * batch_size
        total_count += batch_size
        iterator.set_postfix(loss=total_loss / total_count, acc=total_acc / total_count)

    return {"loss": total_loss / total_count, "acc": total_acc / total_count}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("config.yaml"))
    args = parser.parse_args()

    cfg = load_config(args.config)
    base_dir = args.config.parent
    dataset_root = (base_dir / cfg["dataset_root"]).resolve()
    manifest_path = (base_dir / cfg["manifest_path"]).resolve()
    output_dir = (base_dir / cfg["output_dir"]).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    records = load_manifest(dataset_root, manifest_path)
    train_records, val_records, test_records = split_records(
        records,
        cfg["data"]["train_ratio"],
        cfg["data"]["val_ratio"],
        cfg["data"]["seed"],
    )
    labels = sorted({record.effect_name for record in records})
    label_to_id = {label: idx for idx, label in enumerate(labels)}
    (output_dir / "labels.json").write_text(json.dumps(label_to_id, indent=2), encoding="utf-8")

    common_dataset_args = dict(
        label_to_id=label_to_id,
        frame_indices=cfg["data"]["frame_indices"],
        image_size=cfg["data"]["image_size"],
        max_param_text_chars=cfg["data"]["max_param_text_chars"],
        max_lua_chars=cfg["data"]["max_lua_chars"],
        load_pixels=True,
    )
    train_ds = VideoLuaDataset(train_records, **common_dataset_args)
    val_ds = VideoLuaDataset(val_records, **common_dataset_args)

    use_cuda = torch.cuda.is_available()
    train_loader = DataLoader(
        train_ds,
        batch_size=cfg["train"]["batch_size"],
        shuffle=True,
        num_workers=cfg["train"]["num_workers"],
        pin_memory=use_cuda,
        persistent_workers=cfg["train"]["num_workers"] > 0,
        collate_fn=collate_classification,
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=cfg["train"]["batch_size"],
        shuffle=False,
        num_workers=cfg["train"]["num_workers"],
        pin_memory=use_cuda,
        persistent_workers=cfg["train"]["num_workers"] > 0,
        collate_fn=collate_classification,
    )

    device = torch.device("cuda" if use_cuda else "cpu")
    print(f"Using device: {device}")
    if use_cuda:
        print(f"CUDA device: {torch.cuda.get_device_name(0)}")
    model = VideoParamEffectClassifier(
        num_classes=len(labels),
        video_backbone=cfg["model"]["video_backbone"],
        temporal_model=cfg["model"].get("temporal_model", "mean"),
        freeze_video_backbone=cfg["model"]["freeze_video_backbone"],
        use_param_text=cfg["model"].get("use_param_text", True),
    ).to(device)
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=cfg["train"]["lr"],
        weight_decay=cfg["train"]["weight_decay"],
    )

    metadata = {
        "num_records": len(records),
        "num_train": len(train_records),
        "num_val": len(val_records),
        "num_test": len(test_records),
        "num_labels": len(labels),
    }
    (output_dir / "run_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    best_acc = -1.0
    for epoch in range(1, cfg["train"]["epochs"] + 1):
        train_metrics = run_epoch(model, train_loader, optimizer, device, train=True)
        val_metrics = run_epoch(model, val_loader, optimizer, device, train=False)
        metrics = {"epoch": epoch, "train": train_metrics, "val": val_metrics}
        print(json.dumps(metrics, indent=2))

        if cfg["train"]["save_every_epoch"]:
            torch.save(model.state_dict(), output_dir / f"checkpoint_epoch_{epoch}.pt")
        if val_metrics["acc"] > best_acc:
            best_acc = val_metrics["acc"]
            torch.save(model.state_dict(), output_dir / "best.pt")


if __name__ == "__main__":
    main()
