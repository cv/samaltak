/* Test-only DSO. Build twice with different callback signatures. */
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>

typedef void (*entry_fn)(void);
#ifdef VOID_LAYOUT
typedef void (*callback_fn)(int32_t, uint32_t, uint64_t, int64_t, int32_t, void *);
#else
typedef int32_t (*callback_fn)(uint32_t, void *, uint64_t);
#endif

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_t worker;
static callback_fn callback;
static void *context;
static int request, quitting;
static int32_t live;

static void notify(void)
{
#ifdef VOID_LAYOUT
    callback(-7, 70, 805, -99, 42, context);
#else
    if (callback(73, context, UINT64_C(0x1234567890abcdef)) != 0)
        abort();
#endif
}

static void *run(void *unused)
{
    (void)unused;
    pthread_mutex_lock(&lock);
    while (!quitting) {
        while (!request && !quitting)
            pthread_cond_wait(&changed, &lock);
        if (!request)
            break;
        notify();
        notify();
        notify();
        request = 0;
        pthread_cond_signal(&changed);
    }
    pthread_mutex_unlock(&lock);
    /* This last callback must complete before unregister returns. */
    notify();
    return NULL;
}

int32_t fixture_subscribe(entry_fn entry, void *ctx)
{
    if (live || !entry || !ctx)
        abort();
    callback = (callback_fn)entry;
    context = ctx;
    request = quitting = 0;
    notify();
    notify();
    if (pthread_create(&worker, NULL, run, NULL) != 0) {
        callback = NULL;
        context = NULL;
        return -1;
    }
    live = 1;
    return 0;
}

void fixture_unsubscribe(void *ctx)
{
    if (!live || ctx != context)
        abort();
    pthread_mutex_lock(&lock);
    quitting = 1;
    pthread_cond_signal(&changed);
    pthread_mutex_unlock(&lock);
    if (pthread_join(worker, NULL) != 0)
        abort();
    live = 0;
    callback = NULL;
    context = NULL;
}

int32_t fixture_fire(void)
{
    if (!live)
        return 0;
    pthread_mutex_lock(&lock);
    request = 1;
    pthread_cond_signal(&changed);
    while (request)
        pthread_cond_wait(&changed, &lock);
    pthread_mutex_unlock(&lock);
    return 1;
}
