// Test kernels for System-NV (Tests-NV): tools/nv-test-kernels.sh compiles them for sm_121 into src/Tests-NV/NvTestKernels.st.
// Parameters are 32-bit unsigned counts and 64-bit pointers in the kernel's order (CUDA's ABI).

// c[i] = a[i] + b[i] for i < n.
extern "C" __global__ void vadd(const float *a, const float *b, float *c, unsigned n) {
  unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) c[i] = a[i] + b[i];
}

// p[i] = value for i < n.
extern "C" __global__ void fill(unsigned *p, unsigned value, unsigned n) {
  unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) p[i] = value;
}

// p[0..5] = blockDim.xyz, gridDim.xyz: checks the launch constants the driver puts in constant bank 0.
extern "C" __global__ void dims(unsigned *p) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    p[0] = blockDim.x; p[1] = blockDim.y; p[2] = blockDim.z; p[3] = gridDim.x; p[4] = gridDim.y; p[5] = gridDim.z;
  }
}

// dst[i] = src[i] for i < n, 16 bytes per thread: memory bandwidth.
extern "C" __global__ void __launch_bounds__(256) copy16(uint4 *dst, const uint4 *src, unsigned n) {
  unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) dst[i] = src[i];
}

// Reverses each block of 256 words of p in shared memory: shared memory and barriers.
extern "C" __global__ void __launch_bounds__(256) reverse256(unsigned *p) {
  __shared__ unsigned s[256];
  unsigned base = blockIdx.x * 256;
  s[threadIdx.x] = p[base + threadIdx.x];
  __syncthreads();
  p[base + threadIdx.x] = s[255 - threadIdx.x];
}

// p[i] = the sum of a 256-word local array filled from i, read in an order that depends on i (j := 5j + 1 mod 256
// visits every index): a 1 KB stack frame, local memory beyond the 16r240 bytes every thread has.
extern "C" __global__ void __launch_bounds__(256) local1k(unsigned *p, unsigned n) {
  unsigned a[256];
  unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
  for (int k = 0; k < 256; k++) a[k] = i * 3u + (unsigned)k;
  unsigned s = 0, j = i & 255;
  for (int k = 0; k < 256; k++) { s += a[j]; j = (j * 5 + 1) & 255; }
  if (i < n) p[i] = s;
}

__constant__ unsigned table[4] = {0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u};

// p[i] = table[i % 4] + i for i < n: a constant bank other than 0.
extern "C" __global__ void lookup(unsigned *p, unsigned n) {
  unsigned i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) p[i] = table[i & 3] + i;
}
