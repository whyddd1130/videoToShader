from __future__ import annotations

import unittest

import cv2
import numpy as np

from effect_ir_pipeline.effect_ir.visual_observation import (
    band_orientation_profile,
    directional_blur_profile,
    directional_motion_profile,
    grid_tiling_score,
    line_structure_profile,
)
from effect_ir_pipeline.effect_ir.compare_video_ir import apply_observation_guardrails_to_ir
from effect_ir_pipeline.effect_ir.library_retrieval import rank_library


def _horizontal_bands(size: int = 64) -> np.ndarray:
    gray = np.zeros((size, size), dtype=np.uint8)
    gray[::4, :] = 255
    gray[1::4, :] = 180
    return gray


def _grid_tiles(size: int = 64, block: int = 8) -> np.ndarray:
    gray = np.zeros((size, size), dtype=np.uint8)
    for y in range(0, size, block):
        for x in range(0, size, block):
            gray[y : y + block, x : x + block] = 240 if ((x // block) + (y // block)) % 2 == 0 else 30
    return gray


class VisualObservationTest(unittest.TestCase):
    def test_line_bands_are_not_treated_as_grid_tiles(self) -> None:
        bands = _horizontal_bands()
        grid = _grid_tiles()

        band_profile = band_orientation_profile(bands)
        grid_profile = band_orientation_profile(grid)

        self.assertGreater(band_profile["horizontal_band_strength"], 0.8)
        self.assertLess(grid_tiling_score(bands), 0.5)
        self.assertGreater(grid_tiling_score(grid), grid_tiling_score(bands))
        self.assertGreater(grid_profile["grid_balance"], band_profile["grid_balance"])

    def test_directional_motion_profile_separates_x_from_y_jitter(self) -> None:
        base = np.zeros((64, 64), dtype=np.uint8)
        cv2.rectangle(base, (18, 18), (46, 46), 255, -1)
        shifted_x = np.roll(base, shift=5, axis=1)
        shifted_y = np.roll(base, shift=5, axis=0)

        x_motion = directional_motion_profile(base, shifted_x)
        y_motion = directional_motion_profile(base, shifted_y)

        self.assertGreater(x_motion["jitter_x"], x_motion["jitter_y"])
        self.assertGreater(y_motion["jitter_y"], y_motion["jitter_x"])
        self.assertGreater(x_motion["dominant_motion_axis_ratio"], 0.2)
        self.assertGreater(y_motion["dominant_motion_axis_ratio"], 0.2)

    def test_directional_blur_profile_uses_sampling_axis_not_band_orientation(self) -> None:
        base = np.zeros((96, 96), dtype=np.uint8)
        for x in range(8, 96, 16):
            cv2.rectangle(base, (x, 12), (x + 5, 84), 255, -1)
        blurred_x = cv2.GaussianBlur(base, (15, 1), 0)

        profile = directional_blur_profile(base, blurred_x)

        self.assertGreater(profile["sampling_blur_x"], profile["sampling_blur_y"])
        self.assertGreater(profile["sampling_axis_confidence"], 0.2)

    def test_line_structure_profile_prefers_bands_over_grid(self) -> None:
        bands = _horizontal_bands()
        grid = _grid_tiles()

        band_lines = line_structure_profile(bands)
        grid_lines = line_structure_profile(grid)

        self.assertGreater(band_lines["horizontal_line_strength"], band_lines["vertical_line_strength"])
        self.assertGreater(band_lines["dominant_line_axis_ratio"], 0.2)
        self.assertGreater(grid_lines["line_elongation_strength"], 0.0)

    def test_guardrail_converts_directional_smear_to_simple_transform(self) -> None:
        ir = {
            "region_scope": "full_frame",
            "geometry_ops": ["displacement"],
            "appearance_ops": ["none"],
            "temporal_pattern": "periodic",
            "mask_dependency": "none",
            "strength": "strong",
            "motion_hint": "flicker",
            "color_hint": "none",
            "edge_hint": "none",
            "shape_hint": "line_band",
            "subject_hint": "none",
            "geometry_pattern": "directional",
            "mask_shape_source": "none",
        }
        observation = {
            "aggregate": {
                "shape_bias_hint": "line_band_likely",
                "motion_bias_hint": "directional_jitter_likely",
            },
            "estimated_effect_profile": {
                "horizontal_line_strength": 0.77,
                "vertical_line_strength": 0.10,
                "dominant_line_axis_ratio": 0.74,
                "pixelation_strength": 0.0,
                "edge_emphasis": 0.04,
                "blur_strength": 0.04,
                "jitter_x": 0.78,
                "jitter_y": 0.40,
                "dominant_motion_axis_ratio": 0.36,
            },
        }

        guarded = apply_observation_guardrails_to_ir(ir, observation)

        self.assertEqual(guarded["operation_family"], "simple_transform")
        self.assertEqual(guarded["complexity"], "simple")
        self.assertEqual(guarded["geometry_ops"], ["crop_transform"])
        self.assertIn("linear_stretch_x", guarded["transform_primitives"])
        self.assertIn("directional_smear_x", guarded["transform_primitives"])

    def test_guardrail_overrides_wrong_flow_axis_with_blur_sampling_axis(self) -> None:
        ir = {
            "region_scope": "full_frame",
            "geometry_ops": ["crop_transform"],
            "appearance_ops": ["blur_bokeh"],
            "temporal_pattern": "periodic",
            "mask_dependency": "none",
            "strength": "medium",
            "motion_hint": "translate",
            "color_hint": "none",
            "edge_hint": "soften",
            "shape_hint": "line_band",
            "subject_hint": "none",
            "geometry_pattern": "directional",
            "mask_shape_source": "none",
            "transform_primitives": ["linear_stretch_y", "directional_smear_y"],
        }
        observation = {
            "aggregate": {"sampling_axis_hint": "x"},
            "estimated_effect_profile": {
                "sampling_blur_x": 0.42,
                "sampling_blur_y": 0.08,
                "sampling_axis_confidence": 0.68,
            },
        }

        guarded = apply_observation_guardrails_to_ir(ir, observation)

        self.assertIn("linear_stretch_x", guarded["transform_primitives"])
        self.assertIn("directional_smear_x", guarded["transform_primitives"])
        self.assertNotIn("directional_smear_y", guarded["transform_primitives"])

    def test_simple_transform_retrieval_penalizes_complex_glitch_reference(self) -> None:
        query = {
            "region_scope": "full_frame",
            "geometry_ops": ["crop_transform"],
            "appearance_ops": ["none"],
            "temporal_pattern": "periodic",
            "mask_dependency": "none",
            "strength": "strong",
            "motion_hint": "translate",
            "color_hint": "none",
            "edge_hint": "none",
            "shape_hint": "line_band",
            "subject_hint": "none",
            "geometry_pattern": "directional",
            "mask_shape_source": "none",
            "transform_primitives": ["linear_stretch_x", "directional_smear_x"],
            "complexity": "simple",
            "operation_family": "simple_transform",
        }
        library = [
            {
                "library_id": "DBScreenPulse",
                "sample_id": "DBScreenPulse_00__root",
                "effect_name": "DBScreenPulse",
                "structured_ir": {
                    "region_scope": "full_frame",
                    "geometry_ops": ["displacement"],
                    "appearance_ops": ["none"],
                    "temporal_pattern": "periodic",
                    "mask_dependency": "none",
                    "strength": "medium",
                    "motion_hint": "pulse",
                    "color_hint": "none",
                    "edge_hint": "none",
                    "shape_hint": "line_band",
                    "subject_hint": "none",
                    "geometry_pattern": "directional",
                    "mask_shape_source": "none",
                    "complexity": "complex",
                    "operation_family": "geometry_warp",
                },
                "category_info": {
                    "default_retrieval": True,
                    "retrieval_priority": 1.0,
                    "primary_bucket": "geometry_warp",
                    "primitives": ["displacement", "pulse", "line_band", "directional"],
                },
            },
            {
                "library_id": "SimpleDirectionalSmearX",
                "sample_id": "SimpleDirectionalSmearX",
                "effect_name": "SimpleDirectionalSmearX",
                "structured_ir": {
                    **query,
                },
                "category_info": {
                    "default_retrieval": True,
                    "retrieval_priority": 1.0,
                    "primary_bucket": "transform_transition",
                    "primitives": ["linear_stretch_x", "directional_smear_x", "crop_transform"],
                },
            },
        ]

        ranked = rank_library(query, library, strategy="balanced")

        self.assertEqual(ranked[0]["effect_name"], "SimpleDirectionalSmearX")
        self.assertGreater(ranked[0]["retrieval_score"], ranked[1]["retrieval_score"])


if __name__ == "__main__":
    unittest.main()
