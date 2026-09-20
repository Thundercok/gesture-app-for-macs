# GestureFlow — Workspace Root Handoff Pointer

> **Primary Source Code Directory**: [`GestureFlowApp/`](file:///Users/thundercock2/Documents/antigravity/focused-davinci/GestureFlowApp/)  
> **Full Architecture & Technical Handoff**: See [`GestureFlowApp/HANDOFF.md`](file:///Users/thundercock2/Documents/antigravity/focused-davinci/GestureFlowApp/HANDOFF.md)  
> **Detailed Engineering Walkthrough**: See [`walkthrough.md`](file:///Users/thundercock2/.gemini/antigravity/brain/4e3b51a2-132a-4c72-9f7a-3c8fc8221ff4/walkthrough.md)

---

## Quick Reference for Incoming Agent / Claude

- **Production App Location**: `/Applications/GestureFlow.app`
- **Build & Verification Command**:
  ```bash
  cd GestureFlowApp
  swift build -c release
  ./.build/arm64-apple-macosx/release/GestureFlow --test-gates
  make run
  ```
- **Key Files**:
  - `GestureFlowApp/Sources/GestureFlow/Tracking/HandTracker.swift`: Vision hand tracking, 1€ smoothing, wrist synthesis, knuckle-relative finger extension, fused 3D normal / 2D planar palm facing metric, scale-adaptive clap detector.
  - `GestureFlowApp/Sources/GestureFlow/Tracking/GestureEngine.swift`: Intentionality gating state machine (Face exclusion, Palm orientation Schmitt trigger, Head-level depth-band).
  - `GestureFlowApp/Sources/GestureFlow/UI/HUDView.swift`: Mini Dynamic Pill and Expanded Spatial Inspector with 3-layer hardware compositor clipping (zero gray ghost boxes).
  - `GestureFlowApp/Sources/GestureFlow/UI/ApplicationSwitcherView.swift`: Full-screen switcher dock with catenary pearl tether physics and force-touch haptic detents.
  - `GestureFlowApp/Sources/GestureFlow/main.swift`: Window orchestration, bimanual zoom coordinator, and automated test suite (`--test-gates`).

*Please refer to [`GestureFlowApp/HANDOFF.md`](file:///Users/thundercock2/Documents/antigravity/focused-davinci/GestureFlowApp/HANDOFF.md) for the complete deep dive.*
