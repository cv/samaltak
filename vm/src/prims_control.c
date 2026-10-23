/* Control primitives: perform, closures, processes, timers, the debugger's tryPrimitive. */
#include "core.h"
#include <string.h>

static oop arg0(void) { return prim_argc() > 0 ? prim_arg(0) : nil_oop; }

void p_perform(void)
{
    int n = prim_argc() - 1;
    if (n < 0) return prim_fail();
    oop *b = prim_stack_base(), sel = b[1];
    if (selector_argc(sel) != n) return prim_fail();
    memmove(b + 1, b + 2, (size_t)n * sizeof(oop));
    active_set_stackp(active_stackp() - 1);
    resend_selector = sel;
    resend_argc = n;
    prim_status = PS_RESEND;
}

void p_perform_with_arguments(void)
{
    if (prim_argc() != 2) return prim_fail();
    oop *b = prim_stack_base(), sel = b[1], arr = b[2];
    if (!is_ptr(arr) || raw_class(arr) != cls_array) return prim_fail();
    int n = (int)num_slots(arr);
    int64_t bi = b - active_slots();
    if (selector_argc(sel) != n || bi + 1 + n > active_capacity()) return prim_fail();
    for (int i = 0; i < n; i++) b[1 + i] = slots(arr)[i];
    active_set_stackp(bi + 1 + n);
    resend_selector = sel;
    resend_argc = n;
    prim_status = PS_RESEND;
}

static bool is_block(oop b) { return is_ptr(b) && raw_class(b) == cls_block; }

void p_closure_value(void)
{
    oop b = prim_receiver();
    if (!is_block(b) || load_ref(b, BC_NUMARGS) != int_oop(prim_argc())) return prim_fail();
    activate_block(prim_argc());
    prim_switched();
}

void p_closure_value_with_arguments(void)
{
    oop b = prim_receiver(), a = arg0();
    if (!is_block(b) || !is_ptr(a) || raw_class(a) != cls_array || load_ref(b, BC_NUMARGS) != int_oop(num_slots(a)))
        return prim_fail();
    activate_block_with_array();
    prim_switched();
}

void p_marker(void) { prim_fail(); }

/* ---- processes ---- */

static bool is_process(oop p) { return is_ptr(p) && raw_class(p) == special(SO_PROCESS); }

void p_process_resume(void)
{
    oop p = prim_receiver();
    if (!is_process(p)) return prim_fail();
    oop ctx = load_ref(p, PROC_SUSPENDED);
    if (!is_ptr(ctx) || ctx == nil_oop || raw_class(ctx) != cls_context || load_ref(p, PROC_MYLIST) != nil_oop ||
        p == active_process())
        return prim_fail();
    prim_commit(p);
    resume_process(p);
}

void p_process_suspend(void)
{
    oop p = prim_receiver();
    if (!is_process(p)) return prim_fail();
    if (p == active_process()) {
        prim_commit(nil_oop);
        suspend_active();
        return;
    }
    oop l = load_ref(p, PROC_MYLIST);
    if (l == nil_oop || !remove_link(l, p)) return prim_fail();
    prim_return(l);
}

void p_processor_yield(void)
{
    prim_commit(prim_receiver());
    processor_yield();
}

void p_semaphore_signal(void)
{
    oop s = prim_receiver();
    if (!is_ptr(s) || num_slots(s) <= SEM_EXCESS) return prim_fail();
    prim_commit(s);
    semaphore_signal(s);
}

void p_semaphore_wait(void)
{
    oop s = prim_receiver();
    if (!is_ptr(s) || num_slots(s) <= SEM_EXCESS) return prim_fail();
    prim_commit(s);
    semaphore_wait(s);
}

void p_processor_last_preempted(void) { prim_return(last_preempted); }

void p_processor_relinquish(void)
{
    oop us = arg0();
    if (!is_int(us)) return prim_fail();
    relinquish(int_val(us));
    prim_return(prim_receiver());
}

void p_signal_at_milliseconds(void)
{
    if (prim_argc() < 2 || !is_int(prim_arg(1))) return prim_fail();
    oop s = prim_arg(0);
    if (is_ptr(s) && s != nil_oop && num_slots(s) > SEM_EXCESS) {
        store_ref(specials_oop, SO_TIMER_SEMAPHORE, s);
        set_timer(int_val(prim_arg(1)));
    } else {
        store_ref(specials_oop, SO_TIMER_SEMAPHORE, nil_oop);
        set_timer(-1);
    }
    request_interrupt_check();
    prim_return(prim_receiver());
}

void p_sampler_interval(void)
{
    if (prim_argc() < 2 || !is_int(prim_arg(0)) || !is_int(prim_arg(1))) return prim_fail();
    set_sampler(int_val(prim_arg(0)) > 0 ? int_val(prim_arg(0)) : 0, (int)int_val(prim_arg(1)));
    prim_return(prim_receiver());
}

void p_allocation_sampling(void)
{
    if (prim_argc() < 2 || !is_int(prim_arg(0)) || !is_int(prim_arg(1))) return prim_fail();
    int64_t n = int_val(prim_arg(0));
    alloc_sample_interval = alloc_sample_countdown = n > 0 ? n : 0;
    alloc_sample_sema = (int)int_val(prim_arg(1));
    alloc_sample_unread = false;
    reset_alloc_limit();
    prim_return(prim_receiver());
}

/* Process>>cpuMicroseconds: cpuTime plus, for the active process, the slice it is running */
void p_process_cpu_time(void)
{
    oop p = prim_receiver();
    if (!is_ptr(p) || num_slots(p) <= PROC_CPUTIME) return prim_fail();
    prim_return(int_oop(process_cpu_time_us(p)));
}

/* Profiler: aProcess (not active) stackInto: buffer maxDepth: n (n <= 255; buffer an Array of 2n + 1 slots).
   Writes the innermost n frames bottom-up as method, pc pairs (pc: the block's startpc, 0 for a method) after
   slot 1, which holds depth + (truncated << 16) of the stack written last. Answers k + (depth << 8) +
   (truncated << 16) + (innermost frame just activated << 17); k counts the bottom frames equal to the previous
   content (only if both are truncated or both are not). */
void p_process_stack_into(void)
{
    if (prim_argc() < 2 || !is_int(prim_arg(1))) return prim_fail();
    oop proc = prim_receiver(), buf = prim_arg(0);
    int64_t max = int_val(prim_arg(1));
    if (!is_ptr(proc) || num_slots(proc) <= PROC_CPUTIME || proc == active_process()) return prim_fail();
    if (!is_ptr(buf) || raw_class(buf) != cls_array || max < 1 || max > 255 || num_slots(buf) < (uint32_t)(2 * max + 1))
        return prim_fail();
    oop meths[255];
    int64_t pcs[255];
    int n = 0, fresh = 0;
    oop ctx = load_ref(proc, PROC_SUSPENDED);
    while (is_ptr(ctx) && ctx != nil_oop && n < max) {
        oop cl = load_ref(ctx, CTX_CLOSURE);
        int64_t pc = is_ptr(cl) && cl != nil_oop ? int_val(load_ref(cl, BC_STARTPC)) : 0;
        if (n == 0) fresh = load_ref(ctx, CTX_PC) == int_oop(pc);
        meths[n] = load_ref(ctx, CTX_METHOD);
        pcs[n++] = pc;
        ctx = load_ref(ctx, CTX_SENDER);
    }
    int truncated = is_ptr(ctx) && ctx != nil_oop;
    oop prev = load_ref(buf, 0);
    int k = 0;
    if (is_int(prev) && ((int_val(prev) >> 16) & 1) == truncated) {
        int lim = (int)(int_val(prev) & 0xFFFF) < n ? (int)(int_val(prev) & 0xFFFF) : n;
        while (k < lim && load_ref(buf, (uint32_t)(1 + 2 * k)) == meths[n - 1 - k] &&
               load_ref(buf, (uint32_t)(2 + 2 * k)) == int_oop(pcs[n - 1 - k]))
            k++;
    }
    for (int j = k; j < n; j++) {
        store_ref(buf, (uint32_t)(1 + 2 * j), meths[n - 1 - j]);
        store_ref(buf, (uint32_t)(2 + 2 * j), int_oop(pcs[n - 1 - j]));
    }
    store_ref(buf, 0, int_oop(n | truncated << 16));
    prim_return(int_oop(k | n << 8 | truncated << 16 | fresh << 17));
}

void p_allocation_sample_info(void)
{
    oop a = alloc_obj(cls_array, F_VAR, 2);
    store_ref(a, 0, alloc_sample_class);
    store_ref(a, 1, int_oop(alloc_sample_size));
    prim_return(a);
}

/* {class. size} of an allocation sample not taken yet (and mark it taken), else nil: lets one sampler process serve
   the CPU and allocation samplers' common semaphore. */
void p_allocation_sample_take(void)
{
    if (!alloc_sample_unread) return prim_return(nil_oop);
    alloc_sample_unread = false;
    p_allocation_sample_info();
}

/* Whether a CPU sampler tick was signalled and not taken yet (and mark it taken): the sampler semaphore may be
   one that is also signalled for other reasons (the timer process's). */
void p_sampler_tick_take(void)
{
    bool t = sampler_tick_unread;
    sampler_tick_unread = false;
    prim_return(t ? true_oop : false_oop);
}

/* Context>>tryPrimitive: index receiver: r args: array */
void p_try_primitive(void)
{
    if (prim_argc() != 3) return prim_fail();
    oop idx = prim_arg(0), arr = prim_arg(2), failed = special(SO_SEL_PRIMITIVEFAILED);
    if (!is_int(idx) || !is_ptr(arr) || raw_class(arr) != cls_array) return prim_fail();
    prim_fn fn = prim_lookup(int_val(idx));
    int64_t bi = active_stackp() - 1 - 3;
    uint32_t n = num_slots(arr);
    if (!fn || !prim_tryable(fn) || bi + 1 + (int64_t)n > active_capacity()) return prim_return(failed);
    oop *b = active_slots() + bi;
    b[0] = b[2];
    for (uint32_t i = 0; i < n; i++) b[1 + i] = slots(arr)[i];
    active_set_stackp(bi + 1 + n);
    prim_nargs = (int)n;
    prim_status = PS_NONE;
    fn();
    oop res = prim_status == PS_OK ? prim_result : special(SO_SEL_PRIMITIVEFAILED);
    prim_result = nil_oop;
    active_slots()[bi] = res;
    active_set_stackp(bi + 1);
    prim_nargs = 0;
    prim_status = PS_SWITCHED;
}
