# Texas Squat (Watch + iPhone) — README

## Overview

Texas Squat is a real-time squat tracking system using Apple Watch motion sensors, CoreML inference, and an iPhone SwiftUI dashboard. It estimates knee valgus risk and squat quality per rep while providing live feedback and per-rep reporting.

The system consists of:

* Apple Watch app: collects IMU data + delivers haptic feedback
* iPhone app: runs CoreML model, computes rep logic, and displays analytics

Communication is handled via `WatchConnectivity`.

---

## Core Features

### 1. Real-time squat rep detection

* Uses vertical acceleration (`az`) and state machine logic:

  * `atTop → goingDown → goingUp → atTop`
* Detects valid squat repetitions using threshold-based motion phases
* Prevents double-counting using rep locking and cooldown timing

---

### 2. Knee valgus estimation (CoreML + heuristic fusion)

* CoreML model: `SquatMLModel`
* Input: sliding window of IMU data (44 timesteps × 9 features)
* Output classification:

  * Detects knee cave pattern (`KneeCave`)
* Combined with:

  * IMU pitch heuristic
* Smoothed using exponential moving average:

Conceptually:

* ML prediction + biomechanical proxy → fused valgus score

Displayed as:

* `liveValgusPercent` (0–100%)
* `currentValgusLevel`: `none | low | medium | high`

---

### 3. Real-time feedback loop (Watch → User)

* Watch receives valgus level updates:

  * `none`, `medium`, `high`
* Haptic feedback mapping:

  * medium → directional haptic
  * high → notification haptic
  * none → click (or minimal feedback)
* Rate-limited to prevent spam (cooldown per severity)

---

### 4. Rep-by-rep analytics

Each completed rep generates a report:

```swift
struct RepReport: Identifiable {
    let rep: Int
    let valgus: Int   // average valgus % during rep
    let good: Bool    // valgus threshold-based classification
}
```

A rep is classified as:

* GOOD: valgus < 40%
* BAD: valgus ≥ 40%

---

### 5. Calibration system

Before tracking:

* Collects 50 stationary samples
* Computes baseline posture reference
* Ensures stable sensor normalization before rep detection

---

### 6. iPhone UI dashboard

Displays:

* Total reps
* Good vs bad reps
* Live valgus bar indicator
* Current valgus severity label
* Rep history log

UI components:

* Gradient header (status + rep count)
* Animated valgus bar
* Scrollable rep report list

---

## System Architecture

### Data flow

```
Apple Watch IMU
    ↓
WatchSessionManager
    ↓ (WCSession updateApplicationContext)
iPhone PhoneSessionManager
    ↓
Buffer (44 frames)
    ↓
CoreML + heuristics
    ↓
Rep logic + valgus scoring
    ↓
SwiftUI UI updates + reports
    ↓
Feedback sent back to Watch (haptics)
```

---

## Key Classes

### PhoneSessionManager

Responsible for:

* WCSession delegate handling
* IMU processing
* CoreML inference
* Rep detection state machine
* Valgus scoring + smoothing
* Report generation

Main outputs:

* `reps`
* `reports`
* `liveValgusPercent`
* `currentValgusLevel`

---

### WatchSessionManager

Responsible for:

* Continuous motion capture (25 Hz)
* Packaging IMU packets (9D feature vector)
* Sending data via `updateApplicationContext`
* Receiving valgus feedback messages
* Triggering haptic responses

---

## IMU Feature Vector

Each sample contains 9 values:

```
[ax, ay, az,
 gx, gy, gz,
 roll, pitch, yaw]
```

Sampling rate: ~25 Hz (Watch)

---

## CoreML Model

Model input:

* Shape: `[1, 9, 44]`

Interpretation:

* 9 sensor channels
* 44 time steps (temporal window)

Output:

* Classification label:

  * `"KneeCave"`
  * `"Normal"`

---

## Rep Detection Logic (Summary)

A rep is confirmed when:

1. Downward motion detected (`az < startMovingZ`)
2. Bottom phase reached (`targetZThreshold`)
3. Upward return completes (`az > returnZThreshold`)
4. Timing constraints satisfied (> 1 sec between reps)

Additional safeguards:

* Rep lock prevents duplicates
* Top stability timer prevents noise-triggered reps

---

## Valgus Scoring Logic

Score is computed using:

* CoreML classification (binary risk signal)
* Pitch-based biomechanical proxy
* Weighted fusion:

Conceptually:

```
valgusScore =
    0.5 * ML_output +
    0.8 * pitch_normalized
```

Then smoothed:

```
filtered = 0.4 * previous + 0.6 * current
```

---

## Feedback System

### Watch haptics

Triggered based on valgus severity:

* none → no action / minimal tap
* medium → directional feedback
* high → strong alert haptic

The cooldown system prevents repeated firing during continuous poor form.

---

### iPhone feedback display

* Color-coded status:

  * green → stable
  * yellow → mild valgus
  * orange → moderate
  * red → high valgus

---

## Reset Behavior

Reset clears:

* reps
* reports
* buffers
* calibration state
* rep state machine

---

## Known Constraints / Assumptions

* Watch orientation assumed consistent on the knee
* IMU calibration required at rest before use
* CoreML model assumes a normalized training distribution
* Valgus estimation is proxy-based, not a medical-grade measurement

---

## Requirements

* iOS + watchOS app pair
* WatchConnectivity enabled
* CoreML model file: `SquatMLModel.mlmodel`
* SwiftUI iOS 16+
