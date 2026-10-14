"""G0 acceptance tests: pure policy, no hardware or cloud dependency."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "autonomy"))
from core import Core


class AutonomyTests(unittest.TestCase):
    def new(self):
        return Core(goal="follow up outstanding item")

    def test_positive_event_does_not_establish_owner(self):
        c = self.new()
        x = c.step(0, "person_detected")
        self.assertEqual(x["action"], "request_owner_confirmation")
        self.assertEqual(c.phase, "verify_owner")

    def test_duplicate_notifications_do_not_spam(self):
        c = self.new()
        c.step(0, "person_detected")
        self.assertEqual(c.step(1, "person_detected")["action"], "none")
        self.assertEqual(c.step(2, "person_detected")["action"], "none")

    def test_stale_event_is_unknown_not_absent(self):
        c = self.new()
        c.step(0, "person_detected")
        self.assertEqual(c.belief_at(61), "unknown")
        self.assertNotEqual(c.belief_at(61), "absent")

    def test_expired_confirmation_requires_new_evidence_and_cooldown(self):
        c = self.new()
        c.step(0, "person_detected")
        self.assertEqual(c.step(30, "tick")["reason"], "user_feedback_timeout_cooldown")
        self.assertEqual(c.step(31, "person_detected")["reason"], "cooldown_active")
        self.assertEqual(c.step(630, "person_detected")["action"], "request_owner_confirmation")

    def test_owner_rejects_no_private_goal_disclosure(self):
        c = self.new()
        c.step(0, "person_detected")
        self.assertEqual(c.step(1, "owner_rejected")["reason"], "not_owner_no_goal_disclosure")
        self.assertNotEqual(c.phase, "await_result")

    def test_feedback_defer_and_resume(self):
        c = self.new()
        c.step(0, "person_detected")
        self.assertEqual(c.step(1, "owner_confirmed")["action"], "ask_goal_status")
        self.assertEqual(c.step(2, "defer_goal")["action"], "record_goal_deferred")
        self.assertEqual(c.step(10, "person_detected")["reason"], "already_handling_or_deferred")
        self.assertEqual(c.step(1802, "person_detected")["action"], "request_owner_confirmation")

    def test_goal_complete_stops_all_prompts(self):
        c = self.new()
        c.step(0, "person_detected")
        c.step(1, "owner_confirmed")
        self.assertEqual(c.step(2, "goal_completed")["action"], "record_goal_completed")
        self.assertEqual(c.step(3600, "person_detected")["action"], "none")
        self.assertEqual(c.phase, "done")

    def test_daily_budget(self):
        c = self.new()
        for t in (0, 900, 1800):
            c.step(t, "person_detected")
            c.step(t + 1, "owner_rejected")
        self.assertEqual(c.step(2700, "person_detected")["reason"], "daily_interruption_budget_exhausted")

    def test_state_roundtrip(self):
        c = self.new()
        c.step(100, "person_detected")
        d = Core.restore(c.snapshot())
        self.assertEqual(d.step(101, "person_detected")["action"], "none")
        self.assertEqual(d.step(102, "owner_confirmed")["action"], "ask_goal_status")

    def test_time_must_be_monotonic(self):
        c = self.new()
        c.step(100, "tick")
        with self.assertRaises(ValueError):
            c.step(99, "tick")

    def test_completion_without_expected_feedback_not_accepted(self):
        c = self.new()
        self.assertEqual(c.step(0, "goal_completed")["reason"], "completion_not_expected")
        self.assertEqual(c.phase, "pending")


if __name__ == "__main__":
    unittest.main()
