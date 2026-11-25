// A frame's launches as stream launches or as a CUDA graph replayed with new parameters (tests/nv/README.md):
// the decision NvComputeGPU's frames rest on (docs/nv-gpu.md, Small frames). A frame is N small raster_fill kernels
// (an ordinary damaged frame: 5-12 launches) then a fence write, frames 2 ms apart; per frame, the CPU time to issue it
// and the GPU span (events around it), medians of 300.
//   graph_bench <cubin> [launches]
#include <cuda.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>
#include "../../gpu/nv/raster_abi.h"

#define CK(x) do { CUresult r_ = (x); if (r_ != CUDA_SUCCESS) { const char *s; cuGetErrorString(r_, &s); fprintf(stderr, "%s: %s\n", #x, s); exit(1); } } while (0)

static double now() { return std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
static double median(std::vector<double> v) { std::sort(v.begin(), v.end()); return v[v.size() / 2]; }

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: graph_bench <cubin> [launches]\n"); return 2; }
	int n = argc > 2 ? atoi(argv[2]) : 8;
	CK(cuInit(0));
	CUdevice dev; CK(cuDeviceGet(&dev, 0));
	CUcontext ctx; CK(cuDevicePrimaryCtxRetain(&ctx, dev)); CK(cuCtxSetCurrent(ctx));
	FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long size = ftell(f); fseek(f, 0, SEEK_SET);
	std::vector<char> cubin(size); fread(cubin.data(), 1, size, f); fclose(f);
	CUmodule m; CK(cuModuleLoadData(&m, cubin.data()));
	CUfunction fill; CK(cuModuleGetFunction(&fill, m, "raster_fill"));
	CUdeviceptr px, fence; CK(cuMemAlloc(&px, 1 << 20)); CK(cuMemAlloc(&fence, 64));
	CUstream s; CK(cuStreamCreate(&s, CU_STREAM_NON_BLOCKING));
	CUevent e0, e1; CK(cuEventCreate(&e0, 0)); CK(cuEventCreate(&e1, 0));
	std::vector<RasterFillParams> ps(n);
	for (int i = 0; i < n; i++) ps[i] = RasterFillParams{px + (CUdeviceptr)i * 16384, 4096, 4, (uint32_t)i};
	auto launch = [&](int i) {
		size_t sz = sizeof(RasterFillParams);
		void *extra[] = {CU_LAUNCH_PARAM_BUFFER_POINTER, &ps[i], CU_LAUNCH_PARAM_BUFFER_SIZE, &sz, CU_LAUNCH_PARAM_END};
		CK(cuLaunchKernel(fill, 16, 1, 1, 256, 1, 1, 0, s, nullptr, extra));
	};
	// the graph: captured once from the stream
	CUgraph g; CUgraphExec ge;
	CK(cuStreamBeginCapture(s, CU_STREAM_CAPTURE_MODE_GLOBAL));
	for (int i = 0; i < n; i++) launch(i);
	CK(cuStreamEndCapture(s, &g));
	CK(cuGraphInstantiate(&ge, g, 0));
	size_t count = 0; CK(cuGraphGetNodes(g, nullptr, &count));
	std::vector<CUgraphNode> nodes(count); CK(cuGraphGetNodes(g, nodes.data(), &count));
	std::vector<CUDA_KERNEL_NODE_PARAMS> kp(count);
	for (size_t i = 0; i < count; i++) CK(cuGraphKernelNodeGetParams(nodes[i], &kp[i]));
	const char *names[] = {"stream launches", "graph, parameters set per node", "graph as captured"};
	uint64_t v = 0;
	for (int mode = 0; mode < 3; mode++) {
		std::vector<double> cpu, gpu;
		for (int frame = 0; frame < 330; frame++) {
			std::this_thread::sleep_for(std::chrono::milliseconds(2));
			for (int i = 0; i < n; i++) ps[i].value = frame * 31 + i;
			double t = now();
			CK(cuEventRecord(e0, s));
			if (mode == 0) for (int i = 0; i < n; i++) launch(i);
			else {
				if (mode == 1) for (size_t i = 0; i < count; i++) {
					void *args[] = {&ps[i]};
					CUDA_KERNEL_NODE_PARAMS q = kp[i];
					q.kernelParams = args; q.extra = nullptr;
					CK(cuGraphExecKernelNodeSetParams(ge, nodes[i], &q));
				}
				CK(cuGraphLaunch(ge, s));
			}
			CK(cuEventRecord(e1, s));
			CK(cuStreamWriteValue64(s, fence, ++v, 0));
			double issued = now() - t;
			CK(cuEventSynchronize(e1));
			float ms; CK(cuEventElapsedTime(&ms, e0, e1));
			if (frame >= 30) { cpu.push_back(issued); gpu.push_back(ms * 1000); }
		}
		printf("%-32s %d kernels: CPU %.1f us to issue, GPU %.1f us (medians)\n", names[mode], n, median(cpu), median(gpu));
	}
	return 0;
}
