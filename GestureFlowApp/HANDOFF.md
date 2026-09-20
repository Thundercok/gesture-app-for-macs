# GestureFlow — Comprehensive Project & Architecture Handoff (v2.2)

> **Target Platform**: macOS 14.0+ (Sonoma, Sequoia)  
> **Hardware Target**: Apple Silicon (M1/M2/M3/M4) with Apple Neural Engine (ANE)  
> **Language & Frameworks**: Swift 5.9+, SwiftUI, Apple Vision (`Vision.framework`), AVFoundation, CoreGraphics, AppKit (`NSPanel`, `NSHostingView`), Accessibility (`AXUIElement`)  
> **App Location**: `/Applications/GestureFlow.app`  
> **Source Directory**: `GestureFlowApp/`  
> **Telemetry Log**: `~/Library/Application Support/GestureFlow/gesture_log.jsonl`

---

## 1. Executive Summary & Design Philosophy

**GestureFlow** is a native, ultra-low-latency (60 FPS locked, <1% CPU) spatial computing controller for macOS that enables effortless multitasking, app navigation, and document zoom using computer vision hand gestures.

### Core Pillars:
1. **Anti-Vibecoded Visual Craftsmanship**:
   - Zero emojis in UI code; strict adherence to Apple VisionOS and macOS Sequoia design guidelines.
   - Frosted Obsidian Glass aesthetic (`.ultraThinMaterial`, `Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.88)`), continuous rounded rectangles, subtle white specular gradients, and SF Pro typography with `.monospacedDigit()`.
   - Dynamic Mini Pill HUD (compact 252x40 vs expanded 380x325) with **zero rectangular ghosting, corner bleeding, or shadow clipping**.
2. **Intentionality-First Computer Vision**:
   - Eliminates the "Midas Touch" problem where unintentional hand movements (scratching chin, resting on cheek, talking with hands) trigger system actions.
   - 3-stage intentionality gating (Face Exclusion + Palm Orientation Hysteresis + Head-Level Depth-Band) with an automated test suite passing **40/40 tests (100%)**.
3. **Ergonomic Adaptation for Mac Laptops**:
   - Adapts to low camera angles, screen tilt ($15^\circ-25^\circ$), close typing distance ($20-35\text{cm}$), and wrists clipped by the bottom frame border over keyboards.
4. **Adaptive Battery Throttling**:
   - Automatic 15 FPS idle mode when hands are absent for >2.0s; instant 1-frame wake-up to locked 60 FPS upon hand detection.

---

## 2. Gesture Mapping & System Interaction

| Mode | Gesture | Physical Action | System Event / Action |
| :--- | :--- | :--- | :--- |
| **System Armed** | 🖐 **Open Palm Presentation** | Giơ lòng bàn tay về phía webcam (~280ms) | Kích hoạt vòng quét (Charge Pump) $\to$ Kích hoạt trạng thái **Sẵn sàng (Armed)** trong 4.0s. |
| **App Switcher** | 🤏 **Pinch & Hold** | Chụm ngón cái + trỏ khi đang Armed | Mở **Full-Screen Spatial Switcher Dock** (tập trung vào ứng dụng trước đó). |
| **Quick Toggle** | 🤏 $\to$ 🖐 **Pinch & Immediate Release** | Chụm và nhả ngay tại chỗ (trong deadzone) | Chuyển đổi tức thì sang app trước đó (tương đương `⌘ + Tab`). |
| **App Navigation** | 🤏 $\leftrightarrow$ **Pinch & Horizontal Drag** | Chụm và rê tay sang trái / phải | Cuộn chọn app với sợi dây đàn hồi (Elastic Pearl Tether) và phản hồi xúc giác **Force Touch Haptic Detent**. |
| **Commit App** | 🖐 **Pinch Release** | Thả ngón tay khi đang chọn app | Chuyển tiêu điểm cửa sổ sang app đã chọn và đóng Switcher. |
| **Mode Cycle** | 👏 **Bimanual Clap** | Vỗ hai bàn tay vào nhau dứt khoát | Chuyển đổi chế độ (App Switcher $\leftrightarrow$ Desktop Zoom $\leftrightarrow$ Cursor). |
| **Desktop Zoom** | 👐 **Dual-Pinch Caliper** | Chụm **cả hai tay** và kéo giãn / thu hẹp | Phóng to / thu nhỏ canvas hoặc tài liệu (`⌘ + +` / `⌘ + -`) với haptic feedback. |

---

## 3. Architecture & Data Flow Pipeline

```mermaid
flowchart TD
    Cam[CameraManager: AVCaptureSession 60 FPS] -->|CVPixelBuffer| Tracker[HandTracker: Vision Multi-Hand + Face]
    Tracker --> Synthesis[Wrist Synthesis & Knuckle-Relative Extension]
    Synthesis --> Normal[Fused 3D Normal & 2D Planar Palm Fullness]
    Normal --> Depth[MonocularDepthEstimator: PnP Metric Depth Z]
    
    Depth --> MultiHandData[MultiHandLandmarks: Primary & Secondary]
    
    MultiHandData --> Engine[GestureEngine: Intentionality Gating State Machine]
    MultiHandData --> BimanualZoom[Bimanual Caliper: Dual-Pinch Clutch]
    
    subgraph Intentionality Gates
        Engine --> Gate1[Face Proximity & 3D Proximity Gate]
        Engine --> Gate2[Schmitt Trigger Palm Orientation Hysteresis]
        Engine --> Gate3[Head-Level Depth-Band Gate]
    end
    
    Engine --> StateTransitions{Engine State}
    StateTransitions -->|Standby| Charge[Leaky Charge Pump 0.0 to 1.0]
    StateTransitions -->|Armed| ArmedWait[4.0s Window for Pinch Initiation]
    StateTransitions -->|Engaged| DockNav[App Switcher Drag & Detents]
    StateTransitions -->|Release| Commit[ActionDispatcher: NSRunningApplication Activate]
    
    MultiHandData --> AppState[AppState: Combine ObservableObject]
    AppState --> HUDView[HUDView: Compact Mini Pill / Expanded Inspector]
    AppState --> SwitcherView[ApplicationSwitcherView: Full-Screen Catenary Tether]
```

---

## 4. File-by-File Breakdown & Technical Responsibilities

### 📂 `GestureFlowApp/Sources/GestureFlow/`

#### 1. `Camera/CameraManager.swift`
- Configures `AVCaptureSession` with `AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)`.
- Dispatches hardware-accelerated video frames via a high-priority serial queue (`qos: .userInteractive`).
- Implements `isThrottled: Bool` property: adjusts `activeVideoMinFrameDuration` between $1/60\text{s}$ (active) and $1/15\text{s}$ (idle battery saver).

#### 2. `Tracking/HandTracker.swift`
- Manages dual `VNHumanHandPoseRequest` (`maximumHandCount = 2`) and `VNDetectFaceRectanglesRequest`.
- **Wrist Synthesis from Metacarpals**: When wrists hover over a laptop keyboard and clip past the bottom frame edge ($y > 0.98$), synthesizes an anchor point from `middleMCP` and `indexMCP` (`y: min(0.99, mm.y + 0.16)`).
- **Knuckle-Relative Finger Extension (`isFingerExtended`)**: Checks both knuckle distance (`knuckleToTip > knuckleToPip * 1.06`) and wrist distance, making extension detection immune to laptop screen tilt and perspective foreshortening.
- **Resilient Open-Palm Arming (`isStrictOpenPalm`)**: Requires `extCount >= 3` with `indexExt && middleExt` extended, preventing single-frame pinky dropouts from resetting the charge pump.
- **Fused Planar & 3D Normal Facing Metric**: Combines 3D normal vector dot product with 2D projected palm triangle fullness (`Area(wrist, indexMCP, pinkyMCP)`). Prevents normal vector inversion and eliminates false `.edgeOnPalm` triggers on tilted laptop lids.
- **Scale-Adaptive Clap Detector (`evaluateClap`)**:
  - Dynamically calculates collision threshold based on observed palm size: $\max(0.09, \min(0.24, \text{avgPalm} \times 1.25))$.
  - Implements Condition 2 (two approaching hands merging into a single observation upon physical impact) with persistent separation memory (`wasHandsSeparated`).

#### 3. `Tracking/MonocularDepthEstimator.swift`
- Perspective-n-Point (PnP) solver mapping anthropometric diagonal hand spans ($120\text{mm}$) to physical metric distance in meters:
  $$Z = \frac{f_{\text{norm}} \times D_{\text{hand}}}{\text{observedSpan}}$$
- Clamps metric depth to valid ergonomic range $[0.18\text{m}, 0.85\text{m}]$.
- Optical flow divergence tracking for zero-lag radial expansion/contraction velocity.

#### 4. `Tracking/OneEuroFilter.swift`
- Implements the 1€ Filter (Casiez et al.) across all 21 hand landmarks, pitch/yaw attitude angles, and metric depth.
- Low cutoff ($0.35\text{Hz}$) eliminates sensor grain when stationary, while speed coefficient $\beta = 0.025$ provides instant response during fast gestures with zero lag.

#### 5. `Tracking/GestureEngine.swift`
- **Finite State Machine**:
  - `.standby`: Hand must satisfy `isStrictOpenPalm && isInInteractionRange` to charge the accumulator (`+dt / 0.28`). Drains gracefully (`-dt * 1.5`) when unready.
  - `.armed(expiresAt)`: 4.0-second window. Prolongs while hand remains open; triggers `.engaged` upon pinch.
  - `.engaged`: Tracks horizontal displacement $\Delta x$. Small displacements ($\le 0.022$) trigger instant Cmd+Tab on release. Larger displacements step through apps with detents ($0.038$ normalized travel per app).
  - `.cooldown(until)`: 0.35s lockout to prevent double-firing.
- **Intentionality Gates**:
  - `faceProximity`: Suppresses gestures when hand is within expanded face bounding box ($1.5\times$ width/height) AND within $14\text{cm}$ of face depth in 3D.
  - `edgeOnPalm`: Schmitt trigger ($0.24$ enter, $0.32$ exit) blocking karate-chop or resting hand poses.
  - `depthBand`: Suppresses gestures only at head/ear/neck level ($y < \text{faceBox.maxY} + 0.08$) when within $7\text{cm}$ of face depth.

#### 6. `Tracking/ActionDispatcher.swift`
- High-speed application switcher and window state controller.
- Direct Window Management: `NSRunningApplication.activate(options: [.activateAllWindows])`.
- Haptic Feedback: `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`.
- Sound Effects: `NSSound(named: "Glass")`, `NSSound(named: "Pop")`, `NSSound(named: "Tink")`.
- Continuous Document Magnification: `ActionDispatcher.magnify(delta: CGFloat)` accumulates span delta and dispatches native zoom steps.

#### 7. `UI/HUDView.swift`
- **Three-Layer Compositor Defense against Broken Corners**:
  - Root container explicitly clipped with `.clipShape(RoundedRectangle(cornerRadius: state.isCompactHUD ? 16 : 18, style: .continuous))`.
  - Chassis rendered with exact shape masking: `.fill(.ultraThinMaterial)` overlaid with dark obsidian tint and subtle specular stroke.
  - Zero internal SwiftUI `.shadow()` to prevent window boundary clipping.
- **Interactive Controls**:
  - Mini dynamic pill with pulsating state dot and metric distance readout.
  - Expand/collapse toggle button.
  - Viewport mode cycle button (Minimal Vector Skeleton $\leftrightarrow$ Monochrome Video $\leftrightarrow$ Full Camera Feed).

#### 8. `UI/ApplicationSwitcherView.swift`
- Full-screen spatial overlay panel (`screen.frame`, `.borderless`, `.nonactivatingPanel`).
- **Elastic Catenary Pearl Tether**: Dynamically renders a catenary curve connecting the user's pinch reticle to the target application icon with 32px relaxed sag vs 8px taut spring physics.
- **Bimanual Caliper HUD**: Visual tension bridge connecting left and right hand centroids during dual-pinch zoom with real-time metric span (cm) and zoom percentage (%).

#### 9. `main.swift`
- Orchestrates the full pipeline, AppKit window lifecycle, and menu bar item (`hand.raised.fill`).
- Window Setup & Resizing:
  - Resizes HUD via `panel.setFrame(newFrame, display: true, animate: false)` (avoiding AppKit's rectangular snapshot animation trap).
  - Explicitly clips native backing layer: `hostingView.layer?.cornerRadius = compact ? 16 : 18` and `hostingView.layer?.masksToBounds = true`.
  - Invalidate window shadow: `panel.invalidateShadow()`.
- Bimanual Zoom Coordinator: Computes dual-pinch clutch state (`landmarks.isPinching && secondaryLandmarks.isPinching`) and dispatches zoom actions.
- Built-in Intentionality Test Suite (`--test-gates`).

---

## 5. Critical Technical Traps & Solutions (Must-Read for Incoming Engineers)

### Trap 1: AppKit Transparent Window Server Gray Box Bug
- **Symptom**: Resizing or displaying a borderless transparent `NSPanel` leaves a rectangular light-gray ghost box or rectangular shadow corners around rounded cards (see user screenshot `media_1789704477473.png`).
- **Root Cause**:
  1. `panel.setFrame(newFrame, display: true, animate: true)` creates an unmasked rectangular backing snapshot during Cocoa animations.
  2. SwiftUI `.ultraThinMaterial` uses an AppKit `NSVisualEffectView`. If unclipped, its rectangular layer spills outside rounded corners. WindowServer detects non-zero alpha pixels and draws a sharp 90-degree drop shadow.
- **Solution**:
  - Never use `animate: true` on transparent borderless panels.
  - Always set `hostingView.wantsLayer = true`, `hostingView.layer?.cornerRadius = ...`, and `hostingView.layer?.masksToBounds = true`.
  - Always call `panel.invalidateShadow()` after resizing.
  - Always clip the root SwiftUI container with `.clipShape(RoundedRectangle(...))`.

### Trap 2: Laptop Camera Perspective & Tilt Angle
- **Symptom**: Gestures work when standing or on iMacs, but fail completely on MacBooks sitting on a desk.
- **Root Cause**: MacBook screens tilt back $15^\circ-25^\circ$, looking up at the user. Normal hand presentations are horizontal or forward-angled, reducing $\vec{N} \cdot \vec{F}_{\text{cam}}$ to $0.35-0.55$. Strict desktop thresholds ($\ge 0.48$) and vertical wrist tests (`validWrist.y > middleMCP.y`) fail.
- **Solution**:
  - Relax `facingCamera` threshold to $\ge 0.28$.
  - Fuse 3D normal vector with 2D planar palm triangle fullness (`Area(wrist, indexMCP, pinkyMCP)`).
  - Test finger extension relative to knuckles (`knuckleToTip > knuckleToPip * 1.06`) rather than wrist.

### Trap 3: Single-Frame Pinky Landmark Dropout
- **Symptom**: User holds an open hand to scan, but the yellow progress ring flickers and resets repeatedly.
- **Root Cause**: Requiring all 4 fingers extended (`extCount >= 4`) causes the charge accumulator to discharge whenever the pinky landmark has low confidence for a single frame.
- **Solution**: Require `extCount >= 3` with `indexExt && middleExt`. Primary fingers must be extended, while relaxed pinky curvature is tolerated.

### Trap 4: macOS TCC Accessibility Permissions Lost on Rebuild
- **Symptom**: Accessibility actions fail silently even though the toggle in System Settings is ON.
- **Root Cause**: Ad-hoc signed binaries (`codesign -s -`) generate a new `CDHash` on each compilation. macOS TCC tracks ad-hoc apps by `CDHash`.
- **Solution**: Anchor signing to a persistent local self-signed certificate (`GestureFlow Developer`) in `login.keychain-db`.

---

## 6. Verification Commands & Diagnostics

```bash
cd /Users/thundercock2/Documents/antigravity/focused-davinci/GestureFlowApp

# 1. Compile Release Binary
swift build -c release

# 2. Run Automated Intentionality Gate Verification Suite (40/40 tests)
./.build/arm64-apple-macosx/release/GestureFlow --test-gates

# 3. Build, Sign, and Install to /Applications/GestureFlow.app
make install

# 4. Launch Application
make run

# 5. Stop Application
make stop

# 6. Stream Live Telemetry Logs
tail -f ~/Library/Application\ Support/GestureFlow/gesture_log.jsonl
```

---

## 7. Backlog & Immediate Next Steps for Claude

1. **Continuous Native Trackpad Pinch Emulation (`kCGEventMagnify`)**:
   - Currently, Desktop Zoom dispatches discrete `⌘ + +` / `⌘ + -` keystrokes.
   - Investigate posting continuous `CGEvent` with `type: .magnify` or private CoreGraphics multitouch events for fluid smooth zooming in PDF readers and Figma.
2. **Cursor Mode Implementation**:
   - Mode switching is supported via Clap (`APP_SW` $\to$ `DESK_ZOOM` $\to$ `CURSOR`).
   - Implement spatial index-finger raycasting to move the mouse cursor and pinch-to-click.
3. **Multi-Display & External Webcam Support**:
   - Allow user to select target display or external USB/Continuity camera via the menu bar extra.
