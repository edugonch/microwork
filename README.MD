# MicroBreak T2D — Terminal Micro-Workout System

**A terminal-based micro-workout system for macOS (Zsh) that integrates guided 5-minute exercise sessions into 60-minute work cycles — now with an AI coach that learns from your history.**

---

## Overview

MicroBreak T2D implements a simple but powerful loop:

> **60 minutes of focused work → 5 minutes of guided movement**

Unlike basic timers, this system:

- guides you through **structured micro-workouts**
- intelligently rotates exercise types to avoid repetition
- **remembers your session history** and detects gaps in your routine
- connects to an **AI coach** (Claude, GPT, Llama, or local Ollama) that adapts today's priorities based on what you've done and how long you've rested
- requires **no gym, no setup, no friction**

---

## Why this exists

Long periods of sitting are strongly linked to poor glucose regulation, reduced insulin sensitivity, mental fatigue, and musculoskeletal issues.

MicroBreak T2D applies the concept of **"exercise snacking"**:

> small, frequent bouts of movement → real metabolic impact

Designed especially for developers, remote workers, and people managing **Type 2 Diabetes**.

---

## Features

- **60/5 work-rest cycle** (configurable)
- **12 pre-built routines**: mobility, metabolic, upper body, cardio, core, full body, push-up board, ab wheel
- **AI coach** with session memory — adapts daily priorities based on history and gaps
- **Session persistence** — every cycle is saved to `~/.workout/sessions/YYYY-MM-DD.json`
- **Gap detection** — if you missed 2+ days, the AI suggests a gentler restart
- **4 LLM providers**: Anthropic (Claude), OpenAI, Together AI (open-source models), Ollama (local, free)
- **Graceful degradation** — runs exactly like before if Python or API key is unavailable
- **Voice guidance** (macOS `say`)
- **Native macOS notifications**
- **Minimal / Intense / Normal modes**
- **Test mode** for quick validation

---

## Installation (macOS)

```bash
git clone https://github.com/your-username/microbreak-t2d.git
cd microbreak-t2d
./install.sh
```

The installer:

1. Copies `microbreak` and `workout_ai.py` to `~/.local/bin/`
2. Adds `~/.local/bin` to your PATH if needed (edits `~/.zshrc`)
3. Preserves any existing aliases (e.g. `microb`)
4. Asks which AI provider you want to use
5. Prompts for your API key and saves it to `config.json` (gitignored)

After installation:

```bash
microbreak
```

To update after pulling new changes:

```bash
cd microbreak-t2d
./install.sh
```

---

## AI Coach

On each session start, the AI analyzes your last 14 days and recommends which exercise categories to prioritize today.

**What it considers:**

- Days without sessions (gaps)
- Category distribution (e.g. you haven't done core in a week)
- Today's day of the week and mode

**What it outputs:**

- A priority order for today's exercise categories
- A motivational message shown in the banner
- A gap analysis if you've been away

The AI **suggests priorities** — the script's existing rules (equipment limits, mode, anti-repetition, post-meal bias) still apply on top.

### Supported providers

| Provider    | Models                    | Requires               |
| ----------- | ------------------------- | ---------------------- |
| `anthropic` | Claude Sonnet             | `ANTHROPIC_API_KEY`    |
| `openai`    | GPT-4o mini               | `OPENAI_API_KEY`       |
| `together`  | Llama 3.3, Mixtral, Qwen  | `TOGETHER_API_KEY`     |
| `ollama`    | Any local model           | Ollama running locally |

Switch provider at any time:

```bash
microbreak --ai-provider together
```

### API key setup

The installer handles this interactively. If you skipped it, run `install.sh` again or edit `config.json` directly:

```bash
# config.json lives next to the installed script:
~/.local/bin/config.json
```

```json
{
  "llm_provider": "anthropic",
  "api_keys": {
    "anthropic": "sk-ant-..."
  }
}
```

`config.json` is gitignored — your keys never leave your machine.

### AI flags

```bash
microbreak --no-ai          # Disable AI entirely (no Python call)
microbreak --refresh-ai     # Force new LLM call, ignore daily cache
microbreak --ai-provider ollama
```

---

## Usage

```bash
microbreak                  # Normal mode
microbreak --minimal        # Low-intensity (bad energy days)
microbreak --intense        # High-intensity (good energy days)
microbreak --test           # Short timers for quick testing
microbreak --silent         # No voice
microbreak --no-notify      # No macOS notifications
microbreak --voice Paulina  # Change TTS voice
microbreak --no-equipment   # Skip push-up board / ab wheel
```

---

## Session data

Each session is saved to:

```text
~/.workout/sessions/YYYY-MM-DD.json
```

Multiple runs per day are stored as separate entries within the same file:

```json
{
  "date": "2026-05-29",
  "runs": [
    {
      "run_id": "20260529T090000",
      "start_time": "09:00:00",
      "end_time": "11:05:00",
      "mode": "normal",
      "cycles": [
        {
          "cycle": 1,
          "routine_id": "movilidad_1",
          "routine_name": "Reset Postural de Escritorio",
          "category": "movilidad",
          "intensity": "baja",
          "completed_at": "10:05:32"
        }
      ]
    }
  ]
}
```

---

## Voice setup (macOS)

List available voices:

```bash
say -v "?"
```

Recommended Spanish voices: `Monica`, `Paulina`

To download full quality voices: **System Settings → Accessibility → Spoken Content → Manage Voices**

---

## Customization

Edit `microbreak.sh` directly:

```zsh
WORK_MINUTES=60       # Work block duration
BREAK_MINUTES=5       # Break duration
VOICE_NAME="Mónica"   # TTS voice
USE_EQUIPMENT=1       # Include push-up board / ab wheel
```

All routines are defined in `load_routine()` — add new ones by following the same pattern.

---

## Running tests

```bash
python3 -m unittest test_workout_ai -v
```

44 tests covering session storage, gap detection, AI response validation, LLM providers, cache handling, and shell output formatting.

---

## How the AI works (technical)

```text
microbreak.sh
  └── calls workout_ai.py start
        ├── logs new run to ~/.workout/sessions/YYYY-MM-DD.json
        ├── checks ~/.workout/cache/rec-YYYY-MM-DD.env (8h cache)
        ├── summarizes last 14 days of history
        ├── applies local heuristics (gap detection, category balance)
        ├── optionally calls LLM with the summary
        ├── validates LLM response (8 known categories, schema version)
        └── outputs shell-safe KEY=VALUE lines → eval'd by microbreak.sh
```

If the LLM call fails or times out (>8s), the local heuristic is used instead. If Python is unavailable, the script runs exactly as before.

---

## Design principles

- **Zero friction** — no setup, no equipment required
- **Terminal-first** — always available, no GUI
- **Cognitive respect** — minimal disruption to deep work
- **Physiology-driven** — not random exercises
- **AI as coach, not authority** — rules stay in code, AI suggests priorities
- **Consistency > intensity**

---

## Disclaimer

This tool is not medical advice. If you have injuries, chronic conditions, or severe metabolic disorders, consult a professional before use.

---

## Author

Built for real-world use by someone who works long hours, values health, and refuses unnecessary complexity.
