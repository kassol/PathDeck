# Performance Baseline — S28

> Date: 2026-06-18
> Environment: MacBook Pro M1 Max, macOS 26.5, Swift 6.3.2, Debug configuration

## Status

**性能未测，仅记录阈值和阻塞原因。**

Tests exist in `PathDeckTests/PerformanceTests.swift` (8 tests, 4×1k + 4×10k). Build passes. CLI execution blocked by LaunchServices limitation (Developer Mode / test runner cannot launch via `xcodebuild test`).

Actual timing values require Xcode GUI: Product → Test → select PerformanceTests. This document will be updated with real numbers when that run completes.

## Thresholds (model layer only, no view/scroll)

| Test | Scale | Threshold | Actual |
|------|-------|-----------|--------|
| coldOpen | 1,000 | < 1.0s | pending |
| sort (name) | 1,000 | < 0.2s | pending |
| sort (date) | 1,000 | < 0.2s | pending |
| filter | 1,000 | < 0.1s | pending |
| coldOpen | 10,000 | < 5.0s | pending |
| sort (name) | 10,000 | < 1.0s | pending |
| sort (date) | 10,000 | < 1.0s | pending |
| filter | 10,000 | < 0.5s | pending |

## Not Covered

- NSOutlineView scroll performance (requires Instruments / GUI test)
- Memory peak (requires Instruments profiling; PRD target: < 200MB for 10k)
- FSWatcher throughput under high event volume
