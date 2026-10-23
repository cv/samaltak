/* Thin SDL_GPU wrapper with integer handles.
 *
 * Uploads are batched: each device keeps one open copy pass on its own command
 * buffer and one growing transfer buffer; the batch is submitted right before
 * the next gpuSubmit/gpuDownload, so uploads execute before any command buffer
 * submitted after them. */
#include "platform.h"

#include <SDL3/SDL.h>
#include <pthread.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

enum { K_DEV = 1, K_SHADER, K_PIPE, K_TEX, K_SAMPLER, K_BUF, K_CMD, K_PASS, K_FENCE, K_SWAP };

#define MAX_CLAIMS 16
typedef struct {
    SDL_GPUDevice *dev;
    SDL_GPUTransferBuffer *up_tb;
    uint32_t up_cap, up_used;
    SDL_GPUCommandBuffer *up_cmd;
    SDL_GPUCopyPass *up_pass;
    SDL_GPUTransferBuffer *down_tb;
    uint32_t down_cap;
    int claimed[MAX_CLAIMS];
} gpu_dev;

static pf_table objs;

static pf_obj *get(int h, int kind, const char *what)
{
    pf_obj *o = pf_table_get(&objs, h, kind);
    if (!o) pf_set_error("bad %s handle %d", what, h);
    return o;
}

static gpu_dev *dev_of(pf_obj *o) { return pf_table_get(&objs, o->dev, K_DEV)->ptr; }

/* Metal shader compile errors go to the SDL log, not SDL_GetError: keep the last one. */
static char log_error[2048];
static SDL_LogOutputFunction default_log;

static void capture_log(void *ud, int category, SDL_LogPriority prio, const char *msg)
{
    if (prio >= SDL_LOG_PRIORITY_ERROR) SDL_strlcpy(log_error, msg, sizeof log_error);
    default_log(ud, category, prio, msg);
}

static int sdl_fail(const char *what)
{
    const char *e = SDL_GetError();
    pf_set_error("%s: %s", what, *e ? e : log_error);
    return 0;
}

int pf_gpu_bytes_per_pixel(int format) { return format == PF_TEX_R8 ? 1 : 4; }

static SDL_GPUTextureFormat sdl_format(int f)
{
    switch (f) {
    case PF_TEX_R8: return SDL_GPU_TEXTUREFORMAT_R8_UNORM;
    case PF_TEX_RGBA8: return SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
    case PF_TEX_BGRA8: return SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM;
    default: return SDL_GPU_TEXTUREFORMAT_INVALID;
    }
}

int pf_gpu_create_device(bool debug)
{
    platform_init();
    if (!pf_video_init()) return 0; /* SDL_CreateGPUDevice needs the video subsystem */
    if (!default_log) {
        default_log = SDL_GetDefaultLogOutputFunction();
        SDL_SetLogOutputFunction(capture_log, NULL);
    }
    gpu_dev *d = calloc(1, sizeof *d);
    if (!d) return pf_set_error("out of memory"), 0;
    d->dev = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL, debug, NULL);
    if (!d->dev) {
        free(d);
        return sdl_fail("SDL_CreateGPUDevice");
    }
    int h = pf_table_add(&objs, K_DEV, d);
    objs.v[h].dev = h;
    return h;
}

static gpu_dev *dev_get(int h)
{
    pf_obj *o = get(h, K_DEV, "device");
    return o ? o->ptr : NULL;
}

bool pf_gpu_claim_window(int dev, int win)
{
    gpu_dev *d = dev_get(dev);
    SDL_Window *w = pf_window_sdl(win);
    if (!d || !w) return false;
    int slot = -1;
    for (int i = 0; i < MAX_CLAIMS; i++) {
        if (d->claimed[i] == win) return true;
        if (!d->claimed[i] && slot < 0) slot = i;
    }
    if (slot < 0) return pf_set_error("too many claimed windows"), false;
    if (!SDL_ClaimWindowForGPUDevice(d->dev, w)) return sdl_fail("SDL_ClaimWindowForGPUDevice");
    /* Never block the VM thread on vsync: Metal offers IMMEDIATE (no display
     * sync; the macOS compositor still prevents visible tearing). */
    SDL_GPUPresentMode mode = SDL_GPU_PRESENTMODE_VSYNC;
    if (SDL_WindowSupportsGPUPresentMode(d->dev, w, SDL_GPU_PRESENTMODE_MAILBOX)) mode = SDL_GPU_PRESENTMODE_MAILBOX;
    else if (SDL_WindowSupportsGPUPresentMode(d->dev, w, SDL_GPU_PRESENTMODE_IMMEDIATE)) mode = SDL_GPU_PRESENTMODE_IMMEDIATE;
    if (!SDL_SetGPUSwapchainParameters(d->dev, w, SDL_GPU_SWAPCHAINCOMPOSITION_SDR, mode))
        return sdl_fail("SDL_SetGPUSwapchainParameters");
    d->claimed[slot] = win;
    return true;
}

void pf_gpu_window_closing(int win)
{
    for (int h = 1; h < objs.n; h++) {
        if (objs.v[h].kind != K_DEV) continue;
        gpu_dev *d = objs.v[h].ptr;
        for (int i = 0; i < MAX_CLAIMS; i++)
            if (d->claimed[i] == win) {
                SDL_WaitForGPUIdle(d->dev);
                SDL_ReleaseWindowFromGPUDevice(d->dev, pf_window_sdl(win));
                d->claimed[i] = 0;
            }
    }
}

int pf_gpu_swapchain_format(int dev, int win)
{
    gpu_dev *d = dev_get(dev);
    SDL_Window *w = pf_window_sdl(win);
    if (!d || !w) return 0;
    SDL_GPUTextureFormat f = SDL_GetGPUSwapchainTextureFormat(d->dev, w);
    for (int i = PF_TEX_R8; i <= PF_TEX_BGRA8; i++)
        if (sdl_format(i) == f) return i;
    pf_set_error("unsupported swapchain format %d", (int)f);
    return 0;
}

int pf_gpu_create_shader(int dev, const char *msl, const char *entry, int stage, int samplers,
                         int uniform_buffers, int storage_buffers, int storage_textures)
{
    gpu_dev *d = dev_get(dev);
    if (!d) return 0;
    SDL_GPUShaderCreateInfo ci = {
        .code_size = strlen(msl),
        .code = (const Uint8 *)msl,
        .entrypoint = entry,
        .format = SDL_GPU_SHADERFORMAT_MSL,
        .stage = stage == PF_STAGE_FRAGMENT ? SDL_GPU_SHADERSTAGE_FRAGMENT : SDL_GPU_SHADERSTAGE_VERTEX,
        .num_samplers = samplers,
        .num_storage_textures = storage_textures,
        .num_storage_buffers = storage_buffers,
        .num_uniform_buffers = uniform_buffers,
    };
    SDL_ClearError();
    log_error[0] = 0;
    SDL_GPUShader *s = SDL_CreateGPUShader(d->dev, &ci);
    if (!s) return sdl_fail("SDL_CreateGPUShader");
    int h = pf_table_add(&objs, K_SHADER, s);
    objs.v[h].dev = dev;
    return h;
}

static SDL_GPUVertexElementFormat va_format(int f)
{
    switch (f) {
    case PF_VA_FLOAT: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT;
    case PF_VA_FLOAT2: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2;
    case PF_VA_FLOAT3: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
    case PF_VA_FLOAT4: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4;
    case PF_VA_UBYTE4_NORM: return SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM;
    case PF_VA_UBYTE4: return SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4;
    case PF_VA_UINT: return SDL_GPU_VERTEXELEMENTFORMAT_UINT;
    case PF_VA_INT: return SDL_GPU_VERTEXELEMENTFORMAT_INT;
    default: return SDL_GPU_VERTEXELEMENTFORMAT_INVALID;
    }
}

int pf_gpu_create_pipeline(int dev, int vs, int fs, int stride, const pf_vattr *attrs, int nattrs,
                           int prim, int blend, int target_format)
{
    gpu_dev *d = dev_get(dev);
    pf_obj *v = get(vs, K_SHADER, "vertex shader"), *f = get(fs, K_SHADER, "fragment shader");
    if (!d || !v || !f) return 0;
    if (nattrs < 0 || nattrs > 16) return pf_set_error("bad attribute count"), 0;
    if (!sdl_format(target_format)) return pf_set_error("bad target format %d", target_format), 0;
    static const SDL_GPUPrimitiveType prims[] = {
        SDL_GPU_PRIMITIVETYPE_TRIANGLELIST, SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP, SDL_GPU_PRIMITIVETYPE_LINELIST,
        SDL_GPU_PRIMITIVETYPE_LINESTRIP, SDL_GPU_PRIMITIVETYPE_POINTLIST};
    if (prim < 0 || prim > PF_PRIM_POINTS) return pf_set_error("bad primitive type %d", prim), 0;
    SDL_GPUVertexAttribute va[16];
    for (int i = 0; i < nattrs; i++) {
        va[i] = (SDL_GPUVertexAttribute){.location = i, .buffer_slot = 0, .format = va_format(attrs[i].format),
                                         .offset = attrs[i].offset};
        if (!va[i].format) return pf_set_error("bad vertex format %d", attrs[i].format), 0;
    }
    SDL_GPUVertexBufferDescription vb = {.slot = 0, .pitch = stride, .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX};
    SDL_GPUColorTargetDescription ct = {.format = sdl_format(target_format)};
    if (blend != PF_BLEND_NONE) {
        SDL_GPUBlendFactor src = blend == PF_BLEND_ALPHA ? SDL_GPU_BLENDFACTOR_SRC_ALPHA : SDL_GPU_BLENDFACTOR_ONE;
        ct.blend_state = (SDL_GPUColorTargetBlendState){
            .src_color_blendfactor = src,
            .dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
            .enable_blend = true,
        };
    }
    SDL_GPUGraphicsPipelineCreateInfo ci = {
        .vertex_shader = v->ptr,
        .fragment_shader = f->ptr,
        .vertex_input_state = {.vertex_buffer_descriptions = &vb, .num_vertex_buffers = nattrs ? 1 : 0,
                               .vertex_attributes = va, .num_vertex_attributes = nattrs},
        .primitive_type = prims[prim],
        .rasterizer_state = {.fill_mode = SDL_GPU_FILLMODE_FILL, .cull_mode = SDL_GPU_CULLMODE_NONE},
        .target_info = {.color_target_descriptions = &ct, .num_color_targets = 1},
    };
    SDL_GPUGraphicsPipeline *p = SDL_CreateGPUGraphicsPipeline(d->dev, &ci);
    if (!p) return sdl_fail("SDL_CreateGPUGraphicsPipeline");
    int h = pf_table_add(&objs, K_PIPE, p);
    objs.v[h].dev = dev;
    return h;
}

int pf_gpu_create_texture(int dev, int w, int h, int format, int usage)
{
    gpu_dev *d = dev_get(dev);
    if (!d) return 0;
    if (w <= 0 || h <= 0 || !sdl_format(format) || !(usage & 3)) return pf_set_error("bad texture parameters"), 0;
    SDL_GPUTextureCreateInfo ci = {
        .type = SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_format(format),
        .usage = ((usage & PF_TEXUSE_SAMPLER) ? SDL_GPU_TEXTUREUSAGE_SAMPLER : 0) |
                 ((usage & PF_TEXUSE_COLOR_TARGET) ? SDL_GPU_TEXTUREUSAGE_COLOR_TARGET : 0),
        .width = w,
        .height = h,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    SDL_GPUTexture *t = SDL_CreateGPUTexture(d->dev, &ci);
    if (!t) return sdl_fail("SDL_CreateGPUTexture");
    int th = pf_table_add(&objs, K_TEX, t);
    pf_obj *o = &objs.v[th];
    o->dev = dev, o->w = w, o->h = h, o->fmt = format, o->i = usage;
    return th;
}

int pf_gpu_create_sampler(int dev, bool linear, bool repeat)
{
    gpu_dev *d = dev_get(dev);
    if (!d) return 0;
    SDL_GPUFilter f = linear ? SDL_GPU_FILTER_LINEAR : SDL_GPU_FILTER_NEAREST;
    SDL_GPUSamplerAddressMode a = repeat ? SDL_GPU_SAMPLERADDRESSMODE_REPEAT : SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    SDL_GPUSamplerCreateInfo ci = {.min_filter = f, .mag_filter = f, .mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
                                   .address_mode_u = a, .address_mode_v = a, .address_mode_w = a};
    SDL_GPUSampler *s = SDL_CreateGPUSampler(d->dev, &ci);
    if (!s) return sdl_fail("SDL_CreateGPUSampler");
    int h = pf_table_add(&objs, K_SAMPLER, s);
    objs.v[h].dev = dev;
    return h;
}

int pf_gpu_create_buffer(int dev, int usage, uint32_t size)
{
    gpu_dev *d = dev_get(dev);
    if (!d) return 0;
    if (usage != PF_BUFUSE_VERTEX || size == 0) return pf_set_error("bad buffer parameters"), 0;
    SDL_GPUBufferCreateInfo ci = {.usage = SDL_GPU_BUFFERUSAGE_VERTEX, .size = size};
    SDL_GPUBuffer *b = SDL_CreateGPUBuffer(d->dev, &ci);
    if (!b) return sdl_fail("SDL_CreateGPUBuffer");
    int h = pf_table_add(&objs, K_BUF, b);
    objs.v[h].dev = dev;
    objs.v[h].i = size;
    return h;
}

/* ---- uploads ------------------------------------------------------------ */

static void up_flush(gpu_dev *d)
{
    if (!d->up_cmd) return;
    SDL_EndGPUCopyPass(d->up_pass);
    SDL_SubmitGPUCommandBuffer(d->up_cmd);
    d->up_cmd = NULL;
    d->up_pass = NULL;
    d->up_used = 0;
}

/* Map n bytes of the batch transfer buffer; caller fills, then calls
 * SDL_UnmapGPUTransferBuffer and records the copy on d->up_pass. */
static uint8_t *up_reserve(gpu_dev *d, uint32_t n, uint32_t *off)
{
    uint32_t need = (n + 15) & ~15u;
    if (d->up_used + need > d->up_cap) {
        up_flush(d);
        if (need > d->up_cap) {
            uint32_t cap = 1u << 22;
            while (cap < need) cap <<= 1;
            if (d->up_tb) SDL_ReleaseGPUTransferBuffer(d->dev, d->up_tb);
            SDL_GPUTransferBufferCreateInfo ci = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = cap};
            d->up_tb = SDL_CreateGPUTransferBuffer(d->dev, &ci);
            d->up_cap = d->up_tb ? cap : 0;
            if (!d->up_tb) return sdl_fail("SDL_CreateGPUTransferBuffer"), NULL;
        }
    }
    if (!d->up_cmd) {
        d->up_cmd = SDL_AcquireGPUCommandBuffer(d->dev);
        if (!d->up_cmd) return sdl_fail("SDL_AcquireGPUCommandBuffer"), NULL;
        d->up_pass = SDL_BeginGPUCopyPass(d->up_cmd);
    }
    /* cycle at the start of a batch: the previous batch may still be in flight */
    uint8_t *p = SDL_MapGPUTransferBuffer(d->dev, d->up_tb, d->up_used == 0);
    if (!p) return sdl_fail("SDL_MapGPUTransferBuffer"), NULL;
    *off = d->up_used;
    d->up_used += need;
    return p + *off;
}

bool pf_gpu_upload_buffer(int buf, const void *data, uint32_t n, uint32_t dst_offset)
{
    pf_obj *o = get(buf, K_BUF, "buffer");
    if (!o) return false;
    if (n == 0) return true;
    if ((uint64_t)dst_offset + n > (uint64_t)o->i) return pf_set_error("upload out of buffer bounds"), false;
    gpu_dev *d = dev_of(o);
    uint32_t off;
    uint8_t *p = up_reserve(d, n, &off);
    if (!p) return false;
    memcpy(p, data, n);
    SDL_UnmapGPUTransferBuffer(d->dev, d->up_tb);
    SDL_UploadToGPUBuffer(d->up_pass, &(SDL_GPUTransferBufferLocation){d->up_tb, off},
                          &(SDL_GPUBufferRegion){o->ptr, dst_offset, n}, false);
    return true;
}

bool pf_gpu_upload_texture(int tex, const void *data, size_t len, int x, int y, int w, int h, int bytes_per_row)
{
    pf_obj *o = get(tex, K_TEX, "texture");
    if (!o) return false;
    int bpp = pf_gpu_bytes_per_pixel(o->fmt);
    size_t row = (size_t)w * bpp;
    if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > o->w || y + h > o->h || (size_t)bytes_per_row < row ||
        len < (size_t)(h - 1) * bytes_per_row + row)
        return pf_set_error("bad texture upload region"), false;
    gpu_dev *d = dev_of(o);
    uint32_t off;
    uint8_t *p = up_reserve(d, (uint32_t)(row * h), &off);
    if (!p) return false;
    if ((size_t)bytes_per_row == row) memcpy(p, data, row * h);
    else
        for (int r = 0; r < h; r++) memcpy(p + r * row, (const uint8_t *)data + (size_t)r * bytes_per_row, row);
    SDL_UnmapGPUTransferBuffer(d->dev, d->up_tb);
    SDL_UploadToGPUTexture(d->up_pass, &(SDL_GPUTextureTransferInfo){d->up_tb, off, w, h},
                           &(SDL_GPUTextureRegion){.texture = o->ptr, .x = x, .y = y, .w = w, .h = h, .d = 1}, false);
    return true;
}

/* ---- command buffers and passes ----------------------------------------- */

int pf_gpu_acquire_cmd(int dev)
{
    gpu_dev *d = dev_get(dev);
    if (!d) return 0;
    SDL_GPUCommandBuffer *c = SDL_AcquireGPUCommandBuffer(d->dev);
    if (!c) return sdl_fail("SDL_AcquireGPUCommandBuffer");
    int h = pf_table_add(&objs, K_CMD, c);
    objs.v[h].dev = dev;
    return h;
}

int pf_gpu_acquire_swapchain(int cmd, int win, int *w, int *h)
{
    pf_obj *c = get(cmd, K_CMD, "command buffer");
    SDL_Window *sw = pf_window_sdl(win);
    pf_set_error("");
    if (!c || !sw) return 0;
    if (pf_window_is_hidden(win)) return 0;
    SDL_GPUTexture *t = NULL;
    Uint32 tw = 0, th = 0;
    if (!SDL_AcquireGPUSwapchainTexture(c->ptr, sw, &t, &tw, &th)) return sdl_fail("SDL_AcquireGPUSwapchainTexture");
    if (!t) return 0; /* too many frames in flight: try again later */
    int dev = c->dev;
    int fmt = pf_gpu_swapchain_format(dev, win);
    int sh = pf_table_add(&objs, K_SWAP, t);
    pf_obj *o = &objs.v[sh];
    o->dev = dev, o->w = tw, o->h = th, o->fmt = fmt, o->i = cmd;
    *w = tw, *h = th;
    return sh;
}

static pf_obj *target_get(int tex)
{
    pf_obj *o = pf_table_get(&objs, tex, -1);
    if (!o || (o->kind != K_TEX && o->kind != K_SWAP)) {
        pf_set_error("bad texture handle %d", tex);
        return NULL;
    }
    return o;
}

int pf_gpu_begin_pass(int cmd, int tex, const float *clear)
{
    pf_obj *c = get(cmd, K_CMD, "command buffer"), *t = target_get(tex);
    if (!c || !t) return 0;
    SDL_GPUColorTargetInfo ci = {.texture = t->ptr, .load_op = clear ? SDL_GPU_LOADOP_CLEAR : SDL_GPU_LOADOP_LOAD,
                                 .store_op = SDL_GPU_STOREOP_STORE};
    if (clear) ci.clear_color = (SDL_FColor){clear[0], clear[1], clear[2], clear[3]};
    SDL_GPURenderPass *p = SDL_BeginGPURenderPass(c->ptr, &ci, 1, NULL);
    if (!p) return sdl_fail("SDL_BeginGPURenderPass");
    int h = pf_table_add(&objs, K_PASS, p);
    objs.v[h].dev = c->dev;
    objs.v[h].i = cmd;
    return h;
}

#define PASS(var, h)                                     \
    pf_obj *var##_o = get(h, K_PASS, "render pass");      \
    if (!var##_o) return false;                          \
    SDL_GPURenderPass *var = var##_o->ptr

bool pf_gpu_set_viewport(int pass, float x, float y, float w, float h)
{
    PASS(p, pass);
    SDL_SetGPUViewport(p, &(SDL_GPUViewport){x, y, w, h, 0, 1});
    return true;
}

bool pf_gpu_set_scissor(int pass, int x, int y, int w, int h)
{
    PASS(p, pass);
    SDL_SetGPUScissor(p, &(SDL_Rect){x, y, w, h});
    return true;
}

bool pf_gpu_bind_pipeline(int pass, int pipe)
{
    PASS(p, pass);
    pf_obj *o = get(pipe, K_PIPE, "pipeline");
    if (!o) return false;
    SDL_BindGPUGraphicsPipeline(p, o->ptr);
    return true;
}

bool pf_gpu_bind_vertex_buffer(int pass, int slot, int buf, uint32_t offset)
{
    PASS(p, pass);
    pf_obj *o = get(buf, K_BUF, "buffer");
    if (!o) return false;
    SDL_BindGPUVertexBuffers(p, slot, &(SDL_GPUBufferBinding){o->ptr, offset}, 1);
    return true;
}

bool pf_gpu_bind_texture(int pass, int slot, int tex, int sampler)
{
    PASS(p, pass);
    pf_obj *t = get(tex, K_TEX, "texture"), *s = get(sampler, K_SAMPLER, "sampler");
    if (!t || !s) return false;
    SDL_BindGPUFragmentSamplers(p, slot, &(SDL_GPUTextureSamplerBinding){t->ptr, s->ptr}, 1);
    return true;
}

bool pf_gpu_push_uniforms(int cmd_or_pass, int stage, int slot, const void *data, uint32_t n)
{
    pf_obj *o = pf_table_get(&objs, cmd_or_pass, -1);
    if (o && o->kind == K_PASS) o = pf_table_get(&objs, (int)o->i, K_CMD);
    if (!o || o->kind != K_CMD) return pf_set_error("bad command buffer handle %d", cmd_or_pass), false;
    if (stage == PF_STAGE_FRAGMENT) SDL_PushGPUFragmentUniformData(o->ptr, slot, data, n);
    else SDL_PushGPUVertexUniformData(o->ptr, slot, data, n);
    return true;
}

bool pf_gpu_draw(int pass, int vertex_count, int first_vertex)
{
    PASS(p, pass);
    SDL_DrawGPUPrimitives(p, vertex_count, 1, first_vertex, 0);
    return true;
}

bool pf_gpu_end_pass(int pass)
{
    PASS(p, pass);
    SDL_EndGPURenderPass(p);
    pf_table_remove(&objs, pass);
    return true;
}

bool pf_gpu_blit(int cmd, int src, const int sr[4], int dst, const int dr[4], bool linear)
{
    pf_obj *c = get(cmd, K_CMD, "command buffer"), *s = get(src, K_TEX, "texture"), *t = target_get(dst);
    if (!c || !s || !t) return false;
    bool full = dr[0] == 0 && dr[1] == 0 && dr[2] == t->w && dr[3] == t->h;
    SDL_GPUBlitInfo bi = {
        .source = {.texture = s->ptr, .x = sr[0], .y = sr[1], .w = sr[2], .h = sr[3]},
        .destination = {.texture = t->ptr, .x = dr[0], .y = dr[1], .w = dr[2], .h = dr[3]},
        .load_op = full ? SDL_GPU_LOADOP_DONT_CARE : SDL_GPU_LOADOP_LOAD,
        .filter = linear ? SDL_GPU_FILTER_LINEAR : SDL_GPU_FILTER_NEAREST,
    };
    SDL_BlitGPUTexture(c->ptr, &bi);
    return true;
}

/* Fence timing: a watcher thread polls the pending fences (SDL_QueryGPUFence reads the completion state) every
   200 µs while any are pending and stamps when each completed, so callers learn the submit-to-completion time of a
   fence without blocking or spinning on the VM thread. Entries are indexed by fence handle. */
typedef struct { SDL_GPUFence *f; SDL_GPUDevice *d; int64_t submit_us, done_us; bool active; } fence_watch;
static fence_watch *watches;
static int nwatches, npending;
static pthread_mutex_t watch_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t watch_cond = PTHREAD_COND_INITIALIZER;
static bool watcher_started;

static int64_t mono_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static void *fence_watcher(void *unused)
{
    pthread_mutex_lock(&watch_lock);
    for (;;) {
        while (npending == 0) pthread_cond_wait(&watch_cond, &watch_lock);
        for (int i = 0; i < nwatches; i++) {
            fence_watch *w = &watches[i];
            if (w->active && SDL_QueryGPUFence(w->d, w->f)) {
                w->done_us = mono_us();
                w->active = false;
                npending--;
            }
        }
        pthread_mutex_unlock(&watch_lock);
        struct timespec nap = {0, 200000};
        nanosleep(&nap, NULL);
        pthread_mutex_lock(&watch_lock);
    }
    return NULL;
}

static void watch_fence(int h, SDL_GPUFence *f, SDL_GPUDevice *d)
{
    pthread_mutex_lock(&watch_lock);
    if (h >= nwatches) {
        int n = h + 64;
        fence_watch *nw = realloc(watches, (size_t)n * sizeof *nw);
        if (!nw) { pthread_mutex_unlock(&watch_lock); return; }
        memset(nw + nwatches, 0, (size_t)(n - nwatches) * sizeof *nw);
        watches = nw;
        nwatches = n;
    }
    if (watches[h].active) npending--;
    watches[h] = (fence_watch){f, d, mono_us(), -1, true};
    npending++;
    if (!watcher_started) {
        pthread_t t;
        if (pthread_create(&t, NULL, fence_watcher, NULL) == 0) { pthread_detach(t); watcher_started = true; }
    }
    pthread_cond_signal(&watch_cond);
    pthread_mutex_unlock(&watch_lock);
}

static void unwatch_fence(int h)
{
    pthread_mutex_lock(&watch_lock);
    if (h < nwatches) {
        if (watches[h].active) npending--;
        watches[h] = (fence_watch){0};
    }
    pthread_mutex_unlock(&watch_lock);
}

int64_t pf_gpu_fence_elapsed(int fence)
{
    if (!get(fence, K_FENCE, "fence")) return -2;
    int64_t r = -1;
    pthread_mutex_lock(&watch_lock);
    if (fence < nwatches && watches[fence].f && watches[fence].done_us >= 0) r = watches[fence].done_us - watches[fence].submit_us;
    pthread_mutex_unlock(&watch_lock);
    return r;
}

int pf_gpu_submit(int cmd, bool want_fence, bool *ok)
{
    pf_obj *c = get(cmd, K_CMD, "command buffer");
    *ok = false;
    if (!c) return 0;
    up_flush(dev_of(c));
    SDL_GPUCommandBuffer *cb = c->ptr;
    int dev = c->dev;
    for (int h = 1; h < objs.n; h++)
        if ((objs.v[h].kind == K_SWAP || objs.v[h].kind == K_PASS) && objs.v[h].i == cmd) pf_table_remove(&objs, h);
    pf_table_remove(&objs, cmd);
    if (!want_fence) {
        if (!SDL_SubmitGPUCommandBuffer(cb)) return sdl_fail("SDL_SubmitGPUCommandBuffer");
        *ok = true;
        return 0;
    }
    SDL_GPUFence *f = SDL_SubmitGPUCommandBufferAndAcquireFence(cb);
    if (!f) return sdl_fail("SDL_SubmitGPUCommandBufferAndAcquireFence");
    int h = pf_table_add(&objs, K_FENCE, f);
    objs.v[h].dev = dev;
    watch_fence(h, f, dev_of(&objs.v[h])->dev);
    *ok = true;
    return h;
}

bool pf_gpu_wait_fence(int fence)
{
    pf_obj *o = get(fence, K_FENCE, "fence");
    if (!o) return false;
    SDL_GPUFence *f = o->ptr;
    return SDL_WaitForGPUFences(dev_of(o)->dev, true, &f, 1) || sdl_fail("SDL_WaitForGPUFences");
}

int pf_gpu_fence_done(int fence)
{
    pf_obj *o = get(fence, K_FENCE, "fence");
    if (!o) return -1;
    return SDL_QueryGPUFence(dev_of(o)->dev, o->ptr) ? 1 : 0;
}

bool pf_gpu_download(int tex, int x, int y, int w, int h, void *dst, size_t dst_len)
{
    pf_obj *o = get(tex, K_TEX, "texture");
    if (!o) return false;
    int bpp = pf_gpu_bytes_per_pixel(o->fmt);
    size_t n = (size_t)w * h * bpp;
    if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > o->w || y + h > o->h || dst_len < n)
        return pf_set_error("bad download region"), false;
    gpu_dev *d = dev_of(o);
    up_flush(d);
    if (n > d->down_cap) {
        if (d->down_tb) SDL_ReleaseGPUTransferBuffer(d->dev, d->down_tb);
        SDL_GPUTransferBufferCreateInfo ci = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD, .size = (Uint32)n};
        d->down_tb = SDL_CreateGPUTransferBuffer(d->dev, &ci);
        d->down_cap = d->down_tb ? (uint32_t)n : 0;
        if (!d->down_tb) return sdl_fail("SDL_CreateGPUTransferBuffer");
    }
    SDL_GPUCommandBuffer *cb = SDL_AcquireGPUCommandBuffer(d->dev);
    if (!cb) return sdl_fail("SDL_AcquireGPUCommandBuffer");
    SDL_GPUCopyPass *cp = SDL_BeginGPUCopyPass(cb);
    SDL_DownloadFromGPUTexture(cp, &(SDL_GPUTextureRegion){.texture = o->ptr, .x = x, .y = y, .w = w, .h = h, .d = 1},
                               &(SDL_GPUTextureTransferInfo){d->down_tb, 0, w, h});
    SDL_EndGPUCopyPass(cp);
    SDL_GPUFence *f = SDL_SubmitGPUCommandBufferAndAcquireFence(cb);
    if (!f) return sdl_fail("SDL_SubmitGPUCommandBufferAndAcquireFence");
    SDL_WaitForGPUFences(d->dev, true, &f, 1);
    SDL_ReleaseGPUFence(d->dev, f);
    const uint8_t *p = SDL_MapGPUTransferBuffer(d->dev, d->down_tb, false);
    if (!p) return sdl_fail("SDL_MapGPUTransferBuffer");
    if (o->fmt == PF_TEX_BGRA8) {
        const uint32_t *s = (const uint32_t *)p;
        uint32_t *t = dst;
        for (size_t i = 0; i < n / 4; i++) {
            uint32_t v = s[i];
            t[i] = (v & 0xFF00FF00u) | ((v >> 16) & 0xFF) | ((v & 0xFF) << 16);
        }
    } else memcpy(dst, p, n);
    SDL_UnmapGPUTransferBuffer(d->dev, d->down_tb);
    return true;
}

bool pf_gpu_texture_size(int tex, int *w, int *h, int *format)
{
    pf_obj *o = target_get(tex);
    if (!o) return false;
    *w = o->w, *h = o->h, *format = o->fmt;
    return true;
}

bool pf_gpu_wait_idle(int dev)
{
    gpu_dev *d = dev_get(dev);
    if (!d) return false;
    up_flush(d);
    return SDL_WaitForGPUIdle(d->dev) || sdl_fail("SDL_WaitForGPUIdle");
}

/* ---- release ------------------------------------------------------------ */

static void release_obj(int h)
{
    pf_obj *o = &objs.v[h];
    SDL_GPUDevice *dv = dev_of(o)->dev;
    switch (o->kind) {
    case K_SHADER: SDL_ReleaseGPUShader(dv, o->ptr); break;
    case K_PIPE: SDL_ReleaseGPUGraphicsPipeline(dv, o->ptr); break;
    case K_TEX: SDL_ReleaseGPUTexture(dv, o->ptr); break;
    case K_SAMPLER: SDL_ReleaseGPUSampler(dv, o->ptr); break;
    case K_BUF: SDL_ReleaseGPUBuffer(dv, o->ptr); break;
    case K_FENCE: unwatch_fence(h); SDL_ReleaseGPUFence(dv, o->ptr); break;
    case K_CMD:
        SDL_CancelGPUCommandBuffer(o->ptr);
        for (int i = 1; i < objs.n; i++)
            if ((objs.v[i].kind == K_SWAP || objs.v[i].kind == K_PASS) && objs.v[i].i == h) pf_table_remove(&objs, i);
        break;
    default: break;
    }
    pf_table_remove(&objs, h);
}

static void release_device(int dh)
{
    gpu_dev *d = objs.v[dh].ptr;
    up_flush(d);
    SDL_WaitForGPUIdle(d->dev);
    for (int h = 1; h < objs.n; h++)
        if (h != dh && objs.v[h].kind && objs.v[h].dev == dh) release_obj(h);
    for (int i = 0; i < MAX_CLAIMS; i++)
        if (d->claimed[i]) SDL_ReleaseWindowFromGPUDevice(d->dev, pf_window_sdl(d->claimed[i]));
    if (d->up_tb) SDL_ReleaseGPUTransferBuffer(d->dev, d->up_tb);
    if (d->down_tb) SDL_ReleaseGPUTransferBuffer(d->dev, d->down_tb);
    SDL_DestroyGPUDevice(d->dev);
    free(d);
    pf_table_remove(&objs, dh);
}

bool pf_gpu_release(int h)
{
    pf_obj *o = pf_table_get(&objs, h, -1);
    if (!o) return pf_set_error("bad GPU handle %d", h), false;
    if (o->kind == K_PASS || o->kind == K_SWAP) return pf_set_error("pass/swapchain handles end with their command buffer"), false;
    if (o->kind == K_DEV) release_device(h);
    else release_obj(h);
    return true;
}

void pf_gpu_shutdown(void)
{
    for (int h = 1; h < objs.n; h++)
        if (objs.v[h].kind == K_DEV) release_device(h);
}

void pf_gpu_handle_counts(int64_t out[7])
{
    static const int kinds[7] = {K_DEV, K_SHADER, K_PIPE, K_TEX, K_SAMPLER, K_BUF, K_FENCE};
    for (int i = 0; i < 7; i++) out[i] = pf_table_count(&objs, kinds[i]);
}
