# 🧠 MicroBreak T2D — Terminal Micro-Workout System

**A terminal-based micro-workout system for macOS (Zsh) that integrates guided 5-minute exercise sessions into 60-minute work cycles, optimizing metabolic health, posture, and productivity without breaking focus.**

---

## 🚀 Overview

MicroBreak T2D is a **lightweight, terminal-first automation tool** designed for people who spend long hours in front of a computer.

It implements a simple but powerful loop:

> **60 minutes of focused work → 5 minutes of guided movement**

Unlike basic timers, this system:

* guides you through **structured micro-workouts**
* intelligently rotates exercise types
* minimizes cognitive interruption
* requires **no gym, no setup, no friction**

---

## 🎯 Why this exists

Long periods of sitting are strongly linked to:

* poor glucose regulation
* reduced insulin sensitivity
* mental fatigue
* musculoskeletal issues

MicroBreak T2D applies the concept of **“exercise snacking”**:

> small, frequent bouts of movement → real metabolic impact

Designed especially for:

* developers 👨‍💻
* remote workers 🏠
* knowledge workers 🧠
* people managing **Type 2 Diabetes**

---

## ⚙️ Features

* ⏱ **60/5 work-rest cycle**
* 🧭 **Intelligent routine rotation**

  * mobility
  * metabolic (legs-focused)
  * upper body
  * cardio
  * core
  * full body
* 🗣 **Voice guidance (macOS `say`)**
* 🔔 **Native macOS notifications**
* 🖥 **Terminal-first UX (no GUI required)**
* 🎯 **Guided exercise execution (step-by-step)**
* 🔁 Infinite loop until stopped
* 🧪 **Test mode for quick validation**
* 🔧 **Minimal / Intense modes**

---

## 🧠 How it works

Each cycle:

1. 🧑‍💻 Work deeply for 60 minutes
2. 🔔 Get notified
3. 🏃 Perform a **guided 5-minute routine**
4. 🔁 Repeat

The system:

* avoids repeating the same category consecutively
* biases toward **metabolic/cardio blocks after meals**
* balances load across the day
* keeps sessions **short, effective, and realistic**

---

## 📦 Installation

Clone the repository:

```bash
git clone https://github.com/your-username/microbreak-t2d.git
cd microbreak-t2d
```

Make the script executable:

```bash
chmod +x microbreak.sh
```

Run it:

```bash
./microbreak.sh
```

---

## 🧪 Test Mode

Run with short timers:

```bash
./microbreak.sh --test
```

---

## 🎮 Usage Options

### Minimal mode (low energy days)

```bash
./microbreak.sh --minimal
```

* ultra simple routines
* low intensity
* minimal friction

---

### Intense mode (high energy days)

```bash
./microbreak.sh --intense
```

* higher intensity
* more cardiovascular demand

---

### Disable voice

```bash
./microbreak.sh --silent
```

---

### Disable notifications

```bash
./microbreak.sh --no-notify
```

---

### Change voice

```bash
./microbreak.sh --voice Paulina
```

---

## 🗣 Voice Setup (macOS)

List available voices:

```bash
say -v "?"
```

Recommended Spanish voices:

* `Monica`
* `Paulina`

If voice sounds wrong:

1. Go to:

   * **System Settings → Accessibility → Spoken Content**
2. Click:

   * **Manage Voices**
3. Download full Spanish voices

---

## 🧩 Customization

Edit the script:

```bash
microbreak.sh
```

You can easily modify:

### Work / Break duration

```zsh
WORK_MINUTES=60
BREAK_MINUTES=5
```

---

### Voice

```zsh
VOICE_NAME="Monica"
```

---

### Routine system

All routines are defined inside:

```zsh
load_routine()
```

You can:

* add new routines
* change exercises
* adjust durations
* modify intensity

---

## 🧠 Design Principles

* **Zero friction** → no setup, no equipment
* **Terminal-first** → always available
* **Cognitive respect** → minimal disruption
* **Physiology-driven** → not random exercises
* **Consistency > intensity**

---

## ⚠️ Disclaimer

This tool is not medical advice.

If you have:

* injuries
* chronic conditions
* severe metabolic disorders

Consult a professional before use.

---

## 💡 Roadmap (ideas)

* [ ] Adaptive routines based on time of day
* [ ] User state input (tired / energized / post-meal)
* [ ] Smart progression system
* [ ] Logging & analytics
* [ ] Integration with wearable data

---

## ❤️ Philosophy

> You don’t need a gym.
> You need consistency.

---

## 👤 Author

Built for real-world use by someone who:

* works long hours
* values health
* refuses unnecessary complexity

---

## ⭐ If you find this useful

Give it a star ⭐
Or fork it and improve it 🚀

