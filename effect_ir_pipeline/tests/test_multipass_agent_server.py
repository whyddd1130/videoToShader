from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("multipass_agent_server", ROOT / "tools" / "multipass_agent_server.py")
assert SPEC and SPEC.loader
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


class AgentServerCommandTest(unittest.TestCase):
    def test_state_lookup_uses_persisted_workflow_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "results").mkdir()
            state = directory / "results" / "real_job_agent_state.json"
            state.write_text(json.dumps({"phase": "waiting_for_human_feedback"}))
            resolved = server._state_path(directory, "alias", {"job_id": "real_job"})
            self.assertEqual(resolved, state)

    def test_dense_timeline_switch_reaches_workflow_cli(self) -> None:
        command = server._agent_command(
            job_id="dense_case",
            source=Path("source.png"),
            target=Path("target.mp4"),
            result_dir=Path("results"),
            metadata={"dense_timeline": True},
        )
        self.assertIn("--dense-timeline", command)
        self.assertEqual(command[command.index("--timeline-interval") + 1], "0.2")
        self.assertNotIn("--pass-count", command)
        self.assertNotIn("--pass-description", command)
        self.assertNotIn("--effect-description", command)

    def test_normal_mode_still_starts_without_dense_flag(self) -> None:
        command = server._agent_command(
            job_id="normal_case",
            source=Path("source.png"),
            target=Path("target.mp4"),
            result_dir=Path("results"),
            metadata={"pass_count": 2, "pass_description": "mask then composite"},
        )
        self.assertNotIn("--dense-timeline", command)
        self.assertIn("--pass-count", command)
        self.assertIn("--pass-description", command)

    def test_agent_process_is_detached_from_api_server(self) -> None:
        source = (ROOT / "tools" / "multipass_agent_server.py").read_text()
        self.assertIn("start_new_session=True", source)

    def test_resume_command_keeps_original_inputs_and_adds_resume_flag(self) -> None:
        command = server._agent_command(
            job_id="resume_case",
            source=Path("source.png"),
            target=Path("target.mp4"),
            result_dir=Path("results"),
            metadata={"pass_count": 4, "effect_description": "visible effect"},
            resume=True,
        )
        self.assertIn("--resume", command)
        self.assertIn("--pass-count", command)
        self.assertIn("--effect-description", command)


if __name__ == "__main__":
    unittest.main()
