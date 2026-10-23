/* Display-refresh semaphore: a CVDisplayLink thread flags each refresh; the
 * next platform_poll signals the semaphore (the compositor's frame clock).
 * Signaled at most once per poll, so a late compositor skips refreshes. */
#include "platform.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <CoreVideo/CoreVideo.h>
#include <SDL3/SDL.h>
#include <stdatomic.h>

/* autolink CoreVideo so the VM link line needs only -lSDL3 */
__asm__(".linker_option \"-framework\", \"CoreVideo\"");

static CVDisplayLinkRef display_link;
static atomic_int pending;
static int vsync_sem;

static CVReturn on_refresh(CVDisplayLinkRef dl, const CVTimeStamp *now, const CVTimeStamp *out, CVOptionFlags in,
                           CVOptionFlags *flags, void *ctx)
{
    if (!atomic_exchange(&pending, 1)) {
        request_interrupt_check();
        pf_wake();
    }
    return kCVReturnSuccess;
}

bool pf_vsync_semaphore(int index)
{
    platform_init();
    vsync_sem = index;
    if (index && !display_link) {
        if (CVDisplayLinkCreateWithActiveCGDisplays(&display_link) != kCVReturnSuccess) {
            display_link = NULL;
            pf_set_error("CVDisplayLinkCreateWithActiveCGDisplays failed");
            return false;
        }
        CVDisplayLinkSetOutputCallback(display_link, on_refresh, NULL);
        CVDisplayLinkStart(display_link);
    } else if (!index && display_link) {
        CVDisplayLinkStop(display_link);
        CVDisplayLinkRelease(display_link);
        display_link = NULL;
    }
    return true;
}

void pf_vsync_poll(void)
{
    if (vsync_sem && atomic_exchange(&pending, 0)) signal_external_semaphore(vsync_sem);
}

bool pf_vsync_pending(void) { return vsync_sem && atomic_load(&pending); }
