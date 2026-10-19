# Headless Replay Throughput Benchmark

## Measurement Scope
> [!IMPORTANT]
> This is a **real measurement** of pure code execution on local Apple Silicon hardware.
> It covers the cost of landmark feature extraction (`HandFeatureExtractor`) + gesture arbitration and engines (`GestureEngine`, `ScrollEngine`, `IntentArbiter`, `ActionSink`) per frame.
> It strictly **excludes** camera hardware capture, OS dispatch latency, and Apple Vision neural network inference.

## Environment
- **CPU / Platform**: `Apple M1`
- **OS Version**: macOS `26.5.2`
- **Git SHA**: `7193cb1a613ce84aaec2281ce787e08001e0e762`
- **Build Configuration**: `swift build -c release`
- **Test Command**: `python3 tools/bench_replay.py --frames 60000 --runs 5`

## Results

| Metric | Value |
| :--- | :--- |
| **Benchmark Frames** | 60,000 frames |
| **Iterations** | 5 runs |
| **Individual Runs (s)** | 9.3378s, 8.0047s, 7.9724s, 7.9964s, 7.9568s |
| **Median Wall Time** | **7.9964s** |
| **Mean Wall Time** | 8.2536s |
| **Throughput** | **7,503.4 frames/sec** |
| **Processing Cost** | **133.27 µs/frame** |

## Analysis
- Processing 60 FPS video stream takes approximately **7.996 ms** per second of video (< 0.1% of a single core).
- The tracking and arbitration pipeline operates at **125.1x real-time speed**.

