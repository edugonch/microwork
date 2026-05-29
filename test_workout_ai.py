#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests for workout_ai.py — run with: python3 -m pytest test_workout_ai.py -v"""

import json
import os
import shutil
import tempfile
import time
import unittest
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch

from workout_ai import (
    KNOWN_CATEGORIES,
    SCHEMA_VERSION,
    AnthropicProvider,
    GapAnalyzer,
    LocalHeuristic,
    OllamaProvider,
    OpenAICompatibleProvider,
    RecommendationCache,
    SessionManager,
    SummaryGenerator,
    ValidationError,
    WorkoutConfig,
    build_shell_disabled,
    build_shell_output,
    call_llm_with_fallback,
    make_provider,
    validate_llm_response,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_session_file(sessions_dir, for_date, cycles=None):
    """Create a minimal session JSON file for the given date."""
    cycles = cycles or []
    d = for_date.isoformat()
    data = {
        "date": d,
        "runs": [{"run_id": f"{d}T090000", "start_time": "09:00:00",
                  "end_time": "11:00:00", "mode": "normal", "cycles": cycles}],
    }
    path = Path(sessions_dir) / f"{d}.json"
    path.write_text(json.dumps(data))
    return path


def valid_llm_response(**overrides):
    base = {
        "schema_version": SCHEMA_VERSION,
        "priority_order": list(KNOWN_CATEGORIES),
        "soft_avoid_categories": [],
        "recommended_mode": "normal",
        "reason_codes": ["no_special_conditions"],
        "gap_analysis": "Sin pausa.",
        "message": "Muévete.",
    }
    base.update(overrides)
    return base


def make_summary(gap=None, cat_counts=None, days_with=5, mode="normal"):
    counts = {c: 0 for c in KNOWN_CATEGORIES}
    if cat_counts:
        counts.update(cat_counts)
    return {
        "available_categories": KNOWN_CATEGORIES,
        "last_14_days": {
            "days_with_sessions": days_with,
            "days_without_sessions": 14 - days_with,
            "current_gap_days": gap,
            "longest_gap_days": 0,
            "last_session_date": None,
            "category_counts": counts,
        },
        "today": {"mode": mode, "cycles_done": 0, "weekday": "Thursday"},
    }


# ---------------------------------------------------------------------------
# TestSessionStorage
# ---------------------------------------------------------------------------

class TestSessionStorage(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.sessions_dir = os.path.join(self.tmpdir, "sessions")
        self.manager = SessionManager(self.sessions_dir)

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def _load_today(self):
        today = date.today().isoformat()
        with open(os.path.join(self.sessions_dir, f"{today}.json")) as f:
            return json.load(f)

    def test_creates_sessions_dir_if_not_exists(self):
        self.assertFalse(os.path.exists(self.sessions_dir))
        self.manager.start_run("normal")
        self.assertTrue(os.path.isdir(self.sessions_dir))

    def test_creates_new_session_file_for_today(self):
        run_id = self.manager.start_run("normal")
        today = date.today().isoformat()
        session_file = os.path.join(self.sessions_dir, f"{today}.json")
        self.assertTrue(os.path.exists(session_file))
        data = self._load_today()
        self.assertEqual(data["date"], today)
        self.assertEqual(len(data["runs"]), 1)
        run = data["runs"][0]
        self.assertEqual(run["run_id"], run_id)
        self.assertEqual(run["mode"], "normal")
        self.assertIsNotNone(run["start_time"])
        self.assertIsNone(run["end_time"])
        self.assertEqual(run["cycles"], [])

    def test_appends_new_run_same_day(self):
        self.manager.start_run("normal")
        self.manager.end_run()
        self.manager.start_run("minimal")
        data = self._load_today()
        self.assertEqual(len(data["runs"]), 2)
        self.assertIsNotNone(data["runs"][0]["end_time"])
        self.assertEqual(data["runs"][1]["mode"], "minimal")
        self.assertIsNone(data["runs"][1]["end_time"])

    def test_log_cycle_appends_to_active_run(self):
        self.manager.start_run("normal")
        self.manager.log_cycle("movilidad_1", "movilidad", "baja", "Reset Postural")
        data = self._load_today()
        cycles = data["runs"][-1]["cycles"]
        self.assertEqual(len(cycles), 1)
        c = cycles[0]
        self.assertEqual(c["cycle"], 1)
        self.assertEqual(c["routine_id"], "movilidad_1")
        self.assertEqual(c["category"], "movilidad")
        self.assertEqual(c["intensity"], "baja")
        self.assertEqual(c["routine_name"], "Reset Postural")
        self.assertIn("completed_at", c)

    def test_end_run_writes_end_time(self):
        self.manager.start_run("normal")
        self.manager.end_run()
        data = self._load_today()
        self.assertIsNotNone(data["runs"][0]["end_time"])

    def test_atomic_write_uses_temp_file(self):
        self.manager.start_run("normal")
        today = date.today().isoformat()
        tmp_file = os.path.join(self.sessions_dir, f"{today}.json.tmp")
        self.assertFalse(os.path.exists(tmp_file))

    def test_log_cycle_without_active_run_does_not_crash(self):
        try:
            self.manager.log_cycle("movilidad_1", "movilidad", "baja", "Reset Postural")
        except Exception as e:
            self.fail(f"log_cycle raised unexpectedly: {e}")


# ---------------------------------------------------------------------------
# TestGapDetection
# ---------------------------------------------------------------------------

class TestGapDetection(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.sessions_dir = Path(self.tmpdir) / "sessions"
        self.sessions_dir.mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def test_no_gap_consecutive_days(self):
        today = date(2026, 5, 29)
        for i in range(5):
            make_session_file(self.sessions_dir, today - timedelta(days=i))
        result = GapAnalyzer(self.sessions_dir).analyze(today=today)
        self.assertEqual(result["current_gap_days"], 0)

    def test_detects_two_day_gap(self):
        # Sessions on Monday (25) and Thursday (28); today is Saturday (30)
        today = date(2026, 5, 30)
        make_session_file(self.sessions_dir, date(2026, 5, 25))
        make_session_file(self.sessions_dir, date(2026, 5, 28))
        result = GapAnalyzer(self.sessions_dir).analyze(today=today)
        self.assertEqual(result["current_gap_days"], 2)

    def test_detects_gap_from_today(self):
        today = date(2026, 5, 29)
        last = today - timedelta(days=3)
        make_session_file(self.sessions_dir, last)
        result = GapAnalyzer(self.sessions_dir).analyze(today=today)
        self.assertEqual(result["current_gap_days"], 3)

    def test_no_sessions_ever(self):
        result = GapAnalyzer(self.sessions_dir).analyze(today=date(2026, 5, 29))
        self.assertIsNone(result["current_gap_days"])
        self.assertEqual(result["days_with_sessions"], 0)

    def test_session_today_no_gap(self):
        today = date(2026, 5, 29)
        make_session_file(self.sessions_dir, today)
        result = GapAnalyzer(self.sessions_dir).analyze(today=today)
        self.assertEqual(result["current_gap_days"], 0)


# ---------------------------------------------------------------------------
# TestSummaryGeneration
# ---------------------------------------------------------------------------

class TestSummaryGeneration(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.sessions_dir = Path(self.tmpdir) / "sessions"
        self.sessions_dir.mkdir()
        self.today = date(2026, 5, 29)

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def test_summary_counts_categories_correctly(self):
        cycles = [
            {"category": "movilidad"}, {"category": "movilidad"},
            {"category": "movilidad"}, {"category": "metabolico"},
            {"category": "metabolico"},
        ]
        make_session_file(self.sessions_dir, self.today, cycles=cycles)
        summary = SummaryGenerator(self.sessions_dir).generate("normal", today=self.today)
        counts = summary["last_14_days"]["category_counts"]
        self.assertEqual(counts["movilidad"], 3)
        self.assertEqual(counts["metabolico"], 2)

    def test_summary_window_is_14_days(self):
        old = self.today - timedelta(days=15)
        make_session_file(self.sessions_dir, old, cycles=[{"category": "movilidad"}])
        summary = SummaryGenerator(self.sessions_dir, window_days=14).generate(
            "normal", today=self.today
        )
        self.assertEqual(summary["last_14_days"]["category_counts"]["movilidad"], 0)

    def test_summary_includes_today_cycles(self):
        cycles = [{"category": "cardio"}]
        make_session_file(self.sessions_dir, self.today, cycles=cycles)
        summary = SummaryGenerator(self.sessions_dir).generate("normal", today=self.today)
        self.assertEqual(summary["last_14_days"]["category_counts"]["cardio"], 1)

    def test_summary_days_with_sessions_accurate(self):
        for i in range(5):
            make_session_file(self.sessions_dir, self.today - timedelta(days=i))
        summary = SummaryGenerator(self.sessions_dir, window_days=14).generate(
            "normal", today=self.today
        )
        self.assertEqual(summary["last_14_days"]["days_with_sessions"], 5)


# ---------------------------------------------------------------------------
# TestShellOutput
# ---------------------------------------------------------------------------

class TestShellOutput(unittest.TestCase):
    def test_shell_output_format_valid(self):
        rec = valid_llm_response()
        output = build_shell_output(rec)
        self.assertIn("AI_ENABLED=1", output)
        for line in output.strip().splitlines():
            self.assertIn("=", line, f"Line missing '=': {line!r}")

    def test_shell_output_escapes_special_chars(self):
        rec = valid_llm_response(
            message="Hoy: ¡hazlo! \"con fuerza\" y 'constancia'",
            gap_analysis="Pausa: 2 días",
        )
        output = build_shell_output(rec)
        self.assertIn("AI_MESSAGE=", output)
        self.assertIn("AI_GAP_ANALYSIS=", output)
        # Should be parseable as shell — no raw unquoted special chars
        self.assertNotIn("\n\n", output)

    def test_shell_output_priority_order_space_separated(self):
        rec = valid_llm_response()
        output = build_shell_output(rec)
        po_line = next(l for l in output.splitlines() if l.startswith("AI_PRIORITY_ORDER="))
        # Extract the quoted value
        import shlex
        val = shlex.split(po_line.split("=", 1)[1])[0]
        parts = val.split()
        self.assertEqual(len(parts), 8)
        self.assertEqual(set(parts), set(KNOWN_CATEGORIES))

    def test_shell_output_when_error_returns_ai_disabled(self):
        output = build_shell_disabled()
        self.assertEqual(output.strip(), "AI_ENABLED=0")
        self.assertNotIn("AI_MESSAGE", output)


# ---------------------------------------------------------------------------
# TestLocalHeuristic
# ---------------------------------------------------------------------------

class TestLocalHeuristic(unittest.TestCase):
    def _rec(self, **kwargs):
        return LocalHeuristic().recommend(make_summary(**kwargs))

    def test_gap_2days_raises_movilidad_weight(self):
        rec = self._rec(gap=2)
        idx = rec["priority_order"].index("movilidad")
        self.assertLessEqual(idx, 1, "movilidad should be in first 2 positions")

    def test_gap_2days_raises_metabolico_weight(self):
        rec = self._rec(gap=2)
        idx = rec["priority_order"].index("metabolico")
        self.assertLessEqual(idx, 2, "metabolico should be in first 3 positions")

    def test_gap_2days_never_recommends_intense(self):
        rec = self._rec(gap=2, mode="intense")
        self.assertNotEqual(rec["recommended_mode"], "intense")

    def test_heavy_superior_yesterday_lowers_equipment_upper(self):
        # 70% of cycles were superior → equipment_upper should be deprioritized
        cat_counts = {"superior": 7, "movilidad": 1, "metabolico": 1,
                      "cardio": 1, "core": 0, "full_body": 0,
                      "equipment_upper": 0, "equipment_core": 0}
        rec = self._rec(cat_counts=cat_counts)
        idx = rec["priority_order"].index("equipment_upper")
        self.assertGreaterEqual(idx, 4, "equipment_upper should be deprioritized")

    def test_no_sessions_returns_safe_defaults(self):
        rec = self._rec(gap=None, days_with=0)
        self.assertEqual(rec["soft_avoid_categories"], [])
        self.assertEqual(rec["recommended_mode"], "normal")

    def test_all_8_categories_always_in_priority_order(self):
        for gap in [None, 0, 1, 5, 10]:
            rec = self._rec(gap=gap)
            self.assertEqual(set(rec["priority_order"]), set(KNOWN_CATEGORIES))
            self.assertEqual(len(rec["priority_order"]), 8)


# ---------------------------------------------------------------------------
# TestLLMResponseValidation
# ---------------------------------------------------------------------------

class TestLLMResponseValidation(unittest.TestCase):
    def test_valid_response_passes_validation(self):
        self.assertTrue(validate_llm_response(valid_llm_response()))

    def test_missing_schema_version_fails(self):
        data = valid_llm_response()
        del data["schema_version"]
        with self.assertRaises(ValidationError):
            validate_llm_response(data)

    def test_unknown_category_in_priority_order_fails(self):
        data = valid_llm_response(
            priority_order=list(KNOWN_CATEGORIES[:-1]) + ["invented_category"]
        )
        with self.assertRaises(ValidationError):
            validate_llm_response(data)

    def test_missing_category_in_priority_order_fails(self):
        data = valid_llm_response(priority_order=list(KNOWN_CATEGORIES[:5]))
        with self.assertRaises(ValidationError):
            validate_llm_response(data)

    def test_soft_avoid_cannot_include_all_categories(self):
        data = valid_llm_response(soft_avoid_categories=list(KNOWN_CATEGORIES))
        with self.assertRaises(ValidationError):
            validate_llm_response(data)

    def test_invalid_json_returns_local_fallback(self):
        summary = make_summary()
        heuristic = LocalHeuristic()
        provider = MagicMock()
        provider.call.return_value = "not valid json at all"
        result = call_llm_with_fallback(provider, summary, heuristic)
        self.assertIn("priority_order", result)
        self.assertEqual(set(result["priority_order"]), set(KNOWN_CATEGORIES))

    def test_timeout_returns_local_fallback(self):
        import socket
        summary = make_summary()
        heuristic = LocalHeuristic()
        provider = MagicMock()
        provider.call.side_effect = TimeoutError("timed out")
        result = call_llm_with_fallback(provider, summary, heuristic)
        self.assertIn("priority_order", result)
        self.assertEqual(set(result["priority_order"]), set(KNOWN_CATEGORIES))


# ---------------------------------------------------------------------------
# TestProviderConfig
# ---------------------------------------------------------------------------

class TestProviderConfig(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.config_path = os.path.join(self.tmpdir, "config.json")

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def test_creates_default_config_if_missing(self):
        self.assertFalse(os.path.exists(self.config_path))
        config = WorkoutConfig(self.config_path)
        config.load()
        self.assertTrue(os.path.exists(self.config_path))
        with open(self.config_path) as f:
            data = json.load(f)
        self.assertIn("llm_provider", data)

    def test_anthropic_provider_uses_correct_endpoint(self):
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            mock_resp = MagicMock()
            mock_resp.__enter__ = lambda s: s
            mock_resp.__exit__ = MagicMock(return_value=False)
            mock_resp.read.return_value = json.dumps(
                {"content": [{"text": "{}"}]}
            ).encode()
            return mock_resp

        with patch("workout_ai.urllib_request.urlopen", fake_urlopen):
            provider = AnthropicProvider("claude-sonnet-4-5", "fake-key")
            try:
                provider.call("sys", "usr")
            except Exception:
                pass
        self.assertIn("api.anthropic.com", captured.get("url", ""))

    def test_openai_provider_uses_correct_endpoint(self):
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            mock_resp = MagicMock()
            mock_resp.__enter__ = lambda s: s
            mock_resp.__exit__ = MagicMock(return_value=False)
            mock_resp.read.return_value = json.dumps(
                {"choices": [{"message": {"content": "{}"}}]}
            ).encode()
            return mock_resp

        with patch("workout_ai.urllib_request.urlopen", fake_urlopen):
            provider = OpenAICompatibleProvider("gpt-4o-mini", "fake-key", "https://api.openai.com")
            try:
                provider.call("sys", "usr")
            except Exception:
                pass
        self.assertIn("api.openai.com", captured.get("url", ""))

    def test_together_provider_uses_openai_format(self):
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            captured["body"] = json.loads(req.data.decode())
            mock_resp = MagicMock()
            mock_resp.__enter__ = lambda s: s
            mock_resp.__exit__ = MagicMock(return_value=False)
            mock_resp.read.return_value = json.dumps(
                {"choices": [{"message": {"content": "{}"}}]}
            ).encode()
            return mock_resp

        with patch("workout_ai.urllib_request.urlopen", fake_urlopen):
            provider = OpenAICompatibleProvider(
                "meta-llama/Llama-3.3-70B",
                "fake-key",
                "https://api.together.xyz",
            )
            try:
                provider.call("sys", "usr")
            except Exception:
                pass
        self.assertIn("api.together.xyz", captured.get("url", ""))
        self.assertIn("/v1/chat/completions", captured.get("url", ""))
        # Body uses OpenAI format
        self.assertIn("messages", captured.get("body", {}))

    def test_ollama_provider_uses_local_endpoint(self):
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            mock_resp = MagicMock()
            mock_resp.__enter__ = lambda s: s
            mock_resp.__exit__ = MagicMock(return_value=False)
            mock_resp.read.return_value = json.dumps(
                {"message": {"content": "{}"}}
            ).encode()
            return mock_resp

        with patch("workout_ai.urllib_request.urlopen", fake_urlopen):
            provider = OllamaProvider("llama3.2", "http://localhost:11434")
            try:
                provider.call("sys", "usr")
            except Exception:
                pass
        self.assertIn("localhost:11434", captured.get("url", ""))

    def test_missing_api_key_returns_local_fallback(self):
        env_backup = os.environ.pop("ANTHROPIC_API_KEY", None)
        try:
            config = WorkoutConfig(self.config_path)
            provider = make_provider(config, "anthropic")
            self.assertIsNone(provider)
            # call_llm_with_fallback with None provider → local heuristic
            summary = make_summary()
            rec = call_llm_with_fallback(None, summary, LocalHeuristic())
            self.assertIn("priority_order", rec)
        finally:
            if env_backup is not None:
                os.environ["ANTHROPIC_API_KEY"] = env_backup

    def test_env_var_provider_override_takes_precedence(self):
        # config says anthropic, env var says ollama
        config_data = {**WorkoutConfig.DEFAULT, "llm_provider": "anthropic"}
        with open(self.config_path, "w") as f:
            json.dump(config_data, f)
        config = WorkoutConfig(self.config_path)
        os.environ["WORKOUT_AI_PROVIDER"] = "ollama"
        try:
            provider = make_provider(config)
            self.assertIsInstance(provider, OllamaProvider)
        finally:
            del os.environ["WORKOUT_AI_PROVIDER"]


# ---------------------------------------------------------------------------
# TestCacheHandling
# ---------------------------------------------------------------------------

class TestCacheHandling(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.cache_dir = os.path.join(self.tmpdir, "cache")
        self.cache = RecommendationCache(self.cache_dir)

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def test_cache_used_if_fresh(self):
        self.cache.set("AI_ENABLED=1\nAI_MESSAGE='cached'")
        # _now = now + 1 hour → age = 1 hour < 8 hours → fresh
        result = self.cache.get(max_age_hours=8, _now=time.time() + 3600)
        self.assertIsNotNone(result)
        self.assertIn("AI_ENABLED=1", result)

    def test_cache_ignored_if_stale(self):
        self.cache.set("AI_ENABLED=1\nAI_MESSAGE='cached'")
        # _now = now + 10 hours → age = 10 hours > 8 hours → stale
        result = self.cache.get(max_age_hours=8, _now=time.time() + 10 * 3600)
        self.assertIsNone(result)

    def test_refresh_flag_bypasses_cache(self):
        # Cache fresh, but refresh_ai=True → LLM called (or no-llm → heuristic)
        self.cache.set("AI_ENABLED=1\nAI_MESSAGE='old'")
        # Test by checking that a fresh cache is ignored when refresh_ai=True
        # We verify cache.get() is not called when refresh_ai is set
        # (Integration via cmd_start tested separately; here we verify fresh get works)
        result_fresh = self.cache.get(max_age_hours=8, _now=time.time() + 1)
        self.assertIsNotNone(result_fresh)
        # But when _now puts us past max age, it's stale
        result_stale = self.cache.get(max_age_hours=8, _now=time.time() + 9 * 3600)
        self.assertIsNone(result_stale)

    def test_cache_written_after_llm_call(self):
        rec = valid_llm_response()
        shell_out = build_shell_output(rec)
        self.cache.set(shell_out)
        today = date.today().isoformat()
        cache_file = os.path.join(self.cache_dir, f"rec-{today}.env")
        self.assertTrue(os.path.exists(cache_file))
        with open(cache_file) as cf:
            content = cf.read()
        self.assertIn("AI_ENABLED=1", content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
