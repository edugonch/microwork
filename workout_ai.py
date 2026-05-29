#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""workout_ai.py - AI coach for microbreak.sh

Handles session persistence, gap detection, local heuristics, and optional
LLM integration. Outputs shell-safe KEY=VALUE lines for eval/source in Zsh.

Commands:
  start --mode normal|minimal|intense [--no-llm] [--refresh-ai] [--ai-provider NAME]
  log <routine_id> <category> <intensity> <routine_name>
  end
"""

import argparse
import json
import os
import shlex
import sys
import time
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib import request as urllib_request, error as urllib_error

KNOWN_CATEGORIES = [
    "movilidad", "metabolico", "superior", "cardio",
    "core", "full_body", "equipment_upper", "equipment_core",
]
SCHEMA_VERSION = "WORKOUT_AI_RECOMMENDATION/1.0"
LLM_TIMEOUT = 8
CACHE_MAX_AGE_HOURS = 8
SUMMARY_WINDOW_DAYS = 14
DEFAULT_BASE_DIR = Path.home() / ".workout"
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG_PATH = SCRIPT_DIR / "config.json"

SYSTEM_PROMPT = (
    "Eres un coach de fitness personal para un desarrollador de software con "
    "Diabetes Tipo 2. Tu rol es analizar el historial de sesiones y recomendar "
    "prioridades de categoría para la sesión de hoy. El sistema ya tiene reglas "
    "de seguridad — tú solo sugieres prioridades. "
    "Responde ÚNICAMENTE con JSON válido, sin texto adicional."
)


class ValidationError(Exception):
    pass


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

class WorkoutConfig:
    DEFAULT = {
        "llm_provider": "anthropic",
        "api_keys": {},
        "providers": {
            "anthropic": {"model": "claude-sonnet-4-5"},
            "openai": {"model": "gpt-4o-mini"},
            "together": {
                "model": "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                "url": "https://api.together.xyz",
            },
            "ollama": {"url": "http://localhost:11434", "model": "llama3.2"},
        },
    }

    def __init__(self, config_path):
        self.config_path = Path(config_path)

    def load(self):
        if not self.config_path.exists():
            self.save(self.DEFAULT)
            return dict(self.DEFAULT)
        try:
            with open(self.config_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return dict(self.DEFAULT)

    def save(self, data):
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.config_path.with_suffix(".json.tmp")
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp, self.config_path)


# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

class SessionManager:
    def __init__(self, sessions_dir):
        self.sessions_dir = Path(sessions_dir)

    def _today_file(self):
        return self.sessions_dir / f"{date.today().isoformat()}.json"

    def _load_today(self):
        f = self._today_file()
        if f.exists():
            try:
                with open(f) as fp:
                    return json.load(fp)
            except (json.JSONDecodeError, OSError):
                pass
        return {"date": date.today().isoformat(), "runs": []}

    def _write(self, data):
        self.sessions_dir.mkdir(parents=True, exist_ok=True)
        target = self._today_file()
        tmp = target.with_suffix(".json.tmp")
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp, target)

    @contextmanager
    def _locked(self):
        self.sessions_dir.mkdir(parents=True, exist_ok=True)
        lock = self.sessions_dir / ".lock"
        acquired = False
        deadline = time.time() + 2
        while time.time() < deadline:
            try:
                fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.close(fd)
                acquired = True
                break
            except OSError:
                time.sleep(0.05)
        if not acquired:
            # Stale lock — remove and force-acquire
            try:
                lock.unlink()
                fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.close(fd)
                acquired = True
            except OSError:
                pass
        try:
            yield
        finally:
            if acquired:
                try:
                    lock.unlink()
                except OSError:
                    pass

    def start_run(self, mode):
        now = datetime.now()
        run_id = now.strftime("%Y%m%dT%H%M%S")
        with self._locked():
            data = self._load_today()
            data["runs"].append({
                "run_id": run_id,
                "start_time": now.strftime("%H:%M:%S"),
                "end_time": None,
                "mode": mode,
                "cycles": [],
            })
            self._write(data)
        return run_id

    def log_cycle(self, routine_id, category, intensity, routine_name):
        with self._locked():
            try:
                data = self._load_today()
                active = next(
                    (r for r in reversed(data["runs"]) if r["end_time"] is None),
                    None,
                )
                if active is None:
                    return
                cycle_num = len(active["cycles"]) + 1
                active["cycles"].append({
                    "cycle": cycle_num,
                    "routine_id": routine_id,
                    "routine_name": routine_name,
                    "category": category,
                    "intensity": intensity,
                    "completed_at": datetime.now().strftime("%H:%M:%S"),
                })
                self._write(data)
            except Exception:
                pass

    def end_run(self):
        with self._locked():
            try:
                data = self._load_today()
                for run in reversed(data["runs"]):
                    if run["end_time"] is None:
                        run["end_time"] = datetime.now().strftime("%H:%M:%S")
                        break
                self._write(data)
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Gap analysis
# ---------------------------------------------------------------------------

class GapAnalyzer:
    def __init__(self, sessions_dir):
        self.sessions_dir = Path(sessions_dir)

    def analyze(self, today=None):
        today = today or date.today()
        session_dates = self._session_dates()
        result = {
            "current_gap_days": None,
            "longest_gap_days": 0,
            "last_session_date": None,
            "days_with_sessions": len(session_dates),
        }
        if not session_dates:
            return result

        sorted_dates = sorted(session_dates)
        last = sorted_dates[-1]
        result["last_session_date"] = last.isoformat()
        result["current_gap_days"] = (today - last).days

        if len(sorted_dates) > 1:
            gaps = [
                (sorted_dates[i] - sorted_dates[i - 1]).days - 1
                for i in range(1, len(sorted_dates))
                if (sorted_dates[i] - sorted_dates[i - 1]).days - 1 > 0
            ]
            result["longest_gap_days"] = max(gaps) if gaps else 0

        return result

    def _session_dates(self):
        if not self.sessions_dir.exists():
            return []
        result = []
        for f in self.sessions_dir.glob("*.json"):
            try:
                result.append(date.fromisoformat(f.stem))
            except ValueError:
                pass
        return result


# ---------------------------------------------------------------------------
# Summary for LLM
# ---------------------------------------------------------------------------

class SummaryGenerator:
    def __init__(self, sessions_dir, window_days=SUMMARY_WINDOW_DAYS):
        self.sessions_dir = Path(sessions_dir)
        self.window_days = window_days

    def generate(self, mode="normal", cycles_done=0, today=None):
        today = today or date.today()
        cutoff = today - timedelta(days=self.window_days)
        category_counts = {cat: 0 for cat in KNOWN_CATEGORIES}
        days_with_sessions = 0

        if self.sessions_dir.exists():
            for f in self.sessions_dir.glob("*.json"):
                try:
                    d = date.fromisoformat(f.stem)
                except ValueError:
                    continue
                if d < cutoff:
                    continue
                days_with_sessions += 1
                try:
                    with open(f) as fp:
                        data = json.load(fp)
                except (json.JSONDecodeError, OSError):
                    continue
                for run in data.get("runs", []):
                    for cycle in run.get("cycles", []):
                        cat = cycle.get("category", "")
                        if cat in category_counts:
                            category_counts[cat] += 1

        gap = GapAnalyzer(self.sessions_dir).analyze(today=today)
        return {
            "available_categories": KNOWN_CATEGORIES,
            "last_14_days": {
                "days_with_sessions": days_with_sessions,
                "days_without_sessions": self.window_days - days_with_sessions,
                "current_gap_days": gap["current_gap_days"],
                "longest_gap_days": gap["longest_gap_days"],
                "last_session_date": gap["last_session_date"],
                "category_counts": category_counts,
            },
            "today": {
                "mode": mode,
                "cycles_done": cycles_done,
                "weekday": today.strftime("%A"),
            },
        }


# ---------------------------------------------------------------------------
# Local heuristic (no LLM needed)
# ---------------------------------------------------------------------------

class LocalHeuristic:
    def recommend(self, summary):
        last14 = summary.get("last_14_days", {})
        today_info = summary.get("today", {})
        gap = last14.get("current_gap_days")
        cat_counts = last14.get("category_counts", {})
        days_with = last14.get("days_with_sessions", 0)
        mode = today_info.get("mode", "normal")

        priority = list(KNOWN_CATEGORIES)
        soft_avoid = []
        recommended_mode = mode

        if gap is not None and gap >= 2:
            for cat in reversed(["movilidad", "metabolico"]):
                if cat in priority:
                    priority.remove(cat)
                    priority.insert(0, cat)
            soft_avoid = ["equipment_core", "equipment_upper"]
            if recommended_mode == "intense":
                recommended_mode = "normal"

        total = sum(cat_counts.values()) or 1
        if cat_counts.get("superior", 0) / total > 0.3:
            if "equipment_upper" in priority and priority.index("equipment_upper") < 4:
                priority.remove("equipment_upper")
                priority.append("equipment_upper")

        if days_with == 0:
            soft_avoid = []
            recommended_mode = "normal"

        # Guarantee all 8 categories present exactly once
        seen = set()
        deduped = []
        for cat in priority:
            if cat not in seen:
                seen.add(cat)
                deduped.append(cat)
        for cat in KNOWN_CATEGORIES:
            if cat not in seen:
                deduped.append(cat)
        priority = deduped

        gap_days = gap if gap is not None else 0
        gap_analysis = self._gap_analysis(gap_days)
        message = self._message(gap_days, cat_counts, days_with)
        reason_codes = self._reason_codes(gap_days, cat_counts)

        return {
            "schema_version": SCHEMA_VERSION,
            "priority_order": priority,
            "soft_avoid_categories": soft_avoid,
            "recommended_mode": recommended_mode,
            "reason_codes": reason_codes,
            "gap_analysis": gap_analysis,
            "message": message,
        }

    def _gap_analysis(self, gap_days):
        if gap_days == 0:
            return "Sin pausa reciente; continúa el ritmo."
        if gap_days == 1:
            return "Un día sin sesión; retomamos con normalidad."
        return f"Pausa de {gap_days} días detectada; inicio suave recomendado."

    def _message(self, gap_days, cat_counts, days_with):
        if days_with == 0:
            return "Primera sesión registrada. ¡Bienvenido al sistema!"
        if gap_days >= 3:
            return "Lleva varios días sin sesión. Hoy empezamos suave y retomamos el ritmo."
        if gap_days >= 2:
            return "Pausa reciente detectada. Comienza con movimiento suave y constante."
        if cat_counts.get("metabolico", 0) == 0:
            return "Hoy prioriza ejercicios metabólicos para activar el sistema."
        return "Consistencia sobre intensidad. Muévete cada hora."

    def _reason_codes(self, gap_days, cat_counts):
        codes = []
        if gap_days >= 2:
            codes.extend(["recent_gap_detected", "restart_progressively"])
        if cat_counts.get("metabolico", 0) < 2:
            codes.append("prioritize_glucose_uptake")
        return codes or ["no_special_conditions"]


# ---------------------------------------------------------------------------
# LLM response validation
# ---------------------------------------------------------------------------

def validate_llm_response(data):
    if not isinstance(data, dict):
        raise ValidationError("Response is not a dict")
    if data.get("schema_version") != SCHEMA_VERSION:
        raise ValidationError(
            f"Invalid schema_version: {data.get('schema_version')!r}"
        )
    priority = data.get("priority_order")
    if not isinstance(priority, list):
        raise ValidationError("priority_order must be a list")
    if set(priority) != set(KNOWN_CATEGORIES):
        raise ValidationError(
            f"priority_order must contain exactly the 8 known categories. Got: {priority}"
        )
    soft_avoid = data.get("soft_avoid_categories", [])
    if not isinstance(soft_avoid, list):
        raise ValidationError("soft_avoid_categories must be a list")
    if set(soft_avoid) >= set(KNOWN_CATEGORIES):
        raise ValidationError("soft_avoid_categories cannot block all categories")
    for cat in soft_avoid:
        if cat not in KNOWN_CATEGORIES:
            raise ValidationError(f"Unknown category in soft_avoid_categories: {cat!r}")
    return True


# ---------------------------------------------------------------------------
# Shell output
# ---------------------------------------------------------------------------

def build_shell_output(rec):
    priority = rec.get("priority_order", KNOWN_CATEGORIES)
    soft_avoid = rec.get("soft_avoid_categories", [])
    mode = rec.get("recommended_mode", "normal")
    gap = rec.get("gap_analysis", "")
    msg = rec.get("message", "")
    return "\n".join([
        "AI_ENABLED=1",
        f"AI_PRIORITY_ORDER={shlex.quote(' '.join(priority))}",
        f"AI_SOFT_AVOID={shlex.quote(' '.join(soft_avoid))}",
        f"AI_RECOMMENDED_MODE={shlex.quote(mode)}",
        f"AI_GAP_ANALYSIS={shlex.quote(gap)}",
        f"AI_MESSAGE={shlex.quote(msg)}",
    ])


def build_shell_disabled():
    return "AI_ENABLED=0"


# ---------------------------------------------------------------------------
# Recommendation cache
# ---------------------------------------------------------------------------

class RecommendationCache:
    def __init__(self, cache_dir):
        self.cache_dir = Path(cache_dir)

    def _cache_file(self):
        return self.cache_dir / f"rec-{date.today().isoformat()}.env"

    def get(self, max_age_hours=CACHE_MAX_AGE_HOURS, _now=None):
        f = self._cache_file()
        if not f.exists():
            return None
        ref = _now if _now is not None else time.time()
        age = ref - f.stat().st_mtime
        if age > max_age_hours * 3600:
            return None
        try:
            return f.read_text()
        except OSError:
            return None

    def set(self, text):
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        f = self._cache_file()
        tmp = f.with_suffix(".env.tmp")
        tmp.write_text(text)
        os.replace(tmp, f)


# ---------------------------------------------------------------------------
# LLM providers
# ---------------------------------------------------------------------------

class AnthropicProvider:
    def __init__(self, model, api_key):
        self.model = model
        self.api_key = api_key
        self.url = "https://api.anthropic.com/v1/messages"

    def call(self, system_prompt, user_prompt):
        payload = {
            "model": self.model,
            "max_tokens": 512,
            "system": system_prompt,
            "messages": [{"role": "user", "content": user_prompt}],
        }
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
        data = json.dumps(payload).encode()
        req = urllib_request.Request(self.url, data=data, headers=headers, method="POST")
        with urllib_request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
            body = json.loads(resp.read().decode())
        return body["content"][0]["text"]


class OpenAICompatibleProvider:
    def __init__(self, model, api_key, base_url):
        self.model = model
        self.api_key = api_key
        self.url = f"{base_url.rstrip('/')}/v1/chat/completions"

    def call(self, system_prompt, user_prompt):
        payload = {
            "model": self.model,
            "max_tokens": 512,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        data = json.dumps(payload).encode()
        req = urllib_request.Request(self.url, data=data, headers=headers, method="POST")
        with urllib_request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
            body = json.loads(resp.read().decode())
        return body["choices"][0]["message"]["content"]


class OllamaProvider:
    def __init__(self, model, url):
        self.model = model
        self.url = f"{url.rstrip('/')}/api/chat"

    def call(self, system_prompt, user_prompt):
        payload = {
            "model": self.model,
            "stream": False,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }
        data = json.dumps(payload).encode()
        req = urllib_request.Request(
            self.url, data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib_request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
            body = json.loads(resp.read().decode())
        return body["message"]["content"]


_KEY_LABELS = {
    "anthropic": ("ANTHROPIC_API_KEY", "console.anthropic.com"),
    "openai":    ("OPENAI_API_KEY",    "platform.openai.com"),
    "together":  ("TOGETHER_API_KEY",  "api.together.xyz"),
}


def _tty_write(msg):
    try:
        with open("/dev/tty", "w") as t:
            t.write(msg)
            t.flush()
    except OSError:
        pass


def _tty_read():
    try:
        with open("/dev/tty") as t:
            return t.readline().strip()
    except OSError:
        return ""


def _prompt_api_key(provider_name):
    label, url = _KEY_LABELS.get(provider_name, (f"{provider_name.upper()}_API_KEY", ""))
    _tty_write(f"\n[workout_ai] API key para '{provider_name}' no encontrada.\n")
    if url:
        _tty_write(f"  Consíguela en: {url}\n")
    _tty_write(f"  Ingresa {label}: ")
    return _tty_read()


def _save_api_key(config, provider_name, key):
    cfg = config.load()
    if "api_keys" not in cfg:
        cfg["api_keys"] = {}
    cfg["api_keys"][provider_name] = key
    config.save(cfg)


def _resolve_key(config, provider_name, env_var):
    """Return API key from env var first, then config file, then prompt user."""
    key = os.environ.get(env_var, "")
    if key:
        return key
    cfg = config.load()
    key = cfg.get("api_keys", {}).get(provider_name, "")
    if key:
        return key
    key = _prompt_api_key(provider_name)
    if key:
        _save_api_key(config, provider_name, key)
    return key


def make_provider(config, provider_override=None):
    cfg = config.load()
    provider_name = (
        provider_override
        or os.environ.get("WORKOUT_AI_PROVIDER")
        or cfg.get("llm_provider", "anthropic")
    )
    providers_cfg = cfg.get("providers", WorkoutConfig.DEFAULT["providers"])
    p_cfg = providers_cfg.get(provider_name, {})

    if provider_name == "anthropic":
        key = _resolve_key(config, "anthropic", "ANTHROPIC_API_KEY")
        if not key:
            return None
        return AnthropicProvider(p_cfg.get("model", "claude-sonnet-4-5"), key)

    if provider_name == "openai":
        key = _resolve_key(config, "openai", "OPENAI_API_KEY")
        if not key:
            return None
        return OpenAICompatibleProvider(
            p_cfg.get("model", "gpt-4o-mini"), key, "https://api.openai.com"
        )

    if provider_name == "together":
        key = _resolve_key(config, "together", "TOGETHER_API_KEY")
        if not key:
            return None
        base_url = p_cfg.get("url", "https://api.together.xyz")
        return OpenAICompatibleProvider(
            p_cfg.get("model", "meta-llama/Llama-3.3-70B-Instruct-Turbo"),
            key,
            base_url,
        )

    if provider_name == "ollama":
        return OllamaProvider(
            p_cfg.get("model", "llama3.2"),
            p_cfg.get("url", "http://localhost:11434"),
        )

    return None


def _build_user_prompt(summary):
    return (
        f"Analiza este historial de ejercicio y recomienda prioridades para hoy.\n\n"
        f"Datos:\n{json.dumps(summary, indent=2, ensure_ascii=False)}\n\n"
        f"Responde con este JSON exacto (sin texto adicional):\n"
        f'{{\n'
        f'  "schema_version": "{SCHEMA_VERSION}",\n'
        f'  "priority_order": [lista de las 8 categorías en orden de prioridad],\n'
        f'  "soft_avoid_categories": [],\n'
        f'  "recommended_mode": "normal",\n'
        f'  "reason_codes": ["code1"],\n'
        f'  "gap_analysis": "análisis breve",\n'
        f'  "message": "mensaje motivacional breve en español"\n'
        f"}}\n\n"
        f"Categorías válidas: {json.dumps(KNOWN_CATEGORIES)}"
    )


def call_llm_with_fallback(provider, summary, heuristic):
    if provider is None:
        return heuristic.recommend(summary)
    try:
        raw = provider.call(SYSTEM_PROMPT, _build_user_prompt(summary))
        start = raw.find("{")
        end = raw.rfind("}") + 1
        if start == -1 or end == 0:
            raise ValidationError("No JSON in LLM response")
        data = json.loads(raw[start:end])
        validate_llm_response(data)
        return data
    except Exception:
        return heuristic.recommend(summary)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_start(args, base_dir):
    sessions_dir = base_dir / "sessions"
    cache_dir = base_dir / "cache"
    config_path = Path(getattr(args, "config_path", None) or DEFAULT_CONFIG_PATH)

    try:
        SessionManager(sessions_dir).start_run(args.mode)
    except Exception:
        pass

    cache = RecommendationCache(cache_dir)
    if not args.refresh_ai:
        try:
            cached = cache.get()
            if cached:
                print(cached)
                return
        except Exception:
            pass

    try:
        summary = SummaryGenerator(sessions_dir).generate(args.mode)
    except Exception:
        summary = {
            "available_categories": KNOWN_CATEGORIES,
            "last_14_days": {
                "days_with_sessions": 0, "days_without_sessions": 14,
                "current_gap_days": None, "longest_gap_days": 0,
                "last_session_date": None,
                "category_counts": {c: 0 for c in KNOWN_CATEGORIES},
            },
            "today": {"mode": args.mode, "cycles_done": 0, "weekday": ""},
        }

    heuristic = LocalHeuristic()
    try:
        if args.no_llm:
            rec = heuristic.recommend(summary)
        else:
            config = WorkoutConfig(config_path)
            provider = make_provider(config, args.ai_provider)
            rec = call_llm_with_fallback(provider, summary, heuristic)
        shell_out = build_shell_output(rec)
        try:
            cache.set(shell_out)
        except Exception:
            pass
        print(shell_out)
    except Exception:
        print(build_shell_disabled())


def cmd_log(args, base_dir):
    try:
        SessionManager(base_dir / "sessions").log_cycle(
            args.routine_id, args.category, args.intensity, args.routine_name
        )
    except Exception:
        pass


def cmd_end(args, base_dir):
    try:
        SessionManager(base_dir / "sessions").end_run()
    except Exception:
        pass


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(prog="workout_ai.py")
    sub = parser.add_subparsers(dest="command")

    p_start = sub.add_parser("start")
    p_start.add_argument("--mode", default="normal")
    p_start.add_argument("--no-llm", action="store_true", dest="no_llm")
    p_start.add_argument("--refresh-ai", action="store_true", dest="refresh_ai")
    p_start.add_argument("--ai-provider", default=None, dest="ai_provider")
    p_start.add_argument("--base-dir", default=None, dest="base_dir")
    p_start.add_argument("--config-path", default=None, dest="config_path")

    p_log = sub.add_parser("log")
    p_log.add_argument("routine_id")
    p_log.add_argument("category")
    p_log.add_argument("intensity")
    p_log.add_argument("routine_name")
    p_log.add_argument("--base-dir", default=None, dest="base_dir")

    p_end = sub.add_parser("end")
    p_end.add_argument("--base-dir", default=None, dest="base_dir")

    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        sys.exit(1)

    base_dir = Path(args.base_dir) if getattr(args, "base_dir", None) else DEFAULT_BASE_DIR

    try:
        if args.command == "start":
            cmd_start(args, base_dir)
        elif args.command == "log":
            cmd_log(args, base_dir)
        elif args.command == "end":
            cmd_end(args, base_dir)
    except Exception:
        print(build_shell_disabled())


if __name__ == "__main__":
    main()
