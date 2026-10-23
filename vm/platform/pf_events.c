/* Event queue (OS + injected events), VM poll/wait hooks.
 *
 * One FIFO holds translated SDL events and injected ones, so remote input is
 * indistinguishable from real input. The input semaphore is signaled once when
 * events are pending and re-armed by every pf_event_next call. The FIFO holds at
 * most PF_EVENT_QUEUE_MAX events; further events are dropped and counted. */
#include "platform.h"

#include <SDL3/SDL.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static pf_event *q;
static int q_head, q_len, q_cap;
static int64_t q_dropped;
static int input_sem;
static bool input_armed = true;
static uint64_t last_pump_ns;
static double mouse_x, mouse_y;
static _Atomic uint32_t wake_event;
static atomic_bool in_wait;
static int w_pipe[2] = {-1, -1}; /* wakes the headless poll and stops the watcher */

void platform_init(void)
{
    static bool done;
    if (done) return;
    done = true;
    signal(SIGPIPE, SIG_IGN); /* broken sockets/FIFOs report EPIPE instead */
    pf_now_ms();
    if (pipe(w_pipe) == 0) {
        fcntl(w_pipe[0], F_SETFL, O_NONBLOCK);
        fcntl(w_pipe[1], F_SETFL, O_NONBLOCK);
    }
}

/* any thread: end a platform_wait in progress */
void pf_wake(void)
{
    if (!atomic_load(&in_wait)) return;
    uint32_t t = atomic_load(&wake_event);
    if (t) {
        SDL_Event e = {0};
        e.type = t;
        SDL_PushEvent(&e);
    }
    (void)!write(w_pipe[1], "w", 1);
}

static void drain_pipe(void)
{
    char buf[64];
    while (read(w_pipe[0], buf, sizeof buf) > 0) {}
}

void pf_event_push(const pf_event *e)
{
    pf_event *n = NULL;
    char *text = NULL;
    if (q_len == q_cap) {
        int cap = q_cap ? q_cap * 2 : 256;
        if (cap > PF_EVENT_QUEUE_MAX || !(n = malloc(sizeof *n * cap))) {
            q_dropped++;
            return;
        }
        for (int i = 0; i < q_len; i++) n[i] = q[(q_head + i) % q_cap];
        free(q);
        q = n;
        q_cap = cap;
        q_head = 0;
    }
    if (e->xkind == PF_X_TEXT && !(text = strdup(e->text ? e->text : ""))) {
        q_dropped++;
        return;
    }
    pf_event *d = &q[(q_head + q_len++) % q_cap];
    *d = *e;
    d->text = text;
}

int64_t pf_event_dropped(void) { return q_dropped; }

bool pf_event_next(pf_event *out)
{
    input_armed = true;
    if (!q_len) return false;
    *out = q[q_head];
    q_head = (q_head + 1) % q_cap;
    q_len--;
    return true;
}

void pf_event_set_semaphore(int index)
{
    input_sem = index;
    input_armed = true;
}

static int mods_of(SDL_Keymod m)
{
    return ((m & SDL_KMOD_SHIFT) ? PF_MOD_SHIFT : 0) | ((m & SDL_KMOD_CTRL) ? PF_MOD_CTRL : 0) |
           ((m & SDL_KMOD_ALT) ? PF_MOD_ALT : 0) | ((m & SDL_KMOD_GUI) ? PF_MOD_CMD : 0);
}

static void translate(const SDL_Event *e)
{
    pf_event ev = {0};
    uint64_t now = SDL_GetTicksNS();
    ev.time_ms = pf_now_ms() - (int64_t)((now > e->common.timestamp ? now - e->common.timestamp : 0) / 1000000);
    ev.mods = mods_of(SDL_GetModState());
    ev.x = mouse_x;
    ev.y = mouse_y;
    switch (e->type) {
    case SDL_EVENT_MOUSE_MOTION:
        ev.type = PF_EV_MOUSE_MOVE;
        ev.x = mouse_x = e->motion.x;
        ev.y = mouse_y = e->motion.y;
        ev.key = e->motion.state;
        ev.window = pf_window_from_sdl_id(e->motion.windowID);
        break;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
        ev.type = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN ? PF_EV_MOUSE_DOWN : PF_EV_MOUSE_UP;
        ev.x = mouse_x = e->button.x;
        ev.y = mouse_y = e->button.y;
        ev.key = e->button.button;
        ev.xkind = PF_X_INT;
        ev.ival = e->button.clicks;
        ev.window = pf_window_from_sdl_id(e->button.windowID);
        break;
    case SDL_EVENT_MOUSE_WHEEL: {
        double s = e->wheel.direction == SDL_MOUSEWHEEL_FLIPPED ? -1 : 1;
        ev.type = PF_EV_WHEEL;
        ev.x = mouse_x = e->wheel.mouse_x;
        ev.y = mouse_y = e->wheel.mouse_y;
        ev.xkind = PF_X_POINT;
        ev.dx = s * e->wheel.x;
        ev.dy = s * e->wheel.y;
        ev.window = pf_window_from_sdl_id(e->wheel.windowID);
        break;
    }
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
        ev.type = e->type == SDL_EVENT_KEY_DOWN ? PF_EV_KEY_DOWN : PF_EV_KEY_UP;
        ev.key = e->key.key;
        ev.mods = mods_of(e->key.mod);
        ev.xkind = PF_X_BOOL;
        ev.ival = e->key.repeat;
        ev.window = pf_window_from_sdl_id(e->key.windowID);
        break;
    case SDL_EVENT_TEXT_INPUT:
        ev.type = PF_EV_TEXT_INPUT;
        ev.xkind = PF_X_TEXT;
        ev.text = (char *)e->text.text;
        ev.window = pf_window_from_sdl_id(e->text.windowID);
        break;
    case SDL_EVENT_QUIT:
        ev.type = PF_EV_QUIT;
        break;
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
    case SDL_EVENT_WINDOW_FOCUS_LOST:
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
    case SDL_EVENT_WINDOW_MOUSE_LEAVE:
    case SDL_EVENT_WINDOW_EXPOSED:
        ev.window = pf_window_from_sdl_id(e->window.windowID);
        switch (e->type) {
        case SDL_EVENT_WINDOW_RESIZED:
            ev.type = PF_EV_WINDOW_RESIZED;
            ev.x = e->window.data1;
            ev.y = e->window.data2;
            break;
        case SDL_EVENT_WINDOW_CLOSE_REQUESTED: ev.type = PF_EV_WINDOW_CLOSE_REQUEST; break;
        case SDL_EVENT_WINDOW_FOCUS_GAINED: ev.type = PF_EV_FOCUS_GAINED; break;
        case SDL_EVENT_WINDOW_FOCUS_LOST: ev.type = PF_EV_FOCUS_LOST; break;
        case SDL_EVENT_WINDOW_MOUSE_LEAVE: ev.type = PF_EV_MOUSE_LEAVE; break;
        case SDL_EVENT_WINDOW_EXPOSED: ev.type = PF_EV_WINDOW_EXPOSED; break;
        default:
            ev.type = PF_EV_DISPLAY_SCALE_CHANGED;
            ev.x = pf_window_display_scale(ev.window);
            ev.y = 0;
            break;
        }
        break;
    default:
        return; /* includes wake_event */
    }
    pf_event_push(&ev);
}

static void pump(void)
{
    if (!pf_video_inited()) return;
    SDL_Event e;
    SDL_PumpEvents();
    while (SDL_PeepEvents(&e, 1, SDL_GETEVENT, SDL_EVENT_FIRST, SDL_EVENT_LAST) > 0) translate(&e);
    last_pump_ns = SDL_GetTicksNS();
}

static void signal_ready(void)
{
    pf_vsync_poll();
    if (q_len && input_sem && input_armed) {
        input_armed = false;
        signal_external_semaphore(input_sem);
    }
}

void pf_update_poll_interval(void) { request_periodic_poll(pf_video_inited() || pf_socket_any_armed() ? PF_POLL_US : 0); }

void platform_poll(void)
{
    /* Pumping Cocoa costs tens of µs; at most once per ms is plenty for input. */
    if (pf_video_inited() && SDL_GetTicksNS() - last_pump_ns >= 1000000) pump();
    if (pf_socket_any_armed()) pf_socket_poll(0);
    signal_ready();
}

/* While the VM thread sleeps in SDL_WaitEventTimeout, this thread poll()s the
 * armed sockets and wakes SDL by pushing wake_event. */
static pthread_t watcher;
static pthread_mutex_t w_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t w_cv = PTHREAD_COND_INITIALIZER;
static int w_state; /* 0 idle, 1 requested, 2 polling */
static struct pollfd w_fds[129];
static int w_nfds;
static bool w_started;
static atomic_bool w_stop;

static void *watch_main(void *arg)
{
    (void)arg;
    for (;;) {
        pthread_mutex_lock(&w_mu);
        while (w_state != 1) pthread_cond_wait(&w_cv, &w_mu);
        w_state = 2;
        pthread_mutex_unlock(&w_mu);
        /* w_stop is set before the stop byte is written, so a drained stop
         * byte is always followed by seeing w_stop */
        while (!atomic_load(&w_stop)) {
            int r = poll(w_fds, w_nfds, -1);
            bool sock = false;
            for (int i = 1; r > 0 && i < w_nfds; i++) sock |= w_fds[i].revents != 0;
            if (sock) {
                SDL_Event e = {0};
                e.type = atomic_load(&wake_event);
                SDL_PushEvent(&e);
                break;
            }
            drain_pipe(); /* stop request or a stray pf_wake byte */
        }
        pthread_mutex_lock(&w_mu);
        w_state = 0;
        pthread_cond_broadcast(&w_cv);
        pthread_mutex_unlock(&w_mu);
    }
    return NULL;
}

static bool watcher_start(void)
{
    if (!w_started) {
        if (w_pipe[0] < 0 || pthread_create(&watcher, NULL, watch_main, NULL) != 0) return false;
        w_started = true;
    }
    w_fds[0] = (struct pollfd){.fd = w_pipe[0], .events = POLLIN};
    w_nfds = 1 + pf_socket_poll_fds(&w_fds[1], 128);
    atomic_store(&w_stop, false);
    pthread_mutex_lock(&w_mu);
    w_state = 1;
    pthread_cond_broadcast(&w_cv);
    pthread_mutex_unlock(&w_mu);
    return true;
}

static void watcher_stop(void)
{
    atomic_store(&w_stop, true);
    (void)!write(w_pipe[1], "x", 1);
    pthread_mutex_lock(&w_mu);
    while (w_state != 0) pthread_cond_wait(&w_cv, &w_mu);
    pthread_mutex_unlock(&w_mu);
}

void platform_wait(int64_t timeout_us)
{
    platform_init();
    pump();
    if (pf_video_inited() && !atomic_load(&wake_event)) atomic_store(&wake_event, SDL_RegisterEvents(1));
    atomic_store(&in_wait, true);
    if (q_len || pf_vsync_pending()) timeout_us = 0;
    int ms = timeout_us < 0 ? -1 : (int)((timeout_us + 999) / 1000);
    bool socks = pf_socket_any_armed();
    if (!pf_video_inited()) {
        struct pollfd p[129] = {{.fd = w_pipe[0], .events = POLLIN}};
        int n = 1 + (socks ? pf_socket_poll_fds(&p[1], 128) : 0);
        if (ms != 0) poll(p, n, ms);
    } else {
        bool watching = socks && watcher_start();
        if (ms != 0) SDL_WaitEventTimeout(NULL, ms);
        if (watching) watcher_stop();
        pump();
    }
    atomic_store(&in_wait, false);
    drain_pipe();
    if (socks) pf_socket_poll(0);
    signal_ready();
}

void platform_shutdown(void)
{
    pf_gpu_shutdown();
    pf_windows_shutdown();
    if (pf_video_inited()) SDL_Quit();
}
