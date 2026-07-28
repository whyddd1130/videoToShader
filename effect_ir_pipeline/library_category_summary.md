# Library Shader Category Summary

由 `update_library_category_info.py` 根据根目录 `库侧特效原子化建议.md` 生成。

## blur_bokeh (7)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| Bokeh | atomic | good | yes | 1.00 | blur_bokeh, color_tone, light_glow_flash, pixel_style | bokeh_blur, blur_bokeh, highlight_boost, soften, star, texture_pattern |  |
| DiamondBokeh | atomic | good | yes | 1.00 | blur_bokeh, transform_transition, color_tone, light_glow_flash | bokeh_blur, diamond_kernel, blur_bokeh, highlight_boost, soften, directional |  |
| HexagonalBokeh | atomic | good | yes | 1.00 | blur_bokeh, color_tone, light_glow_flash | bokeh_blur, hexagon_kernel, blur_bokeh, highlight_boost, hexagon |  |
| MipmapBlur | atomic | good | yes | 1.00 | blur_bokeh | mipmap_blur, blur_bokeh, soften |  |
| motionBlur | atomic | good | yes | 1.00 | blur_bokeh, transform_transition | directional_blur, motion_blur, blur_bokeh, translate, directional |  |
| PolygonBokeh | atomic | good | yes | 1.00 | blur_bokeh, color_tone, light_glow_flash | bokeh_blur, polygon_kernel, blur_bokeh, highlight_boost, polygon |  |
| SurfaceBlur | atomic | good | yes | 1.00 | blur_bokeh | surface_blur, blur_bokeh |  |

## color_tone (13)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| BrightFlash | conditional | inactive_on_model | no | 0.00 | color_tone, light_glow_flash, mask_composite | light_glow_flash, color_adjust, highlight_boost, luminance_alpha | valid_trigger_or_effect_specific_assets |
| ColorBalanceHLS | atomic | good | yes | 1.00 | color_tone | hue_shift, saturation, lightness, color_adjust, hue_saturation |  |
| ExtractChannel | atomic | good | yes | 1.00 | color_tone | channel_isolation, channel_shift |  |
| FlashWarning | atomic | good | yes | 1.00 | color_tone, mask_composite | hue_saturation, color_adjust, luminance_alpha |  |
| FourColorGradient | atomic | good | yes | 1.00 | color_tone, transform_transition | gradient_color_map, color_adjust, hue_saturation, global |  |
| HairDyeing | conditional | good | no | 0.35 | color_tone, subject_face | hair_color_shift, hue_shift, color_adjust, hue_saturation, subject_segmentation | hair_segmentation |
| Invert | atomic | good | yes | 1.00 | color_tone | invert, color_adjust |  |
| LeaveColor | atomic | good | yes | 1.00 | color_tone, blur_bokeh | selective_saturation, color_adjust, hue_saturation, soften |  |
| Lumetri | atomic | good | yes | 1.00 | color_tone | contrast, color_adjust |  |
| Lut | conditional | inactive_on_model | no | 0.00 | color_tone | color_adjust, hue_saturation | valid_trigger_or_effect_specific_assets |
| Metalman | composite | mixed | yes | 0.45 | color_tone, edge_outline, mask_composite | color_adjust, edge_outline_emboss, translate, hue_saturation, enhance, line_band, luminance_alpha |  |
| ShiftChannels | atomic | good | yes | 1.00 | color_tone | rgb_shift, channel_shift, color_adjust, channel_isolation |  |
| SplashScreen | atomic | good | yes | 1.00 | color_tone | color_adjust, flicker |  |

## edge_outline (6)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| EmbossNew | atomic | good | yes | 1.00 | edge_outline | emboss, edge_outline_emboss, enhance |  |
| Engrave | atomic | good | yes | 1.00 | edge_outline | engrave, edge_outline_emboss, enhance |  |
| LayerOutline | atomic | good | yes | 1.00 | edge_outline, light_glow_flash, mask_composite | layer_outline, edge_glow, edge_outline_emboss, light_glow_flash, translate, outline, polygon, analytic_shape |  |
| Outline | atomic | good | yes | 1.00 | edge_outline, mask_composite | outline, edge_outline_emboss, luminance_alpha |  |
| Sketch | atomic | good | yes | 1.00 | edge_outline, color_tone | edge_detect, sketch, edge_outline_emboss, contrast, outline |  |
| Stroke | atomic | good | yes | 1.00 | edge_outline, blur_bokeh | stroke, outline, edge_outline_emboss, blur_bokeh, rotate, line_band, radial, edge_map |  |

## geometry_warp (33)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| BasicBlocks | conditional | inactive_on_model | no | 0.00 | geometry_warp, mask_composite | displacement, composite_cutout, polygon, localized, analytic_shape | valid_trigger_or_effect_specific_assets |
| BezierWarp | atomic | good | yes | 1.00 | geometry_warp, transform_transition | bezier_warp, warp, deform, global |  |
| Bowknot | atomic | good | yes | 1.00 | geometry_warp, transform_transition | warp, deform, directional |  |
| Bulge | atomic | good | yes | 1.00 | geometry_warp, mask_composite | bulge, bulge_twirl, circle, radial, analytic_shape |  |
| CCCylinder | atomic | good | yes | 1.00 | geometry_warp, mask_composite | warp, rotate, circle, localized, analytic_shape |  |
| CCLens | atomic | good | yes | 1.00 | geometry_warp, mask_composite | lens_distortion, composite_cutout, circle, radial, analytic_shape |  |
| CCSphere | composite | mixed | yes | 0.45 | geometry_warp, color_tone, light_glow_flash, mask_composite | warp, light_glow_flash, rotate, brightness, circle, radial, analytic_shape |  |
| cornerPinAndTile | atomic | good | yes | 1.00 | geometry_warp, transform_transition | warp, mirror_repeat, tiled |  |
| DisplacementMap | atomic | good | yes | 1.00 | geometry_warp, transform_transition, pixel_style | displacement, deform, global, texture_pattern |  |
| edgeStretch | atomic | good | yes | 1.00 | geometry_warp, transform_transition | edge_stretch, warp, directional |  |
| Enlargement | atomic | good | yes | 1.00 | geometry_warp, blur_bokeh, mask_composite | warp, soften, circle, localized, analytic_shape |  |
| FaceRelocation | conditional | good | no | 0.35 | geometry_warp, transform_transition, subject_face | crop_transform, warp, translate, localized, subject_segmentation | face_tracking_or_landmarks |
| hahajing | composite | mixed | yes | 0.45 | geometry_warp, transform_transition | warp, directional |  |
| HeadMatting | conditional | inactive_on_model | no | 0.00 | geometry_warp, transform_transition, subject_face | warp, mirror_repeat, deform, localized, subject_segmentation | subject_segmentation |
| Inhalation | atomic | good | yes | 1.00 | geometry_warp | center_inhalation, warp, scale, grow_shrink, circle, radial |  |
| JellyDistortion | composite | mixed | yes | 0.45 | geometry_warp, transform_transition | mirror_repeat, warp, rotate, radial |  |
| kaleida | composite | mixed | yes | 0.45 | geometry_warp, transform_transition | mirror_repeat, warp, rotate, star, radial |  |
| LensDistortion2 | atomic | good | yes | 1.00 | geometry_warp | lens_distortion, circle, radial |  |
| MagnifyHead | conditional | good | no | 0.35 | geometry_warp, subject_face | warp, deform, circle, localized, subject_segmentation | face_tracking_or_landmarks |
| Mercury | composite | mixed | yes | 0.45 | geometry_warp, color_tone, light_glow_flash, mask_composite | displacement, light_glow_flash, translate, highlight_boost, circle, localized, analytic_shape |  |
| MosaicBurr | composite | mixed | yes | 0.45 | geometry_warp, transform_transition, color_tone | displacement, channel_shift, channel_isolation, global |  |
| MosaicColor1 | composite | mixed | yes | 0.45 | geometry_warp, transform_transition, color_tone, pixel_style | displacement, pixelation_mosaic, channel_shift, grid_tile, tiled |  |
| MosaicGlass2 | atomic | good | yes | 1.00 | geometry_warp, transform_transition | displacement, global |  |
| MosaicStar | atomic | good | yes | 1.00 | geometry_warp, pixel_style | displacement, star, localized, texture_pattern |  |
| NewShatter | composite | mixed | yes | 0.45 | geometry_warp, transform_transition, mask_composite | crop_transform, displacement, rotate, polygon, radial, analytic_shape |  |
| OpticsCompensation | atomic | good | yes | 1.00 | geometry_warp | lens_distortion, circle, radial |  |
| SEFaceSmooth | conditional | inactive_on_model | no | 0.00 | geometry_warp, subject_face | warp, deform, localized, subject_segmentation | face_region |
| Shatter | composite | mixed | yes | 0.45 | geometry_warp, mask_composite | displacement, composite_cutout, translate, polygon, localized |  |
| SlicingSlide | composite | mixed | yes | 0.45 | geometry_warp, transform_transition, blur_bokeh, mask_composite | displacement, blur_bokeh, translate, grid_tile, tiled, analytic_shape |  |
| SpillSuppressor | conditional | inactive_on_model | no | 0.00 | geometry_warp, subject_face | warp, deform, localized, subject_segmentation | foreground_or_chroma_condition |
| Tornado | composite | mixed | yes | 0.45 | geometry_warp, transform_transition | warp, crop_transform, deform, directional |  |
| Twirl | atomic | good | yes | 1.00 | geometry_warp, mask_composite | twirl, radial_warp, bulge_twirl, rotate, circle, swirl, analytic_shape |  |
| WaveWarp | atomic | good | yes | 1.00 | geometry_warp, transform_transition | wave_warp, warp, deform, line_band, directional |  |

## identity_none (4)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| Illusion | conditional | inactive_on_model | no | 0.00 | identity_none |  | valid_trigger_or_effect_specific_assets |
| Nothing | noop_or_test | not_for_generation | no | 0.00 | identity_none |  |  |
| Residual | conditional | inactive_on_model | no | 0.00 | identity_none |  | valid_trigger_or_effect_specific_assets |
| TestPass | noop_or_test | not_for_generation | no | 0.00 | identity_none |  |  |

## light_glow_flash (4)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| BlingBling | atomic | good | yes | 1.00 | light_glow_flash, color_tone, edge_outline | sparkle, star_glow, light_glow_flash, pulse, brightness, star, localized, edge_map |  |
| CCLightSweep | atomic | good | yes | 1.00 | light_glow_flash, transform_transition, color_tone, blur_bokeh, mask_composite | light_sweep, light_glow_flash, color_adjust, translate, brightness, soften, line_band, directional |  |
| EdgeGlow | atomic | good | yes | 1.00 | light_glow_flash, color_tone | edge_glow, light_glow_flash, flicker, highlight_boost, circle, radial |  |
| NeonArc | composite | mixed | yes | 0.45 | light_glow_flash, geometry_warp, color_tone, edge_outline | neon_edge_glow, channel_shift, displacement, warp, light_glow_flash, edge_outline_emboss, flicker, outline |  |

## mask_composite (6)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| EyesSticker | conditional | good | no | 0.35 | mask_composite, subject_face | composite_cutout, translate, localized, subject_segmentation | eye_landmarks |
| GradientWipe | atomic | good | yes | 1.00 | mask_composite, transform_transition, blur_bokeh | gradient_wipe, composite_cutout, soften, directional, luminance_alpha |  |
| LayerMask | atomic | good | yes | 1.00 | mask_composite, blur_bokeh | mask_composite, composite_cutout, soften, luminance_alpha |  |
| pointNine | atomic | good | yes | 1.00 | mask_composite | nine_patch_composite, composite_cutout |  |
| Progress | atomic | good | yes | 1.00 | mask_composite | progress_reveal, circle_mask, composite_cutout, grow_shrink, circle, analytic_shape |  |
| RandomImage | atomic | good | yes | 1.00 | mask_composite | random_image_composite, composite_cutout, randomized, localized |  |

## pixel_style (7)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| AsciiArtStyle | atomic | good | yes | 1.00 | pixel_style, transform_transition | ascii_luma_blocks, grid_tile, pixelation_mosaic, tiled |  |
| LowPixel | atomic | good | yes | 1.00 | pixel_style, transform_transition, color_tone | square_pixelate, pixelation_mosaic, color_adjust, flicker, hue_saturation, grid_tile, tiled |  |
| MosaicBuilding | atomic | good | yes | 1.00 | pixel_style, transform_transition, edge_outline | grid_mosaic, edge_outline, pixelation_mosaic, edge_outline_emboss, outline, grid_tile, tiled |  |
| MosaicColor2 | composite | mixed | yes | 0.45 | pixel_style, mask_composite | pixelation_mosaic, composite_cutout |  |
| MosaicHexagon | atomic | good | yes | 1.00 | pixel_style, transform_transition | hex_pixelate, pixelation_mosaic, hexagon, tiled |  |
| Newsprint | atomic | good | yes | 1.00 | pixel_style, transform_transition, color_tone, mask_composite | halftone, posterize, pixelation_mosaic, color_adjust, contrast, circle, tiled, luminance_alpha |  |
| Pattaizer | atomic | good | yes | 1.00 | pixel_style, transform_transition, mask_composite | pattern_tile, star_mask, pixelation_mosaic, composite_cutout, star, tiled, texture_pattern |  |

## transform_transition (12)

| effect | atomicity | quality | default | priority | buckets | primitives | requires |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| CCPageTurn | composite | mixed | yes | 0.45 | transform_transition, color_tone, light_glow_flash, mask_composite | fold_page, composite_cutout, light_glow_flash, deform, brightness, directional |  |
| CCPageTurn2 | atomic | good | yes | 1.00 | transform_transition | page_fold, fold_page, deform, directional |  |
| CCPageTurnWithBg | composite | mixed | yes | 0.45 | transform_transition, color_tone, light_glow_flash, mask_composite | fold_page, composite_cutout, light_glow_flash, deform, brightness, directional |  |
| FaceAnchor | conditional | good | no | 0.35 | transform_transition, subject_face | crop_transform, translate, localized, subject_segmentation | face_tracking_or_landmarks |
| FaceLocation | conditional | inactive_on_model | no | 0.00 | transform_transition, mask_composite, subject_face | crop_transform, composite_cutout, translate, localized | face_tracking_or_landmarks |
| Fold | atomic | good | yes | 1.00 | transform_transition, geometry_warp | fold_page, warp, deform, radial |  |
| fractalnoise | atomic | good | yes | 1.00 | transform_transition | randomized, global |  |
| Guoqing2021 | composite | mixed | yes | 0.45 | transform_transition, color_tone, mask_composite | composite_cutout, color_adjust, flicker, global |  |
| HeadTrack | conditional | good | no | 0.35 | transform_transition, subject_face | crop_transform, translate, localized, subject_segmentation | face_tracking_or_landmarks |
| RightAlpha | conditional | inactive_on_model | no | 0.00 | transform_transition, color_tone, mask_composite | crop_transform, composite_cutout, channel_isolation, directional, luminance_alpha | valid_trigger_or_effect_specific_assets |
| Transform | atomic | good | yes | 1.00 | transform_transition | translate, scale, crop_transform, global |  |
| Wiggle | atomic | good | yes | 1.00 | transform_transition | crop_transform, global |  |
