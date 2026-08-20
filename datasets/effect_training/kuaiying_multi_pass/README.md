# Kuaiying Multi-pass Effect Dataset

- valid samples: 52
- effects: 11 (Cartoon, ClearPictureQuality, CrossBlur, DeepGlow, HallucinationEffect, HazySoftLight, MosaicBlur, RainbowDrop, WaterDroplet, Wave, comic)
- failed/rejected samples: 20
- categories: {"blur_motion": 6, "color_distortion": 12, "detail_enhance": 4, "geometry_warp": 7, "glow_bloom": 9, "pixel_mosaic": 6, "stylize": 8}
- source: proj/Faceless_AEPlugin/resource/script
- video contract: 1080x1080, 25 fps, 125 frames, 5 seconds
- parameter contract: one primary strength parameter uses frame 0/62/124 low-high-low keyframes
- scope: general image-space multi-pass plugins; transitions, layer inputs, AI/face/matting/depth/spectrum/history are excluded
- intermediate pass videos: not included in v1; pipeline.json records extracted shaders and FBO allocation sites
- rejected renders are quarantined under failed/samples and are not listed in manifest.jsonl

Open review.html to inspect every accepted video and sampled frame. contact_sheet_midframes.jpg is the compact midpoint overview when present.
