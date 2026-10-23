/* SDL3 windows, cursor, clipboard. */
#include "platform.h"

#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>

enum { K_WINDOW = 1 };
static pf_table windows;
static bool video_ok;
static SDL_Cursor *cursors[SDL_SYSTEM_CURSOR_COUNT];

bool pf_video_init(void)
{
    if (video_ok) return true;
    SDL_SetHint(SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE, "0");
    SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        pf_set_error("SDL_Init: %s", SDL_GetError());
        return false;
    }
    video_ok = true;
    pf_update_poll_interval();
    return true;
}

bool pf_video_inited(void) { return video_ok; }

static SDL_Window *win_get(int win)
{
    pf_obj *o = pf_table_get(&windows, win, K_WINDOW);
    if (!o) pf_set_error("bad window handle %d", win);
    return o ? o->ptr : NULL;
}

void *pf_window_sdl(int win) { return win_get(win); }

int pf_window_open(int w, int h, const char *title, int flags)
{
    if (!pf_video_init()) return 0;
    SDL_WindowFlags f = 0;
    if (flags & PF_WIN_HIDDEN) f |= SDL_WINDOW_HIDDEN;
    if (flags & PF_WIN_RESIZABLE) f |= SDL_WINDOW_RESIZABLE;
    if (flags & PF_WIN_HIGH_DENSITY) f |= SDL_WINDOW_HIGH_PIXEL_DENSITY;
    SDL_Window *sw = SDL_CreateWindow(title ? title : "", w, h, f);
    if (!sw) {
        pf_set_error("SDL_CreateWindow: %s", SDL_GetError());
        return 0;
    }
    SDL_StartTextInput(sw);
    int handle = pf_table_add(&windows, K_WINDOW, sw);
    windows.v[handle].i = SDL_GetWindowID(sw);
    return handle;
}

bool pf_window_close(int win)
{
    SDL_Window *sw = win_get(win);
    if (!sw) return false;
    pf_gpu_window_closing(win);
    SDL_StopTextInput(sw);
    SDL_DestroyWindow(sw);
    pf_table_remove(&windows, win);
    return true;
}

int pf_window_from_sdl_id(uint32_t id)
{
    for (int h = 1; h < windows.n; h++)
        if (windows.v[h].kind == K_WINDOW && windows.v[h].i == id) return h;
    return 0;
}

bool pf_window_size(int win, int *w, int *h)
{
    SDL_Window *sw = win_get(win);
    return sw && SDL_GetWindowSize(sw, w, h);
}

bool pf_window_pixel_size(int win, int *w, int *h)
{
    SDL_Window *sw = win_get(win);
    return sw && SDL_GetWindowSizeInPixels(sw, w, h);
}

double pf_window_display_scale(int win)
{
    SDL_Window *sw = win_get(win);
    if (!sw) return -1;
    float s = SDL_GetWindowDisplayScale(sw);
    return s > 0 ? s : 1.0;
}

double pf_window_refresh_rate(int win)
{
    SDL_Window *sw = win_get(win);
    if (!sw) return -1;
    const SDL_DisplayMode *m = SDL_GetCurrentDisplayMode(SDL_GetDisplayForWindow(sw));
    return m ? m->refresh_rate : 0;
}

bool pf_window_set_title(int win, const char *title)
{
    SDL_Window *sw = win_get(win);
    return sw && SDL_SetWindowTitle(sw, title);
}

bool pf_window_show(int win, bool show)
{
    SDL_Window *sw = win_get(win);
    return sw && (show ? SDL_ShowWindow(sw) : SDL_HideWindow(sw));
}

bool pf_window_is_hidden(int win)
{
    SDL_Window *sw = win_get(win);
    return !sw || (SDL_GetWindowFlags(sw) & (SDL_WINDOW_HIDDEN | SDL_WINDOW_MINIMIZED));
}

/* 0 arrow, 1 ibeam, 2 hand, 3 resize-ew, 4 resize-ns, 5 resize-nwse,
 * 6 resize-nesw, 7 move, 8 wait, 9 crosshair, 10 not-allowed */
bool pf_set_cursor(int kind)
{
    static const SDL_SystemCursor map[] = {
        SDL_SYSTEM_CURSOR_DEFAULT, SDL_SYSTEM_CURSOR_TEXT, SDL_SYSTEM_CURSOR_POINTER,
        SDL_SYSTEM_CURSOR_EW_RESIZE, SDL_SYSTEM_CURSOR_NS_RESIZE, SDL_SYSTEM_CURSOR_NWSE_RESIZE,
        SDL_SYSTEM_CURSOR_NESW_RESIZE, SDL_SYSTEM_CURSOR_MOVE, SDL_SYSTEM_CURSOR_WAIT,
        SDL_SYSTEM_CURSOR_CROSSHAIR, SDL_SYSTEM_CURSOR_NOT_ALLOWED,
    };
    if (kind < 0 || kind >= (int)(sizeof map / sizeof map[0])) {
        pf_set_error("bad cursor %d", kind);
        return false;
    }
    if (!pf_video_init()) return false;
    SDL_SystemCursor c = map[kind];
    if (!cursors[c]) cursors[c] = SDL_CreateSystemCursor(c);
    if (!cursors[c]) {
        pf_set_error("SDL_CreateSystemCursor: %s", SDL_GetError());
        return false;
    }
    return SDL_SetCursor(cursors[c]);
}

char *pf_clipboard_get(void)
{
    if (!pf_video_init()) return NULL;
    char *s = SDL_GetClipboardText();
    char *r = strdup(s ? s : "");
    SDL_free(s);
    if (!r) pf_set_error("out of memory");
    return r;
}

bool pf_clipboard_set(const char *s)
{
    if (!pf_video_init()) return false;
    if (!SDL_SetClipboardText(s)) {
        pf_set_error("SDL_SetClipboardText: %s", SDL_GetError());
        return false;
    }
    return true;
}

void pf_windows_shutdown(void)
{
    for (int h = 1; h < windows.n; h++)
        if (windows.v[h].kind == K_WINDOW) pf_window_close(h);
    for (int i = 0; i < SDL_SYSTEM_CURSOR_COUNT; i++)
        if (cursors[i]) SDL_DestroyCursor(cursors[i]), cursors[i] = NULL;
}

int pf_window_handle_count(void) { return pf_table_count(&windows, -1); }
