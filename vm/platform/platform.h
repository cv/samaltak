/* Samaltak platform layer: C internals (no oops). prims_platform.c wraps these
 * as primitives; tests/ call them directly. Handles are small positive ints
 * (0 = failure, see pf_last_error()). All functions run on the VM (main) thread. */
#ifndef SAMALTAK_PLATFORM_H
#define SAMALTAK_PLATFORM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* ---- VM hooks ---------------------------------------------------------- */
void platform_init(void);               /* idempotent */
void platform_poll(void);               /* at interrupt checks */
void platform_wait(int64_t timeout_us); /* idle; < 0 = forever */
void platform_shutdown(void);

/* VM services used by the platform (vm.h in the VM; stubs in tests) */
void signal_external_semaphore(int index);
void request_interrupt_check(void);
void request_periodic_poll(int64_t interval_us);

const char *pf_last_error(void);
void pf_set_error(const char *fmt, ...);
int64_t pf_now_ms(void); /* monotonic, ms since platform start */

/* ---- handle tables ----------------------------------------------------- */
typedef struct {
    int kind; /* 0 = free */
    void *ptr;
    int dev, w, h, fmt;
    int64_t i;
} pf_obj;
typedef struct {
    pf_obj *v;
    int n, cap, free_head;
} pf_table;
int pf_table_add(pf_table *t, int kind, void *ptr);
pf_obj *pf_table_get(pf_table *t, int h, int kind); /* kind < 0: any */
void pf_table_remove(pf_table *t, int h);
int pf_table_count(const pf_table *t, int kind); /* live handles; kind < 0: any */
/* live handles: files sockets windows gpuDevices shaders pipelines textures samplers buffers fences ptys */
#define PF_HANDLE_COUNTS 11
void pf_handle_counts(int64_t out[PF_HANDLE_COUNTS]);
int pf_file_handle_count(void);
int pf_socket_handle_count(void);
int pf_pty_handle_count(void);
int pf_window_handle_count(void);
void pf_gpu_handle_counts(int64_t out[7]); /* devices shaders pipelines textures samplers buffers fences */

/* ---- events ------------------------------------------------------------ */
enum {
    PF_EV_MOUSE_MOVE = 1, PF_EV_MOUSE_DOWN, PF_EV_MOUSE_UP, PF_EV_WHEEL,
    PF_EV_KEY_DOWN, PF_EV_KEY_UP, PF_EV_TEXT_INPUT, PF_EV_WINDOW_RESIZED,
    PF_EV_WINDOW_CLOSE_REQUEST, PF_EV_QUIT, PF_EV_FOCUS_GAINED, PF_EV_FOCUS_LOST,
    PF_EV_DISPLAY_SCALE_CHANGED, PF_EV_MOUSE_LEAVE, PF_EV_WINDOW_EXPOSED
};
enum { PF_MOD_SHIFT = 1, PF_MOD_CTRL = 2, PF_MOD_ALT = 4, PF_MOD_CMD = 8 };
enum { PF_X_NIL, PF_X_INT, PF_X_BOOL, PF_X_TEXT, PF_X_POINT }; /* textOrDelta kind */
typedef struct {
    int type;
    int64_t time_ms;
    double x, y;
    int64_t key; /* buttonOrKey */
    int mods;
    int xkind;
    int64_t ival;  /* PF_X_INT / PF_X_BOOL */
    double dx, dy; /* PF_X_POINT */
    char *text;    /* PF_X_TEXT, malloc'd */
    int window;    /* window handle, 0 = none */
} pf_event;
#define PF_EVENT_QUEUE_MAX 4096              /* queued events; 256 << k */
void pf_event_push(const pf_event *e);       /* copies text; drops the event if the queue is full */
bool pf_event_next(pf_event *out);           /* caller frees out->text */
int64_t pf_event_dropped(void);              /* events dropped since startup */
void pf_event_set_semaphore(int index);      /* 0 = none */
bool pf_vsync_semaphore(int index);          /* signaled once per display refresh; 0 = stop */
void pf_wake(void);                          /* any thread: end a platform_wait */

/* ---- windows ----------------------------------------------------------- */
enum { PF_WIN_HIDDEN = 1, PF_WIN_RESIZABLE = 2, PF_WIN_HIGH_DENSITY = 4 };
bool pf_video_init(void);
int pf_window_open(int w, int h, const char *title, int flags);
bool pf_window_close(int win);
bool pf_window_size(int win, int *w, int *h);
bool pf_window_pixel_size(int win, int *w, int *h);
double pf_window_display_scale(int win); /* < 0 on error */
double pf_window_refresh_rate(int win);  /* Hz, 0 if unknown, < 0 on error */
bool pf_window_set_title(int win, const char *title);
bool pf_window_show(int win, bool show);
void *pf_window_sdl(int win); /* SDL_Window* */
int pf_window_from_sdl_id(uint32_t id);
bool pf_window_is_hidden(int win);
bool pf_set_cursor(int kind);
char *pf_clipboard_get(void); /* malloc'd */
bool pf_clipboard_set(const char *s);

/* ---- GPU --------------------------------------------------------------- */
enum { PF_TEX_R8 = 1, PF_TEX_RGBA8 = 2, PF_TEX_BGRA8 = 3 };
enum { PF_TEXUSE_SAMPLER = 1, PF_TEXUSE_COLOR_TARGET = 2 };
enum { PF_BUFUSE_VERTEX = 1, PF_BUFUSE_INDEX = 2, PF_BUFUSE_STORAGE = 4 };
enum { PF_STAGE_VERTEX = 0, PF_STAGE_FRAGMENT = 1 };
enum { PF_BLEND_NONE = 0, PF_BLEND_ALPHA = 1, PF_BLEND_PREMULTIPLIED = 2 };
enum { PF_PRIM_TRIANGLES = 0, PF_PRIM_TRIANGLE_STRIP, PF_PRIM_LINES, PF_PRIM_LINE_STRIP, PF_PRIM_POINTS };
enum { PF_VA_FLOAT = 1, PF_VA_FLOAT2, PF_VA_FLOAT3, PF_VA_FLOAT4, PF_VA_UBYTE4_NORM, PF_VA_UBYTE4, PF_VA_UINT, PF_VA_INT };
typedef struct { int format, offset; } pf_vattr;

int pf_gpu_create_device(bool debug);
bool pf_gpu_claim_window(int dev, int win);
int pf_gpu_swapchain_format(int dev, int win); /* PF_TEX_*, 0 on error */
int pf_gpu_create_shader(int dev, const char *msl, const char *entry, int stage,
                         int samplers, int uniform_buffers, int storage_buffers, int storage_textures);
int pf_gpu_create_pipeline(int dev, int vs, int fs, int stride, const pf_vattr *attrs, int nattrs,
                           int prim, int blend, int target_format);
int pf_gpu_create_texture(int dev, int w, int h, int format, int usage);
int pf_gpu_create_sampler(int dev, bool linear, bool repeat);
int pf_gpu_create_buffer(int dev, int usage, uint32_t size);
bool pf_gpu_release(int h);
bool pf_gpu_upload_buffer(int buf, const void *data, uint32_t n, uint32_t dst_offset);
bool pf_gpu_upload_texture(int tex, const void *data, size_t len, int x, int y, int w, int h, int bytes_per_row);
int pf_gpu_acquire_cmd(int dev);
int pf_gpu_acquire_swapchain(int cmd, int win, int *w, int *h); /* 0: none available (not an error if no error set) */
int pf_gpu_begin_pass(int cmd, int tex, const float *clear_rgba /* NULL = load */);
bool pf_gpu_set_viewport(int pass, float x, float y, float w, float h);
bool pf_gpu_set_scissor(int pass, int x, int y, int w, int h);
bool pf_gpu_bind_pipeline(int pass, int pipe);
bool pf_gpu_bind_vertex_buffer(int pass, int slot, int buf, uint32_t offset);
bool pf_gpu_bind_texture(int pass, int slot, int tex, int sampler);
bool pf_gpu_push_uniforms(int cmd_or_pass, int stage, int slot, const void *data, uint32_t n);
bool pf_gpu_draw(int pass, int vertex_count, int first_vertex);
bool pf_gpu_end_pass(int pass);
bool pf_gpu_blit(int cmd, int src, const int src_rect[4], int dst, const int dst_rect[4], bool linear);
int pf_gpu_submit(int cmd, bool want_fence, bool *ok); /* fence handle or 0 */
bool pf_gpu_wait_fence(int fence);
int pf_gpu_fence_done(int fence); /* 1 done, 0 pending, -1 error */
int64_t pf_gpu_fence_elapsed(int fence);   /* µs from the fence's submit to its completion (stamped by a watcher thread); -1 pending, -2 bad handle */
bool pf_gpu_download(int tex, int x, int y, int w, int h, void *dst, size_t dst_len);
bool pf_gpu_texture_size(int tex, int *w, int *h, int *format);
bool pf_gpu_wait_idle(int dev);
int pf_gpu_bytes_per_pixel(int format);

/* ---- files & processes ------------------------------------------------- */
enum { PF_FILE_READ = 0, PF_FILE_READ_WRITE = 1, PF_FILE_APPEND = 2, PF_FILE_CREATE_TRUNCATE = 3 };
typedef struct { bool exists, is_dir; int64_t size, mtime_us; } pf_stat;
int pf_file_open(const char *path, int mode);
bool pf_file_close(int f);
int64_t pf_file_read(int f, void *buf, size_t n);         /* < 0 error */
int64_t pf_file_write(int f, const void *buf, size_t n);  /* < 0 error */
int64_t pf_file_write_behind(int f, const void *buf, size_t n); /* queued for a background thread: n, 0 if 3 writes are pending, < 0 error */
int64_t pf_file_size(int f);
int64_t pf_file_position(int f);
bool pf_file_seek(int f, int64_t pos);
bool pf_file_flush(int f);
bool pf_file_delete(const char *path);
bool pf_file_rename(const char *from, const char *to);
bool pf_file_stat(const char *path, pf_stat *st);
char **pf_dir_entries(const char *path, int *n); /* malloc'd array of malloc'd names */
bool pf_dir_create(const char *path);
char *pf_cwd(void); /* malloc'd */
bool pf_mkfifo(const char *path);
int64_t pf_spawn(char *const argv[]);          /* pid, < 0 error */
bool pf_process_wait(int64_t pid, bool block, int *status, bool *done);

/* ---- sockets (TCP, non-blocking) --------------------------------------- */
int pf_socket_listen(const char *host, int port, int backlog);
int pf_socket_connect(const char *host, int port);
int pf_socket_accept(int s, bool *would_block);             /* 0 + would_block = none pending */
int64_t pf_socket_recv(int s, void *buf, size_t n);         /* 0 EOF, -1 would block, -2 error */
int64_t pf_socket_send(int s, const void *buf, size_t n);   /* -1 would block, -2 error */
bool pf_socket_close(int s);
bool pf_socket_semaphores(int s, int read_index, int write_index);
int pf_socket_local_port(int s);
int pf_socket_poll_fds(void *pollfds, int max); /* internal: armed fds for platform_wait */
void pf_socket_poll(int timeout_ms);            /* internal: signal ready sockets */
bool pf_socket_any_armed(void);

/* ---- pseudo-terminals (master side non-blocking, polled like sockets) -- */
/* argv[0] is looked up in PATH; envp NULL = inherit (TERM=xterm-256color is set either way unless envp has TERM); cwd NULL = inherit */
int pf_pty_spawn(char *const argv[], char *const envp[], const char *cwd, int rows, int cols, int64_t *pid);
int64_t pf_pty_read(int p, void *buf, size_t n);         /* 0 EOF (child side closed), -1 would block, -2 error */
int64_t pf_pty_write(int p, const void *buf, size_t n);  /* -1 would block, -2 error */
bool pf_pty_resize(int p, int rows, int cols);
bool pf_pty_semaphores(int p, int read_index, int write_index);
bool pf_pty_wait(int p, bool block, int *status, bool *done); /* status as pf_process_wait */
bool pf_pty_close(int p);                                     /* hangs up the child (SIGHUP) unless it has ended */

/* internal: sockets and pty masters share one handle table and its polling */
enum { PF_FD_SOCKET = 1, PF_FD_PTY = 2 };
int pf_fd_add(int fd, int kind, void *ptr); /* 0 when full (fd left open) */
pf_obj *pf_fd_get(int h, int kind);
bool pf_fd_close(int h, int kind);

/* ---- cross-module internals -------------------------------------------- */
#define PF_POLL_US 1000           /* platform_poll cadence while Smalltalk runs and OS events or sockets may arrive */
void pf_update_poll_interval(void); /* after video init or socket semaphore changes */
bool pf_video_inited(void);
void pf_gpu_window_closing(int win);
void pf_windows_shutdown(void);
void pf_gpu_shutdown(void);
void pf_vsync_poll(void);
bool pf_vsync_pending(void);

#endif
