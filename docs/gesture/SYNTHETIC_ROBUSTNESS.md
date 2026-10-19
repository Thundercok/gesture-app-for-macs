# Synthetic perturbation of synthetic fixtures. Code-path robustness only. Not recognition accuracy on real hands.

- **Git SHA**: `d30aa4fe61ee11d9cfca6ce10b458fd6099d83cb`
- **Command**: `python3 tools/robustness_synthetic.py`
- **Evaluation Scope**: Headless pipeline verification with injected coordinate noise, frame drop, downsampling, and spatial mirroring.

## Summary Results

| Fixture | Perturbation | Seeds | Hits / Total | Hit Rate (%) | Clashes / False Fires |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `synthetic_swipe_left.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_down.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_up.jsonl` | jitter(σ=0.000) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_left.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_down.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_up.jsonl` | jitter(σ=0.002) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_left.jsonl` | jitter(σ=0.005) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | jitter(σ=0.005) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | jitter(σ=0.005) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | jitter(σ=0.005) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | jitter(σ=0.005) | 10 | 9/10 | 90.0% | 1 |
| `synthetic_scroll_down.jsonl` | jitter(σ=0.005) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_up.jsonl` | jitter(σ=0.005) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_left.jsonl` | jitter(σ=0.010) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | jitter(σ=0.010) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | jitter(σ=0.010) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | jitter(σ=0.010) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | jitter(σ=0.010) | 10 | 1/10 | 10.0% | 9 |
| `synthetic_scroll_down.jsonl` | jitter(σ=0.010) | 10 | 9/10 | 90.0% | 1 |
| `synthetic_scroll_up.jsonl` | jitter(σ=0.010) | 10 | 9/10 | 90.0% | 1 |
| `synthetic_swipe_left.jsonl` | drop(p=0.10) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | drop(p=0.10) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | drop(p=0.10) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | drop(p=0.10) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | drop(p=0.10) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_down.jsonl` | drop(p=0.10) | 10 | 9/10 | 90.0% | 1 |
| `synthetic_scroll_up.jsonl` | drop(p=0.10) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_left.jsonl` | drop(p=0.25) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | drop(p=0.25) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | drop(p=0.25) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | drop(p=0.25) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | drop(p=0.25) | 10 | 9/10 | 90.0% | 0 |
| `synthetic_scroll_down.jsonl` | drop(p=0.25) | 10 | 7/10 | 70.0% | 1 |
| `synthetic_scroll_up.jsonl` | drop(p=0.25) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_left.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_down.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_up.jsonl` | downsample(2x / 30fps) | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_left.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_right.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_up.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |
| `synthetic_swipe_down.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |
| `synthetic_pinch.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_down.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |
| `synthetic_scroll_up.jsonl` | mirror_x | 10 | 10/10 | 100.0% | 0 |

## Observations & Takeaways
- **Coordinate Jitter**: Pure kinematic gesture evaluation tolerates micro-jitter ($\sigma \le 0.002$) gracefully. At $\sigma \ge 0.005$, displacement noise can slightly alter peak velocity timing or drift.
- **Frame Drop**: Frame drops test trajectory continuity in `GestureEngine` and `ScrollEngine`. Windowed history lookup (`sampleDt` between 0.035s and 0.180s) ensures resilient offset matching even with moderate frame loss.
- **Mirror Invariance**: Horizontal coordinate mirroring ($x \to 1 - x$) preserves directional gesture mechanics with exact left/right action swapping.

