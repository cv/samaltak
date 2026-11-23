# GPU render-pass FFI pair (display CI only)

Use the display CI job (X11/Xvfb + lavapipe), never a local launch.
`GPUFFIRegressionTest` disables legacy fallbacks during successful candidate
calls and verifies lifecycle/status and read-back. The shared
`ffi-paired.py --display-ci` harness separately proves that every candidate
iteration enters both approved GPU targets (444 and 445).

The timing fixture in `ffi-paired-gpu.st` records a viewport and scissor with
identical arguments in both arms. It reuses one real device, pipeline and target.
Each arm gets an identically initialized render pass; clear/setup, submit and
idle wait are untimed. The measurement is CPU command encoding, not frame
throughput or GPU execution. No result is claimed without CI evidence.
