# GPU render-pass FFI workload (display CI only)

The display CI job (X11/Xvfb + lavapipe) runs `GPUFFIRegressionTest` for
lifecycle/status and pixel readback through the public GPU API. The
`ffi-paired.py --display-ci --proof-only` harness separately verifies that
each iteration enters both approved GPU targets (444 and 445).

The workload records viewport and scissor commands on a real render pass.
Setup, clear, submit and wait are not timed. A timing run compares CPU command
encoding on separate matched VM/image pairs, not GPU execution or frame rate.
