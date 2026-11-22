extern "C" __global__ void add1(const float* a, float* b, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) b[i] = a[i] + 1.0f;
}
extern "C" __global__ void blocksum(const float* a, float* out) {
  __shared__ float s[256];
  s[threadIdx.x] = a[blockIdx.x * 256 + threadIdx.x];
  __syncthreads();
  for (int k = 128; k > 0; k >>= 1) { if (threadIdx.x < k) s[threadIdx.x] += s[threadIdx.x + k]; __syncthreads(); }
  if (threadIdx.x == 0) out[blockIdx.x] = s[0];
}
extern "C" __global__ void dims(unsigned* o) {
  extern __shared__ unsigned dyn[];
  o[0] = blockDim.x; o[1] = blockDim.y; o[2] = blockDim.z; o[3] = gridDim.x; o[4] = gridDim.y; o[5] = gridDim.z;
  unsigned s; asm("mov.u32 %0, %%dynamic_smem_size;" : "=r"(s)); o[6] = s;
  unsigned t; asm("mov.u32 %0, %%total_smem_size;" : "=r"(t)); o[7] = t;
  o[8] = (unsigned)(unsigned long long)dyn;
}
