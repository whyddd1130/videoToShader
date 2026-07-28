from __future__ import annotations

import hashlib

import torch
import torch.nn as nn
import torchvision.models as tv_models


def make_text_bow(texts: list[str], dim: int = 2048, device: torch.device | None = None) -> torch.Tensor:
    features = torch.zeros(len(texts), dim, dtype=torch.float32, device=device)
    for row, text in enumerate(texts):
        tokens = text.replace("\n", " ").replace(":", " ").replace(",", " ").split()
        for token in tokens:
            digest = hashlib.md5(token.encode("utf-8")).hexdigest()
            bucket = int(digest[:8], 16) % dim
            features[row, bucket] += 1.0
    norms = features.norm(dim=1, keepdim=True).clamp_min(1.0)
    return features / norms


class VideoParamEffectClassifier(nn.Module):
    def __init__(
        self,
        num_classes: int,
        video_backbone: str = "resnet18",
        temporal_model: str = "mean",
        text_dim: int = 2048,
        hidden_dim: int = 512,
        freeze_video_backbone: bool = False,
        use_param_text: bool = True,
    ) -> None:
        super().__init__()
        if video_backbone != "resnet18":
            raise ValueError(f"Unsupported video_backbone: {video_backbone}")
        if temporal_model not in {"mean", "gru"}:
            raise ValueError(f"Unsupported temporal_model: {temporal_model}")

        backbone = tv_models.resnet18(weights=None)
        image_dim = backbone.fc.in_features
        backbone.fc = nn.Identity()
        self.image_encoder = backbone
        self.temporal_model = temporal_model
        self.image_dim = image_dim
        self.use_param_text = use_param_text
        if freeze_video_backbone:
            for param in self.image_encoder.parameters():
                param.requires_grad = False

        if temporal_model == "gru":
            self.temporal_encoder = nn.GRU(
                input_size=image_dim,
                hidden_size=image_dim // 2,
                num_layers=1,
                batch_first=True,
                bidirectional=True,
            )

        self.visual_proj = nn.Sequential(
            nn.Linear(image_dim * 2, hidden_dim),
            nn.ReLU(inplace=True),
            nn.Dropout(0.1),
        )
        if use_param_text:
            self.text_proj = nn.Sequential(
                nn.Linear(text_dim, hidden_dim),
                nn.ReLU(inplace=True),
                nn.Dropout(0.1),
            )
            classifier_input_dim = hidden_dim * 2
        else:
            classifier_input_dim = hidden_dim
        self.classifier = nn.Sequential(
            nn.Linear(classifier_input_dim, hidden_dim),
            nn.ReLU(inplace=True),
            nn.Dropout(0.1),
            nn.Linear(hidden_dim, num_classes),
        )

    def forward(
        self,
        video_frames: torch.Tensor,
        input_image: torch.Tensor,
        param_bow: torch.Tensor | None = None,
    ) -> torch.Tensor:
        batch_size, num_frames, channels, height, width = video_frames.shape
        flat_frames = video_frames.reshape(batch_size * num_frames, channels, height, width)
        frame_features = self.image_encoder(flat_frames).reshape(batch_size, num_frames, -1)
        if self.temporal_model == "gru":
            _, hidden = self.temporal_encoder(frame_features)
            frame_features = torch.cat([hidden[0], hidden[1]], dim=1)
        else:
            frame_features = frame_features.mean(dim=1)
        input_features = self.image_encoder(input_image)
        visual_features = self.visual_proj(torch.cat([frame_features, input_features], dim=1))
        if self.use_param_text:
            if param_bow is None:
                raise ValueError("param_bow is required when use_param_text=True")
            text_features = self.text_proj(param_bow)
            fused_features = torch.cat([visual_features, text_features], dim=1)
        else:
            fused_features = visual_features
        return self.classifier(fused_features)