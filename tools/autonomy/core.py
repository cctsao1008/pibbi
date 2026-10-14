"""Minimal deterministic goal-followup core. No network, hardware, or firmware access.

Input kinds are *internal experimental events*, not a claim about Watcher JSON.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional


@dataclass
class Config:
    person_ttl_s: int = 60
    confirmation_timeout_s: int = 30
    response_timeout_s: int = 60
    cooldown_s: int = 600
    defer_s: int = 1800
    max_opportunities_per_day: int = 3


@dataclass
class Core:
    goal: str
    config: Config = field(default_factory=Config)
    phase: str = "pending"  # pending, verify_owner, await_result, deferred, done
    last_person_at: Optional[int] = None
    response_due: Optional[int] = None
    next_allowed_at: int = 0
    opportunity_times: List[int] = field(default_factory=list)
    last_t: Optional[int] = None

    def belief_at(self, now: int) -> str:
        """A stale positive detection means UNKNOWN, not ABSENT."""
        if self.last_person_at is None:
            return "unknown"
        if now - self.last_person_at <= self.config.person_ttl_s:
            return "person_recently_detected"
        return "unknown"

    def _opportunity_budget_ok(self, now: int) -> bool:
        self.opportunity_times = [t for t in self.opportunity_times if now - t < 86400]
        return len(self.opportunity_times) < self.config.max_opportunities_per_day

    def step(self, now: int, kind: str) -> Dict[str, Any]:
        if self.last_t is not None and now < self.last_t:
            raise ValueError("nonmonotonic timestamp")
        self.last_t = now

        def decision(action: str, reason: str) -> Dict[str, Any]:
            return {"t": now, "input": kind, "action": action,
                    "reason": reason, "phase": self.phase,
                    "belief": self.belief_at(now)}

        if self.phase == "done":
            return decision("none", "goal_already_completed")

        # Process expiration before a newly arrived event.
        if self.phase in ("verify_owner", "await_result") and self.response_due is not None and now >= self.response_due:
            self.phase = "pending"
            self.response_due = None
            self.next_allowed_at = max(self.next_allowed_at, now + self.config.cooldown_s)
            return decision("none", "user_feedback_timeout_cooldown")

        if self.phase == "deferred" and now >= self.next_allowed_at:
            self.phase = "pending"

        if kind == "person_detected":
            self.last_person_at = now
            if self.phase != "pending":
                return decision("none", "already_handling_or_deferred")
            if now < self.next_allowed_at:
                return decision("none", "cooldown_active")
            if not self._opportunity_budget_ok(now):
                return decision("none", "daily_interruption_budget_exhausted")
            self.opportunity_times.append(now)
            self.phase = "verify_owner"
            self.response_due = now + self.config.confirmation_timeout_s
            return decision("request_owner_confirmation", "person_event_is_not_identity")

        if kind == "owner_confirmed":
            if self.phase != "verify_owner":
                return decision("none", "confirmation_not_expected")
            self.phase = "await_result"
            self.response_due = now + self.config.response_timeout_s
            return decision("ask_goal_status", "owner_explicitly_confirmed")

        if kind == "owner_rejected":
            if self.phase != "verify_owner":
                return decision("none", "rejection_not_expected")
            self.phase = "pending"
            self.response_due = None
            self.next_allowed_at = now + self.config.cooldown_s
            return decision("none", "not_owner_no_goal_disclosure")

        if kind == "goal_completed":
            if self.phase != "await_result":
                return decision("none", "completion_not_expected")
            self.phase = "done"
            self.response_due = None
            return decision("record_goal_completed", "explicit_user_feedback")

        if kind == "defer_goal":
            if self.phase != "await_result":
                return decision("none", "defer_not_expected")
            self.phase = "deferred"
            self.response_due = None
            self.next_allowed_at = now + self.config.defer_s
            return decision("record_goal_deferred", "explicit_user_feedback")

        if kind == "tick":
            return decision("none", "waiting_for_evidence")

        raise ValueError("unsupported event kind: " + kind)

    def snapshot(self) -> Dict[str, Any]:
        return {"goal": self.goal, "config": asdict(self.config),
                "phase": self.phase, "last_person_at": self.last_person_at,
                "response_due": self.response_due, "next_allowed_at": self.next_allowed_at,
                "opportunity_times": list(self.opportunity_times), "last_t": self.last_t}

    @classmethod
    def restore(cls, saved: Dict[str, Any]) -> "Core":
        data = dict(saved)
        data["config"] = Config(**data["config"])
        return cls(**data)
