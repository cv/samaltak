/* Process scheduler, semaphores, interrupts (ticker thread, timer, samplers). */
#include "core.h"
#include <pthread.h>
#include <stdlib.h>
#include <time.h>
#ifdef __APPLE__
#include <sys/event.h>
#endif

atomic_int interrupt_pending;
oop last_preempted;
oop alloc_sample_class;
int64_t alloc_sample_size, alloc_sample_interval, alloc_sample_countdown;
int alloc_sample_sema;
uint64_t stat_process_switches;

static bool alloc_sample_pending, in_idle, preempt_to_front;
bool alloc_sample_unread, sampler_tick_unread;
static int64_t timer_ms = -1, sampler_interval_us, sampler_next_us, last_switch_us, start_us;
static int sampler_sema;
static int *pending_ext, pending_ext_n, pending_ext_cap;

static int64_t raw_now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

int64_t now_us(void) { return raw_now_us() - start_us; }
int64_t now_ms(void) { return now_us() / 1000; }

void request_interrupt_check(void) { atomic_store_explicit(&interrupt_pending, 1, memory_order_relaxed); }

void signal_external_semaphore(int index)
{
    if (pending_ext_n == pending_ext_cap) {
        pending_ext_cap = pending_ext_cap ? pending_ext_cap * 2 : 64;
        pending_ext = realloc(pending_ext, sizeof(int) * (size_t)pending_ext_cap);
        if (!pending_ext) fatal("out of memory queueing external semaphore signals");
    }
    pending_ext[pending_ext_n++] = index;
    request_interrupt_check();
}

/* ---- ticker ----
 * While Smalltalk runs, a kqueue timer serviced by the ticker thread requests an interrupt check when the timer or
 * the CPU sampler is due, and a periodic one every tick_poll_us if the platform asked for polls
 * (request_periodic_poll). While the VM waits in platform_wait both are disarmed: the wait's timeout covers the timer
 * and the sampler, and the platform wakes it for events. tick_update (VM thread) re-arms after any change. */
enum { TICK_DEADLINE = 1, TICK_POLL };
static bool tick_idle;
static int64_t tick_poll_us, tick_armed_poll, tick_armed_deadline = INT64_MAX;
static atomic_bool tick_deadline_fired; /* the one-shot fired; re-arm it if its deadline is still ahead */

#ifdef __APPLE__
static int tick_kq = -1;

/* us < 0 disarms (an already fired one-shot is gone: ENOENT, ignored) */
static void tick_arm(int ident, int64_t us, bool periodic)
{
    struct kevent ch, res;
    if (us < 0) EV_SET(&ch, ident, EVFILT_TIMER, EV_DELETE | EV_RECEIPT, 0, 0, NULL);
    else EV_SET(&ch, ident, EVFILT_TIMER, EV_ADD | EV_RECEIPT | (periodic ? 0 : EV_ONESHOT), NOTE_USECONDS, us, NULL);
    struct timespec zero = {0, 0};
    kevent(tick_kq, &ch, 1, &res, 1, &zero);
}

static void *ticker(void *arg)
{
    (void)arg;
    struct kevent ev;
    for (;;)
        if (kevent(tick_kq, NULL, 0, &ev, 1, NULL) > 0) {
            if (ev.ident == TICK_DEADLINE) atomic_store(&tick_deadline_fired, true);
            request_interrupt_check();
        }
    return NULL;
}

static void ticker_start(void)
{
    if ((tick_kq = kqueue()) < 0) fatal("cannot create the ticker's kqueue");
    pthread_t t;
    if (pthread_create(&t, NULL, ticker, NULL) != 0) fatal("cannot start the ticker thread");
    pthread_detach(t);
}
#else
/* without kqueue: a fixed 500 µs tick */
static void tick_arm(int ident, int64_t us, bool periodic) {}

static void *ticker(void *arg)
{
    (void)arg;
    for (;;) {
        struct timespec ts = {0, 500000};
        nanosleep(&ts, NULL);
        request_interrupt_check();
    }
    return NULL;
}

static void ticker_start(void)
{
    pthread_t t;
    if (pthread_create(&t, NULL, ticker, NULL) != 0) fatal("cannot start the ticker thread");
    pthread_detach(t);
}
#endif

/* A pending one-shot is not armed twice; one that fired before its deadline (clock skew) is armed again. */
static void tick_update(void)
{
    int64_t due = INT64_MAX, poll = tick_idle ? 0 : tick_poll_us, now = now_us();
    if (!tick_idle) {
        if (timer_ms >= 0 && timer_ms < INT64_MAX / 1000) due = timer_ms * 1000;
        if (sampler_interval_us > 0 && sampler_next_us < due) due = sampler_next_us;
    }
    if (atomic_exchange(&tick_deadline_fired, false) || due != tick_armed_deadline) {
        if (due <= now) request_interrupt_check();
        tick_arm(TICK_DEADLINE, due == INT64_MAX || due <= now ? -1 : due - now, false);
        tick_armed_deadline = due;
    }
    if (poll != tick_armed_poll) {
        tick_arm(TICK_POLL, poll ? poll : -1, true);
        tick_armed_poll = poll;
    }
}

static void tick_set_idle(bool idle)
{
    tick_idle = idle;
    tick_update();
}

void request_periodic_poll(int64_t interval_us)
{
    tick_poll_us = interval_us > 0 ? interval_us : 0;
    tick_update();
}

void sched_init(void)
{
    start_us = raw_now_us();
    last_preempted = nil_oop;
    alloc_sample_class = nil_oop;
    last_switch_us = 0;
    ticker_start();
}

/* ---- linked lists ---- */

void add_last_link(oop list, oop link)
{
    store_ref(link, PROC_NEXT, nil_oop);
    if (load_ref(list, LL_FIRST) == nil_oop) store_ref(list, LL_FIRST, link);
    else store_ref(load_ref(list, LL_LAST), PROC_NEXT, link);
    store_ref(list, LL_LAST, link);
    store_ref(link, PROC_MYLIST, list);
}

oop remove_first_link(oop list)
{
    oop first = load_ref(list, LL_FIRST);
    if (first == nil_oop) return nil_oop;
    oop next = load_ref(first, PROC_NEXT);
    store_ref(list, LL_FIRST, next);
    if (next == nil_oop) store_ref(list, LL_LAST, nil_oop);
    store_ref(first, PROC_NEXT, nil_oop);
    store_ref(first, PROC_MYLIST, nil_oop);
    return first;
}

static void add_first_link(oop list, oop link)
{
    store_ref(link, PROC_NEXT, load_ref(list, LL_FIRST));
    if (load_ref(list, LL_FIRST) == nil_oop) store_ref(list, LL_LAST, link);
    store_ref(list, LL_FIRST, link);
    store_ref(link, PROC_MYLIST, list);
}

bool remove_link(oop list, oop link)
{
    oop prev = nil_oop, cur = load_ref(list, LL_FIRST);
    while (cur != nil_oop && cur != link) {
        prev = cur;
        cur = load_ref(cur, PROC_NEXT);
    }
    if (cur == nil_oop) return false;
    oop next = load_ref(link, PROC_NEXT);
    if (prev == nil_oop) store_ref(list, LL_FIRST, next);
    else store_ref(prev, PROC_NEXT, next);
    if (load_ref(list, LL_LAST) == link) store_ref(list, LL_LAST, prev);
    store_ref(link, PROC_NEXT, nil_oop);
    store_ref(link, PROC_MYLIST, nil_oop);
    return true;
}

/* ---- scheduling ---- */

static oop processor(void) { return special(SO_PROCESSOR); }
oop active_process(void) { return load_ref(processor(), SCHED_ACTIVE); }

static int64_t priority_of(oop p)
{
    oop v = load_ref(p, PROC_PRIORITY);
    int64_t pr = is_int(v) ? int_val(v) : 1;
    return pr < 1 ? 1 : pr > 80 ? 80 : pr;
}

static oop run_list(int64_t pri) { return load_ref(load_ref(processor(), SCHED_LISTS), (uint32_t)(pri - 1)); }

/* Saves the active context into the outgoing process and switches to proc. */
void transfer_to(oop proc)
{
    push_root(&proc);
    materialize_all(); /* a suspended process is a chain of Contexts */
    pop_root();
    oop old = active_process();
    int64_t now = now_us();
    oop ct = load_ref(old, PROC_CPUTIME);
    store_ref(old, PROC_CPUTIME, int_oop((is_int(ct) ? int_val(ct) : 0) + now - last_switch_us));
    last_switch_us = now;
    store_ref(old, PROC_SUSPENDED, active_ctx);
    store_ref(processor(), SCHED_ACTIVE, proc);
    oop ctx = load_ref(proc, PROC_SUSPENDED);
    if (!is_ptr(ctx) || ctx == nil_oop) fatal("resuming a process without a context");
    store_ref(proc, PROC_SUSPENDED, nil_oop);
    active_ctx = ctx;
    remember_if_old(ctx);
    stat_process_switches++;
}

static void idle_wait(void)
{
    in_idle = true;
    if (!pending_ext_n && !alloc_sample_pending) {
        int64_t now = now_us(), wait = INT64_MAX;
        if (timer_ms >= 0) wait = timer_ms * 1000 - now;
        if (sampler_interval_us > 0 && sampler_next_us - now < wait) wait = sampler_next_us - now;
        tick_set_idle(true);
        if (wait == INT64_MAX) platform_wait(-1);
        else if (wait > 0) platform_wait(wait);
        tick_set_idle(false);
    }
    handle_interrupts();
    last_switch_us = now_us();
    in_idle = false;
}

static void transfer_to_highest(void)
{
    for (;;) {
        oop lists = load_ref(processor(), SCHED_LISTS);
        for (uint32_t i = num_slots(lists); i-- > 0;) {
            oop l = load_ref(lists, i);
            if (load_ref(l, LL_FIRST) != nil_oop) {
                transfer_to(remove_first_link(l));
                return;
            }
        }
        idle_wait();
    }
}

void resume_process(oop proc)
{
    oop active = active_process();
    if (!in_idle && priority_of(proc) > priority_of(active)) {
        /* Profiler wakeups must not reorder the run queue: they would act as a 1 ms time slicer and bias the samples. */
        if (preempt_to_front) add_first_link(run_list(priority_of(active)), active);
        else add_last_link(run_list(priority_of(active)), active);
        last_preempted = active;
        transfer_to(proc);
    } else {
        add_last_link(run_list(priority_of(proc)), proc);
    }
}

void suspend_active(void) { transfer_to_highest(); }

void semaphore_signal(oop sem)
{
    if (load_ref(sem, LL_FIRST) == nil_oop) {
        oop ex = load_ref(sem, SEM_EXCESS);
        store_ref(sem, SEM_EXCESS, int_oop((is_int(ex) ? int_val(ex) : 0) + 1));
    } else {
        resume_process(remove_first_link(sem));
    }
}

void semaphore_wait(oop sem)
{
    oop ex = load_ref(sem, SEM_EXCESS);
    if (is_int(ex) && int_val(ex) > 0) {
        store_ref(sem, SEM_EXCESS, int_oop(int_val(ex) - 1));
        return;
    }
    add_last_link(sem, active_process());
    transfer_to_highest();
}

void processor_yield(void)
{
    oop active = active_process();
    oop l = run_list(priority_of(active));
    if (load_ref(l, LL_FIRST) == nil_oop) return;
    add_last_link(l, active);
    transfer_to(remove_first_link(l));
}

/* ---- interrupts ---- */

static bool is_semaphore(oop s) { return is_ptr(s) && s != nil_oop && fmt_has_pointers(format_of(s)) && num_slots(s) > SEM_EXCESS; }

static void signal_index(int index)
{
    oop ext = special(SO_EXTERNAL_OBJECTS);
    if (index < 1 || !is_ptr(ext) || ext == nil_oop || (uint32_t)index > num_slots(ext)) return;
    oop s = load_ref(ext, (uint32_t)index - 1);
    if (is_semaphore(s)) semaphore_signal(s);
}

void handle_interrupts(void)
{
    atomic_store_explicit(&interrupt_pending, 0, memory_order_relaxed);
    platform_poll();
    int64_t now = now_us();
    if (timer_ms >= 0 && now / 1000 >= timer_ms) {
        timer_ms = -1;
        oop s = special(SO_TIMER_SEMAPHORE);
        if (is_semaphore(s)) semaphore_signal(s);
    }
    preempt_to_front = true;
    if (sampler_interval_us > 0 && now >= sampler_next_us) {
        /* keep the phase, so the mean interval is exact even if interrupt checks come late */
        sampler_next_us += sampler_interval_us;
        if (sampler_next_us <= now) sampler_next_us = now + sampler_interval_us;
        sampler_tick_unread = true;
        signal_index(sampler_sema);
    }
    if (alloc_sample_pending) {
        alloc_sample_pending = false;
        signal_index(alloc_sample_sema);
    }
    preempt_to_front = false;
    if (finalization_pending) {
        finalization_pending = false;
        oop s = special(SO_FINALIZATION_SEMAPHORE);
        if (is_semaphore(s)) semaphore_signal(s);
    }
    for (int i = 0; i < pending_ext_n; i++) signal_index(pending_ext[i]);
    pending_ext_n = 0;
    tick_update();
}

void set_timer(int64_t ms)
{
    timer_ms = ms;
    tick_update();
}

int64_t process_cpu_time_us(oop proc)
{
    oop ct = load_ref(proc, PROC_CPUTIME);
    int64_t t = is_int(ct) ? int_val(ct) : 0;
    if (proc == active_process() && !in_idle) t += now_us() - last_switch_us;
    return t;
}

void set_sampler(int64_t interval_us, int sema)
{
    sampler_interval_us = interval_us;
    sampler_sema = sema;
    sampler_next_us = now_us() + interval_us;
    tick_update();
}

void alloc_sample_hit(oop cls, size_t bytes)
{
    alloc_sample_class = cls;
    alloc_sample_size = (int64_t)bytes;
    alloc_sample_pending = true;
    alloc_sample_unread = true;
    request_interrupt_check();
}

void relinquish(int64_t us)
{
    if (pending_ext_n || alloc_sample_pending) return;
    int64_t now = now_us();
    if (timer_ms >= 0 && timer_ms * 1000 - now < us) us = timer_ms * 1000 - now;
    if (sampler_interval_us > 0 && sampler_next_us - now < us) us = sampler_next_us - now;
    if (us > 0) {
        tick_set_idle(true);
        platform_wait(us);
        tick_set_idle(false);
    }
    request_interrupt_check();
}
