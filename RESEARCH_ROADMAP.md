# 🚀 Research Roadmap: Vision-Based Keyboard & Mouseless Spatial OS
**Target Venues**: ACM UIST / ACM CHI / IEEE ISMAR / IROS  
**Project**: GestureFlow → SpatialDesktop Engine  
**Hardware Target**: Commodity Monocular RGB Webcam (Apple Silicon MacBooks)

---

## 📌 1. Baseline Achieved (GestureFlow Engine v1.2)

- **Native Architecture**: 100% Native Swift + SwiftUI, CoreMedia/AVFoundation, Apple Vision framework running on Apple Neural Engine (ANE).
- **Physical Footprint**:
  - Binary/Bundle Size: **696 KB** (zero Electron, zero Python runtime bloat).
  - Memory: **~100–120 MB** (video frame buffer).
  - CPU: **~2% overall** (~15–20% of one efficiency core with live HUD, < 1% when HUD is hidden).
- **HCI Interaction Model**:
  - 3-stage Apple Vision Pro Clutch & Scrub interaction: **Deliberate Pinch (`👌`) Engage → Spatial Ratchet Scrub → Release to Commit**.
  - 4-Layer Bulletproof Application Activation: AppKit `unhide()` + `activate(options: .activateIgnoringOtherApps)` + LaunchServices `NSWorkspace.openApplication` + Accessibility API `kAXFrontmostAttribute` & `kAXRaiseAction` + AppleScript `kAEActivate`.
  - VisionOS Smoked Glass Overhaul: $720 \times 175\text{ pt}$ obsidian glass base plate, specular rim highlights, contrast-dark capsule typography, spatial cradle focus backplate.

---

## 🎯 2. The Vision: True Keyboard & Mouseless Computing

Transforming commodity laptops into a full **Freehand Spatial Workspace** (replacing physical keyboard, mouse, and trackpad entirely) using a single monocular webcam.

### The 3 Fatal Traps of Prior Systems (Why Leap Motion & Kinect Failed)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. Zero-Friction Pointing Dilemma:                                          │
│    Physical mouse has pad friction absorbing 8-12Hz physiological tremor.   │
│    Free air has zero friction → Severe cursor wobble & Fitts' Law collapse. │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. The "Heisenberg Click Effect" (Click Tremor):                           │
│    Mechanical force of fingers clamping together deflects the hand by       │
│    5-15 pixels right at the moment of contact → Cursor slips off target.    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. The Mode-Confusion Nightmare:                                            │
│    Without physical buttons, distinguishing Hover vs. Drag vs. Scroll vs.   │
│    Click vs. System Macro vs. Hand Rest causes endless mis-triggers.        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🧠 3. Core Machine Learning Architecture

```
                      Monocular Webcam (RGB, 60 FPS)
                                    │
                                    ▼
         ┌───────────────────────────────────────────────────────┐
         │      Apple Vision / MediaPipe 21 Joint Keypoints       │
         │             X_{t-K:t} ∈ ℝ^{K × 21 × 2}                │
         └──────────────────────────┬────────────────────────────┘
                                    │
            ┌───────────────────────┴───────────────────────┐
            ▼                                               ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│ Module 1: Latent Mode         │   │ Module 2: Neural Dynamic      │
│ Classifier (Causal GNN / SSM) │   │ Controller (Deep RL Policy)   │
├───────────────────────────────┤   ├───────────────────────────────┤
│ • Temporal Early Anticipation │   │ • Dynamic Viscous Damping μ(t)│
│ • Hard-Negative Contrastive   │   │ • Adaptive Magnetic Snapping  │
│ • Pre-Click Coordinate Freeze │   │ • Physiological Tremor Damping│
└───────────────┬───────────────┘   └───────────────┬───────────────┘
                │                                   │
                └───────────────────┬───────────────┘
                                    ▼
         ┌───────────────────────────────────────────────────────┐
         │       macOS WindowServer / CGEvent / Quartz Core      │
         │  (Silky, Razor-Sharp Spatial Mouse & System Control)   │
         └───────────────────────────────────────────────────────┘
```

### Module 1: Causal Latent Mode & Intent Multiplexer (Sequence Modeling)
- **Goal**: Predict user intent and interaction mode **before** completion without mode confusion.
- **Input**: Temporal sliding window $\mathbf{X}_{t-K:t} \in \mathbb{R}^{K \times 21 \times 2}$ (normalized hand skeleton sequence).
- **Target Output**: $P(M_t \in \{\text{Hover}, \text{PreClick}, \text{Drag}, \text{Scroll}, \text{SystemMacro}, \text{Idle}\})$.
- **Key Innovations**:
  1. **Pre-Click Anchor Locking**: When $P(\text{PreClick}) > 0.85$ (fingers rapidly decelerating into pinch apex), lock/anchor cursor position for $35\text{ms}$ prior to contact $\rightarrow$ **0% click deflection, 100% click precision**.
  2. **Self-Supervised Hard-Negative Contrastive Learning (InfoNCE)**: Train embedding space to strictly separate daily ambient hand motions (scratching, resting, stretching) from deliberate communicative interactions.
  3. **Ultra-Lightweight Edge Deployment**: Quantized INT8/FP16 running on Apple Neural Engine in $< 1.0\text{ms}$.

### Module 2: Neural Dynamic Friction & Target Snapping (Deep RL / Optimal Control)
- **Goal**: Artificial synthetic friction field to eliminate the zero-friction tremor problem.
- **MDP Formulation**:
  - **State $s_t$**: $[\mathbf{p}_{\text{cursor}}, \mathbf{v}_{\text{hand}}, \mathbf{a}_{\text{hand}}, \text{dist\_to\_nearest\_UI\_target}, \text{target\_bounding\_box}]$.
  - **Action $a_t = [\mu_t, \mathbf{F}_{\text{attract}}]$**:
    - $\mu_t \in [\mu_{\min}, \mu_{\max}]$: Dynamic viscous damping coefficient. When moving fast across the screen, $\mu_t \to 0$ (inertial glide). When hand decelerates near a UI button/text, $\mu_t$ spikes (feels like moving through viscous honey), instantly damping 8-12Hz physiological tremor.
    - $\mathbf{F}_{\text{attract}} \in \mathbb{R}^2$: Adaptive magnetic snap force pulling the cursor into the target centroid.
  - **Reward Function (Fitts' Law Optimization)**:
    $$\mathcal{R}_t = \text{Throughput}(\text{bits/s}) - \alpha \|\mathbf{jerk}_t\|^2 - \beta \|\text{Overshoot}\|^2 + \gamma \mathbb{I}(\text{TargetAcquisition})$$
- **Training Strategy**:
  - Simulated kinematic agent trained via PPO / SAC in a Python gym environment with synthetic noise & Fitts' law target acquisition tasks.
  - Policy distilled into a 3-layer MLP ($< 50\text{KB}$) evaluated directly inside the Swift event loop.

### Module 3: Sub-Watt Cascaded Vision Pipeline (Systems Track)
- **Tier 0 (Ambient Idle)**: Subsampled $80 \times 60$ Luma plane at $4\text{ FPS}$ via Metal Compute motion energy check ($< 0.05\text{W}$).
- **Tier 1 (Kinematic Arming)**: $15\text{ FPS}$ hand bounding-box ROI crop when motion is detected in upper air space.
- **Tier 2 (Continuous Precision Interaction)**: $60\text{ FPS}$ full Neural Engine tracking activated during active manipulation, falling back to Tier 0 within $200\text{ms}$ of release.

---

## 📅 4. Implementation & Publication Milestones

| Phase | Milestone | Deliverable |
| :--- | :--- | :--- |
| **Phase 1** | **Dataset & Kinematic Telemetry** | Build an in-app telemetry recorder in GestureFlow to log 21-joint streams during (a) normal daily computer use and (b) target spatial tasks ($N=10$ subjects). |
| **Phase 2** | **Causal Intent & Pre-Click Model** | Train Causal TCN / Tiny-Mamba in PyTorch with InfoNCE hard-negative mining; export to CoreML `.mlpackage`; verify $<1\text{ms}$ inference on ANE. |
| **Phase 3** | **RL Neural Friction Controller** | Train PPO agent on simulated 2D Fitts' Law acquisition tasks; implement dynamic damping and magnetic snapping in Swift Quartz Core. |
| **Phase 4** | **System Integration & User Study** | Full integration into GestureFlow; run empirical user study comparing Physical Mouse vs. Raw Air-Pointer vs. Neural-Damped Spatial Pointer. |
| **Phase 5** | **Paper Drafting & Submission** | Target: **ACM UIST / ACM CHI / IEEE ISMAR**. |
