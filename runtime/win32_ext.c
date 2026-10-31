/* Win32 layer - second round: registry, window, synchronization, threads */
#include <strings.h>
#include "cpu.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>
#include <sys/event.h>
#include <sched.h>
#include <stddef.h>
#include <unistd.h>

void dispatch_indirect(CPU*,uint32_t);
void mem_commit(uint32_t,uint32_t);
uint32_t win32_alloc(uint32_t n, int zero);
uint32_t res_find(uint32_t,uint32_t,int);
uint32_t res_data(uint32_t);
uint32_t res_size(uint32_t);

/* ---- object table (HANDLE -> type/state) ---- */
#define H_BASE 0x00A00000u
typedef enum { OB_NONE=0, OB_EVENT, OB_MUTEX, OB_THREAD, OB_FILE, OB_KEY, OB_SEM } ObKind;
typedef struct {
    ObKind kind; int signaled; int manual;
    pthread_mutex_t mtx; pthread_cond_t cv;
    uint32_t guest_arg, guest_entry, tid;
    uint32_t owner_tid; int rec;      /* MUTEX: ownership + recursion */
    pthread_t th; int started; void *pending;
    volatile int terminate;           /* THREAD: TerminateThread was called on it */
    char name[64];
    int refs;                         /* open handles (DuplicateHandle adds one) */
    int prim_ok;                      /* mtx/cv set up once (kept when the slot is reused) */
    /* OB_THREAD: how it ended (ExitThread's or TerminateThread's code, or the
     * entry's eax), whether its last handle was closed while it still ran, its
     * TEB, who started it (CreateThread's return address), its place in the
     * order threads ended, and how often an import looked its handle up
     * (waits, CloseHandle, GetExitCodeThread, DuplicateHandle, ...): obj_reclaim */
    uint32_t exit_code; int ended, closed;
    uint32_t teb, creator, looked; uint64_t end_seq;
    uint32_t gen;                     /* handle generation (obj_reclaim); kept when the slot is reused */
} Obj;
/* 4096 (was 512), and closed handles' slots are reused.  The table used to
 * only grow: every RegOpenKey, CreateEvent, CreateMutex, CreateSemaphore and
 * CreateThread ate a slot for good, and after 511 the game got NULL handles,
 * a time bomb in a long career session.  The game never closes the handle of
 * the thread it starts for every race or world load, so one slot per load
 * stays in use; a full table takes such a thread's slot back (obj_reclaim). */
#define OBJ_MAX 4096
static Obj g_obj[OBJ_MAX];
static int g_obj_n = 1;
/* A handle is H_BASE + gen * OBJ_MAX + slot.  gen stays 0 until obj_reclaim
 * gives a slot to a new object: the reclaimed thread's handle then names
 * nothing (a late CloseHandle or wait on it is that of a closed handle and
 * cannot reach the slot's new object).  Handles stay below 0x00B00000. */
#define OBJ_GENS 256u
static int obj_slot(uint32_t h){                /* -1: not ours, or an older generation's */
    uint32_t d = h - H_BASE;                     /* below H_BASE wraps past the range */
    if (d >= OBJ_GENS * OBJ_MAX) return -1;
    uint32_t i = d % OBJ_MAX;
    return d / OBJ_MAX == g_obj[i].gen ? (int)i : -1;
}
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
typedef struct { uint64_t waits, sets; uint32_t waiter_tid, setter_tid; } WStat;
static WStat g_wstat[64];

/* ---- BIG GUEST LOCK ----------------------------------------------------
 * Guest code runs on only one thread at a time. This keeps the guest
 * memory/allocators shared by the lifted code safe and the instruction trace
 * consistent. The lock is released only in blocking calls (Sleep/Wait*).  */
extern CPU *g_cur_cpu;
static _Thread_local CPU *tl_cpu = 0;
static _Thread_local void *tl_obj = 0;   /* this thread's object */
/* Wait semantics.  Waits used to give up early: events after 2 s even for INFINITE, multi-object
 * waits after 200 ms.  A game thread that waits for an event during a long load (the NIS
 * audio stream thread, for instance) then saw a bogus WAIT_TIMEOUT.  NFSU2_WAIT_LEGACY=1 cuts
 * waits at 2 s / 200 ms again (A/B). */
static int wait_legacy(void){ static int v=-1; if (v<0){ const char *e=getenv("NFSU2_WAIT_LEGACY"); v = (e && *e && *e!='0'); } return v; }
static uint64_t wait_now_us(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (uint64_t)t.tv_sec*1000000u + (uint64_t)t.tv_nsec/1000u; }
static int wait_thread_killed(void);
/* The deadline of a wait (monotonic clock, UINT64_MAX = INFINITE) and the next slice of it.
 * Short slices let a TerminateThread end a waiting thread; a condition variable may also
 * wake early, so every wait loops until its object is ready or the deadline has passed. */
static uint64_t wait_deadline(uint32_t ms, uint32_t legacy_cap_ms){
    if (wait_legacy() && (ms == 0xFFFFFFFFu || ms > legacy_cap_ms)) ms = legacy_cap_ms;
    return ms == 0xFFFFFFFFu ? UINT64_MAX : wait_now_us() + (uint64_t)ms * 1000u;
}
static uint64_t wait_slice(uint64_t deadline, uint64_t slice_us){
    uint64_t now = wait_now_us();
    return deadline <= now ? 0 : deadline - now < slice_us ? deadline - now : slice_us;
}
/* With o->mtx held.  A mutex is ready when it is free or already ours (recursion); a wait
 * on it takes ownership.  A semaphore gives one count per wait, an auto-reset event resets,
 * a thread stays signaled once it has ended. */
static int wait_ready(Obj *o, uint32_t tid){
    return o->signaled > 0 || (o->kind == OB_MUTEX && o->owner_tid == tid && o->rec > 0);
}
static void wait_take(Obj *o, uint32_t tid){
    if (o->kind == OB_MUTEX){ o->signaled = 0; o->owner_tid = tid; o->rec++; }
    else if (o->kind == OB_SEM) o->signaled--;
    else if (o->kind == OB_EVENT && !o->manual) o->signaled = 0;
}
/* A mutex that is free or ours, taken at once (guest_noyield, gil_keep_for_mutex); 0: the wait has to block. */
static int mutex_take_now(Obj *o, uint32_t tid){
    pthread_mutex_lock(&o->mtx);
    int got = wait_ready(o, tid);
    if (got) wait_take(o, tid);
    pthread_mutex_unlock(&o->mtx);
    return got;
}
/* THREADLOG=1: log thread creation, termination and stack recycling */
static int thread_log(void){ static int v=-1; if (v<0){ const char *e=getenv("THREADLOG"); v = (e && *e && *e!='0'); } return v; }

/* CPU state of all guest threads: to be able to dump the stack traces of ALL
 * of them at stall time (a single thread's can be misleading). */
#define MAXCPUS 32
CPU *g_all_cpus[MAXCPUS];
uint32_t g_all_tids[MAXCPUS];
int g_all_n = 0;
/* Stall watchdog (watchdog.c): what each guest thread is doing right now. */
enum { TS_RUN = 0, TS_GIL, TS_WAIT, TS_WAITM, TS_CS, TS_SLEEP, TS_IDLE };
typedef struct { volatile int what; volatile uint32_t obj; volatile uint64_t since_us; } TState;
TState g_tstate[MAXCPUS];
static _Thread_local int tl_slot = -1;
static uint64_t gil_now_us(void);
static void ts_set(int what, uint32_t obj){
    if (tl_slot < 0) return;
    g_tstate[tl_slot].what = what; g_tstate[tl_slot].obj = obj; g_tstate[tl_slot].since_us = gil_now_us();
}
static void reg_cpu(CPU *c){
    for (int i=0;i<g_all_n;i++) if (g_all_cpus[i]==c){ tl_slot = i; return; }
    for (int i=0;i<g_all_n;i++) if (!g_all_cpus[i]){             /* a slot an ended thread left */
        g_all_cpus[i] = c; g_all_tids[i] = c->fs_base ? MR32(c->fs_base+0x24) : 0; tl_slot = i; return; }
    if (g_all_n < MAXCPUS){
        g_all_cpus[g_all_n] = c;
        g_all_tids[g_all_n] = c->fs_base ? MR32(c->fs_base+0x24) : 0;
        tl_slot = g_all_n;
        g_all_n++;
    }
}
/* A guest thread ends: its CPU lived on its host stack. */
static void unreg_cpu(CPU *c){
    for (int i=0;i<g_all_n;i++) if (g_all_cpus[i]==c){ g_all_cpus[i] = 0; g_all_tids[i] = 0; g_tstate[i].what = TS_RUN; }
    tl_slot = -1;
}
/* --- measuring the HOLD TIME of the big lock (GIL) ---------------------
 * A guest thread doesn't release the GIL as long as it makes no Win32 call; a
 * long computation (example: decoding the audio stream) starves the other
 * threads.  The audio writes ~50 ms of silence every 30 s -- we measure
 * whether this is the culprit.  GILLOG=<ms> reports every hold above the
 * threshold. */
static uint64_t gil_now_us(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec*1000000ull + (uint64_t)ts.tv_nsec/1000ull;
}
static _Thread_local uint64_t tl_gil_t0 = 0;
uint64_t g_gil_max_us = 0, g_gil_long = 0;
static int gil_thr_us(void){
    static int v = -1;
    if (v < 0){ const char *e = getenv("GILLOG"); v = (e && *e) ? atoi(e)*1000 : 0; }
    return v;
}
static void gil_took(void){ tl_gil_t0 = gil_now_us(); }
static void gil_gave(void){
    if (!tl_gil_t0) return;
    uint64_t d = gil_now_us() - tl_gil_t0;
    tl_gil_t0 = 0;
    if (d > g_gil_max_us) g_gil_max_us = d;
    int thr = gil_thr_us();
    if (thr && d > (uint64_t)thr){
        g_gil_long++;
        static int shown = 0;
        if (shown < 80){ shown++;
            double audio_time(void);
            fprintf(stderr, "  [GIL] t=%.3f s  lock held %.1f ms  guest eip=%08x\n",
                    audio_time(), d/1000.0, tl_cpu ? tl_cpu->eip : 0u);
        }
    }
}
/* ---- the guest lock: a FIFO ticket lock or a plain mutex -----------------
 * A pthread mutex has no order: a thread that unlocks and relocks at once
 * (the fair yield, a 10 ms Sleep loop, the frame pacer) can win again and
 * again while the threads parked on it (the DirectSound feeder, the loader,
 * the winmm timer) wait.  NFSU2_GIL=ticket: every locker draws a ticket and
 * the lock is handed over in ticket order (from th0mk's nfsu2-web, where the
 * browser's lock had the same problem; here on a host mutex and condition
 * variable).  NFSU2_GIL=mutex (the default) is the plain mutex.  Both
 * measure every acquisition that had to queue: how long the thread waited
 * (the holder's time included), per guest thread, in the exit report
 * ("guest lock").  NFSU2_GIL_STAT=0 turns the measurement off. */
typedef struct { uint32_t tid; uint64_t n, queued; double wait_ms, wait_max_ms; uint32_t whist[24]; } GilStat;
static GilStat g_gs[64]; static int g_gs_n;
static GilStat g_gs_tot;
static _Thread_local GilStat *tl_gs; static _Thread_local uint32_t tl_gs_tid = ~0u;
static _Thread_local double tl_acq_ms; static _Thread_local int tl_holding;
static int g_gil_ticket = -1, g_gil_stat = -1;
static double g_gil_keep_ms = -1;
static uint64_t g_gil_fair_yields, g_gil_kept;
static pthread_mutex_t g_guest = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_tk_mx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_tk_cv = PTHREAD_COND_INITIALIZER;
static uint32_t g_tk_next, g_tk_serving;           /* tickets drawn / the one served (under g_tk_mx) */
static double gil_ms(void){ return (double)gil_now_us() / 1000.0; }
static void gil_cfg(void){
    if (g_gil_ticket >= 0) return;
    const char *e = getenv("NFSU2_GIL");
    g_gil_ticket = e && !strcmp(e, "ticket");
    e = getenv("NFSU2_GIL_STAT"); g_gil_stat = !(e && *e == '0');
    e = getenv("NFSU2_GIL_KEEP_MS"); g_gil_keep_ms = e && *e ? atof(e) : 2.0;
}
static int gil_bucket(double ms){ double us = ms * 1000.0; int k = 0; while (us >= 2.0 && k < 23){ us *= 0.5; k++; } return k; }
static void gil_note(GilStat *s, double w){
    if (!s) return;
    s->queued++; s->wait_ms += w; if (w > s->wait_max_ms) s->wait_max_ms = w; s->whist[gil_bucket(w)]++;
}
static GilStat *gil_stat_for(CPU *who){                /* the guest lock held */
    uint32_t tid = (who && who->fs_base) ? MR32(who->fs_base + 0x24u) : 0u;
    if (tl_gs && tl_gs_tid == tid) return tl_gs;
    GilStat *s = 0;
    for (int i = 0; i < g_gs_n; i++) if (g_gs[i].tid == tid){ s = &g_gs[i]; break; }
    if (!s && g_gs_n < 64){ s = &g_gs[g_gs_n++]; s->tid = tid; }
    tl_gs = s; tl_gs_tid = tid;
    return s;
}
/* Threads waiting for the ticket lock (0 = nobody); a hint, read without the lock. */
static uint32_t ticket_queued(void){
    uint32_t d = __atomic_load_n(&g_tk_next, __ATOMIC_RELAXED) - __atomic_load_n(&g_tk_serving, __ATOMIC_RELAXED);
    return d ? d - 1u : 0u;
}
static void gil_acquire(CPU *who){
    gil_cfg();
    double t0 = 0; int queued;
    if (g_gil_ticket){
        pthread_mutex_lock(&g_tk_mx);
        uint32_t me = __atomic_fetch_add(&g_tk_next, 1u, __ATOMIC_RELAXED);
        queued = g_tk_serving != me;
        if (queued && g_gil_stat) t0 = gil_ms();
        while (g_tk_serving != me) pthread_cond_wait(&g_tk_cv, &g_tk_mx);
        pthread_mutex_unlock(&g_tk_mx);
    } else {
        queued = pthread_mutex_trylock(&g_guest) != 0;
        if (queued){ if (g_gil_stat) t0 = gil_ms(); pthread_mutex_lock(&g_guest); }
    }
    tl_holding = 1;
    if (!g_gil_stat && !g_gil_ticket) return;
    double t1 = gil_ms();
    tl_acq_ms = t1;
    if (!who || !g_gil_stat) return;
    GilStat *s = gil_stat_for(who); if (s) s->n++; g_gs_tot.n++;
    if (queued){ gil_note(s, t1 - t0); gil_note(&g_gs_tot, t1 - t0); }
}
static void gil_release(void){
    tl_holding = 0;
    if (g_gil_ticket){
        pthread_mutex_lock(&g_tk_mx);
        __atomic_store_n(&g_tk_serving, g_tk_serving + 1u, __ATOMIC_RELAXED);
        int any = g_tk_next != g_tk_serving;
        pthread_mutex_unlock(&g_tk_mx);
        if (any) pthread_cond_broadcast(&g_tk_cv);
    } else pthread_mutex_unlock(&g_guest);
}
/* WaitForSingleObject on a free mutex (win32_ext_call): keep the guest lock
 * instead of handing it over, unless another thread queues for it and this
 * one has held it for NFSU2_GIL_KEEP_MS (2 ms).  Only with the ticket lock,
 * where a hand-over really lets the queue run: the game thread handed it over
 * at every take of the sound library's mutex (~119,000 times in a 50 s
 * race), and each hand-over to a waiting worker risks a late wake-up.
 * Taking every free mutex outright kept the other threads waiting up to the
 * game thread's pacer sleep; the 2 ms bound keeps their waits near what the
 * old hand-overs gave.  0: hand over at every take. */
static int gil_keep_for_mutex(void){
    gil_cfg();
    if (!g_gil_ticket || !(g_gil_keep_ms > 0) || !tl_holding) return 0;
    return !ticket_queued() || gil_ms() - tl_acq_ms < g_gil_keep_ms;
}
static double gil_pct(const uint32_t *hist, uint64_t n, double p){   /* upper edge of the bucket, ms */
    uint64_t want = (uint64_t)(p * (double)n + 0.5), acc = 0;
    for (int k = 0; k < 24; k++){ acc += hist[k]; if (acc >= want && want) return (double)(2u << k) / 1000.0; }
    return 0;
}
static void gil_print(const char *what, const GilStat *s){
    fprintf(stderr, "    %-10s %9llu taken, %8llu queued (%4.1f%%): wait avg %.3f p50<%.3f p99<%.3f max %.2f ms\n", what,
            (unsigned long long)s->n, (unsigned long long)s->queued, s->n ? 100.0 * (double)s->queued / (double)s->n : 0.0,
            s->queued ? s->wait_ms / (double)s->queued : 0.0, gil_pct(s->whist, s->queued, 0.5), gil_pct(s->whist, s->queued, 0.99),
            s->wait_max_ms);
}
void win32_gil_report(void){
    gil_cfg();
    if (!g_gil_stat) return;
    fprintf(stderr, "  guest lock (%s): %llu fair yields handed it over, %llu free mutexes taken keeping it; queued acquisitions:\n",
            g_gil_ticket ? "FIFO ticket lock, NFSU2_GIL=ticket" : "pthread mutex",
            (unsigned long long)g_gil_fair_yields, (unsigned long long)g_gil_kept);
    gil_print("all", &g_gs_tot);
    for (int i = 0; i < g_gs_n; i++){ char nm[32]; snprintf(nm, sizeof nm, "tid %u", g_gs[i].tid); gil_print(nm, &g_gs[i]); }
}
void guest_lock(CPU *c){ ts_set(TS_GIL, 0); gil_acquire(c); tl_cpu=c; g_cur_cpu=c; reg_cpu(c); gil_took(); ts_set(TS_RUN, 0); }
void guest_unlock(void){ ts_set(TS_IDLE, 0); gil_gave(); gil_release(); }
static void guest_yield_begin(void){ gil_gave(); gil_release(); }
static void guest_thread_die(uint32_t code);
static void guest_yield_end(void){ ts_set(TS_GIL, 0); gil_acquire(tl_cpu); g_cur_cpu = tl_cpu; gil_took(); ts_set(TS_RUN, 0);
    if (tl_obj && ((Obj*)tl_obj)->terminate) guest_thread_die(((Obj*)tl_obj)->exit_code); }
/* For runtime code that blocks on a guest thread outside Sleep/Wait* (metal_present
 * waiting for the screen): give the big lock up for the wait.  Returns 0, and does
 * nothing, on a thread that isn't a guest thread. */
int  guest_blocking_begin(void){ if (!tl_cpu) return 0; ts_set(TS_IDLE, 0); guest_yield_begin(); return 1; }
void guest_blocking_end(void){ guest_yield_end(); }
/* A blocking host call (winsock.c select/connect, net_relay.c) waits with
 * the guest lock released, as a Windows thread would wait in the kernel. */
void guest_wait_begin(void){ ts_set(TS_IDLE, 0); guest_yield_begin(); }   /* watchdog: host side */
void guest_wait_end(void){ guest_yield_end(); }
/* Sleep while releasing the big lock (win32.c: the game's frame wait loop). */
uint64_t g_sleep_late_ns, g_sleep_gil_ns, g_sleep_n;    /* diagnostics: sleep latency / lock wait */
/* On macOS nanosleep wakes up with a timer coalescing margin: in the game a
 * 3 ms request is on average 447 us late (separate measurement: median ~770 us,
 * QoS makes no difference).  A kevent timer with NOTE_CRITICAL isn't
 * coalesced: median ~45 us. */
static void sleep_precise_ns(long ns){
    static _Thread_local int kq = -1;
    if (kq < 0) kq = kqueue();
    if (kq >= 0){
        struct kevent ev, out;
        EV_SET(&ev, 1, EVFILT_TIMER, EV_ADD | EV_ONESHOT, NOTE_NSECONDS | NOTE_CRITICAL, ns, 0);
        if (kevent(kq, &ev, 1, &out, 1, NULL) == 1) return;
    }
    struct timespec ts = { (time_t)(ns / 1000000000L), ns % 1000000000L };
    nanosleep(&ts, 0);
}
void guest_sleep_ns(long ns){
    struct timespec a, b, d;
    guest_yield_begin();
    clock_gettime(CLOCK_MONOTONIC, &a); sleep_precise_ns(ns); clock_gettime(CLOCK_MONOTONIC, &b);
    guest_yield_end();
    clock_gettime(CLOCK_MONOTONIC, &d);
    int64_t sl = (int64_t)(b.tv_sec - a.tv_sec) * 1000000000LL + (b.tv_nsec - a.tv_nsec) - ns;
    int64_t gl = (int64_t)(d.tv_sec - b.tv_sec) * 1000000000LL + (d.tv_nsec - b.tv_nsec);
    g_sleep_late_ns += sl > 0 ? (uint64_t)sl : 0; g_sleep_gil_ns += (uint64_t)gl; g_sleep_n++;
}

/* --- frame rate locking (60 Hz) ---------------------------------------
 * The virtual clock advances EXACTLY 16.667 ms per frame, so the game speed =
 * (real fps / 60).  When the emulator did 117 fps the game ran at 195% speed.
 * Locking the frame to 60 Hz makes the speed independent of FPS.
 * The big lock is RELEASED during the sleep, otherwise the worker threads stop. */
/* TIMELOG=1: the virtual/real time ratio and frame count once a second.
 * For measuring the complaint "the game speeds up needlessly in cutscenes" --
 * if the ratio goes above 1.0 the game really is running fast. */
static void timelog_tick(void){
    static int on = -1;
    if (on < 0){ const char *e = getenv("TIMELOG"); on = (e && *e && *e != '0'); }
    if (!on) return;
    uint64_t host_us(void);
    static uint64_t lr = 0, lv = 0; static long lf = 0;
    long metal_frames(void);
    uint64_t r = gil_now_us(), v = host_us();
    long f = metal_frames();
    if (!lr){ lr = r; lv = v; lf = f; return; }
    if (r - lr < 1000000ull) return;
    fprintf(stderr, "  [time] real %.2f s, virtual %.2f s, ratio %.3f, %ld frames (%.1f fps)\n",
            (r-lr)/1e6, (v-lv)/1e6, (double)(v-lv)/(double)(r-lr),
            f-lf, (f-lf)*1e6/(double)(r-lr));
    lr = r; lv = v; lf = f;
}

void frame_pace(void){
    timelog_tick();
    /* DEFAULT: NO LIMITER.  The 60 Hz rationale above NO LONGER HOLDS --
     * since the virtual clock switched to VCLOCK=real, the game speed is
     * independent of the real fps (measured: virtual/real = 0.999 at both
     * 63.7 fps and 99 fps).  With the limiter on, 61% of the race frame was
     * nanosleep; with it off the race went 63.7 -> 79.4 fps and the menus to
     * 120 fps (the display refresh limit).
     * PACE60=1 brings back the old behavior.  Runaway fps is cut by vsync
     * anyway; the virtual clock's per-frame increment is floored at 4 ms (250 fps).
     * framerate.c paces every frame unless NFSU2_FPS=off and reads PACE60=1 as
     * NFSU2_FPS=60, so this loop only runs with NFSU2_FPS=off. */
    static int off = -1;
    if (off < 0){ const char *e = getenv("PACE60");
                  int hfr_mode_off(void);
                  off = !(e && *e && *e != '0') || !hfr_mode_off(); }
    if (off) return;
    static uint64_t deadline = 0;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t now = (uint64_t)ts.tv_sec*1000000ull + (uint64_t)ts.tv_nsec/1000ull;
    if (!deadline || now > deadline + 200000ull) deadline = now;   /* far behind: reset */
    deadline += 16667ull;
    if (now < deadline){
        uint64_t d = deadline - now;
        struct timespec sl = { (time_t)(d/1000000ull), (long)((d%1000000ull)*1000ull) };
        guest_yield_begin();
        nanosleep(&sl, 0);
        guest_yield_end();
    }
}

/* Fair GIL: guest code can also spin in non-blocking Win32 calls
 * (example: a wait loop spinning on EnterCriticalSection). We periodically
 * release the lock and give the other guest threads a turn.            */
/* ---- REAL critical sections -------------------------------------------
 * EnterCriticalSection/LeaveCriticalSection used to be no-op stubs.  The single
 * big lock (GIL) covered for them most of the time, BUT guest_fair_yield
 * releases the GIL every 1024 Win32 calls: a thread could lose the lock while
 * INSIDE a critical section and another thread could enter the same section.
 * The game's loader/audio/video queues get silently corrupted that way.
 *
 * The GIL MUST BE RELEASED while waiting for the lock, otherwise deadlock.  */
#define MAXCS 512
static struct { uint32_t key; pthread_mutex_t m; int used; uint32_t owner; int depth; } g_cs[MAXCS];
static int g_cs_used = 0;
/* watchdog.c: critical sections held right now */
int win32_cs_held(uint32_t *key, uint32_t *owner, int *depth, int max){
    int n = 0;
    for (int i = 0; i < MAXCS && n < max; i++)
        if (g_cs[i].used && g_cs[i].owner){ key[n] = g_cs[i].key; owner[n] = g_cs[i].owner; depth[n] = g_cs[i].depth; n++; }
    return n;
}
static pthread_mutex_t g_cs_tab = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local int tl_cs_depth = 0;
/* guest_noyield(+1) .. (-1): a guest function that must not lose the GIL to another guest thread halfway
 * (radio.c, sub_0073b900: the music's event tick).  No fair yield, and a mutex that is free (or already ours) is
 * taken without handing the GIL over, as Windows does not switch threads there either; a wait that blocks
 * still gives it up. */
static _Thread_local int tl_noyield = 0;
void guest_noyield(int d){ tl_noyield += d; }
uint64_t g_cs_enter = 0, g_cs_contended = 0;

static int cs_disabled(void){
    static int v = -1;
    if (v < 0){ const char *e = getenv("NOCS"); v = (e && *e && *e != '0') ? 1 : 0; }
    return v;
}
static pthread_mutex_t *cs_for(uint32_t key){
    if (cs_disabled()) return 0;          /* old behavior: no-op stub */
    pthread_mutex_lock(&g_cs_tab);
    unsigned h = (key >> 2) % MAXCS;
    for (unsigned i = 0; i < MAXCS; i++){
        unsigned j = (h + i) % MAXCS;
        if (g_cs[j].used && g_cs[j].key == key){
            pthread_mutex_unlock(&g_cs_tab); return &g_cs[j].m;
        }
        if (!g_cs[j].used){
            pthread_mutexattr_t a;
            pthread_mutexattr_init(&a);
            pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
            pthread_mutex_init(&g_cs[j].m, &a);
            pthread_mutexattr_destroy(&a);
            g_cs[j].key = key; g_cs[j].used = 1; g_cs_used++;
            pthread_mutex_unlock(&g_cs_tab); return &g_cs[j].m;
        }
    }
    pthread_mutex_unlock(&g_cs_tab);
    return 0;                      /* table full: fall back to the old behavior */
}
/* Owner/recursion of a section (watchdog report); only its owner changes them. */
static void cs_owned(pthread_mutex_t *m, uint32_t tid, int d){
    size_t i = (size_t)(((char *)m - (char *)&g_cs[0].m) / (ptrdiff_t)sizeof g_cs[0]);
    if (i >= MAXCS) return;
    g_cs[i].depth += d;
    g_cs[i].owner = g_cs[i].depth > 0 ? (tid ? tid : g_cs[i].owner) : 0u;
}

uint32_t call_guest(CPU *c, uint32_t fn, int nargs, const uint32_t *args);
int metal_take_char(int remove);            /* metal.m: WM_CHAR queue */
static uint32_t g_wndproc = 0;
static uint32_t g_hwnd    = 0x00B00001u;
#define WMQ 8
static struct { uint32_t msg, wp, lp; } g_wmq[WMQ];
static int g_wmq_head = 0, g_wmq_tail = 0;
static int g_wm_activated = 0;
uint64_t g_wm_sent = 0, g_wm_dispatched = 0;

static void wm_push(uint32_t m, uint32_t wp, uint32_t lp){
    int nx = (g_wmq_tail + 1) % WMQ;
    if (nx == g_wmq_head) return;
    g_wmq[g_wmq_tail].msg = m; g_wmq[g_wmq_tail].wp = wp; g_wmq[g_wmq_tail].lp = lp;
    g_wmq_tail = nx;
}
static int wm_pop(uint32_t *m, uint32_t *wp, uint32_t *lp){
    if (g_wmq_head == g_wmq_tail) return 0;
    *m = g_wmq[g_wmq_head].msg; *wp = g_wmq[g_wmq_head].wp; *lp = g_wmq[g_wmq_head].lp;
    g_wmq_head = (g_wmq_head + 1) % WMQ;
    return 1;
}

static uint32_t cur_tid(CPU *c){
    return (c && c->fs_base && mem_is_committed(c->fs_base+0x24u))
           ? MR32(c->fs_base+0x24u) : 0u;
}

void guest_fair_yield(void){
    if (tl_cs_depth || tl_noyield) return;    /* yielding inside a critical section, or kept (guest_noyield) */
    static _Thread_local uint32_t n = 0;
    if ((++n & 0x3FFu) != 0) return;          /* once every 1024 calls */
    if (g_gil_ticket > 0){
        /* the FIFO lock: hand it over only when someone queues; they all run
         * before this thread gets it back, so no sched_yield or nap is needed */
        if (!ticket_queued()) return;
        g_gil_fair_yields++;
        guest_yield_begin();
        guest_yield_end();
        return;
    }
    g_gil_fair_yields++;
    guest_yield_begin();
    sched_yield();
    /* CAUTION: there used to be a nanosleep(50us) here every time.  On macOS a
     * sleep of 50 us really takes ~1-2 ms (scheduler quantum + timer
     * coalescing).  In the pre-race cutscene the guest calls a Win32 function
     * ~110 thousand times per frame; that meant ~110 sleeps = ~165 ms per frame.
     * Measured: 70% of the guest thread was in __semwait_signal, i.e. SLEEP,
     * not computation.  Frame time 235 ms (4.6 fps).  sched_yield already
     * provides fairness; we thin out the sleeps (only to guarantee the other
     * threads make progress). */
    if ((n & 0x7FFFu) == 0){
        struct timespec ts = {0, 50000L}; nanosleep(&ts, 0);
    }
    guest_yield_end();
}

/* Closed handles' slots go to new objects (g_free).  Since a thread may still
 * be waiting on an object being closed, mtx/cv are neither destroyed nor set
 * up again.  NFSU2_NO_OBJREUSE=1: the table only grows, as before. */
static int g_free[OBJ_MAX], g_nfree = 0;
static uint64_t g_obj_reused = 0, g_obj_full = 0, g_obj_reclaimed = 0;
static int obj_reuse(void){ static int v = -1; if (v < 0) v = !getenv("NFSU2_NO_OBJREUSE"); return v; }
/* The table is full (g_lock held; every caller of obj_new holds the guest
 * lock too).  Take back the slot of the thread that ended first among those
 * whose handle no import has looked up since CreateThread: never waited on,
 * closed, duplicated, resumed or asked for its exit code, so no wait on it
 * can be pending either (waits look their handles up before they give the
 * guest lock away).  SPEED2.EXE's per-load timer thread is one: sub_00726454
 * starts it (entry 0x7263C7: timeBeginPeriod, a callback every 10 ms until a
 * flag is cleared) for every race and world load and stores the handle at
 * 0x8B47B8, which nothing in the exe reads; each one ends before the next
 * starts, its handle open.  On Windows such a handle stays valid as long as
 * the process; the table here ran out after ~4,000 loads, and from then on
 * every CreateEvent, CreateThread and RegOpenKey got NULL.  The reclaimed
 * slot moves to the next generation, so the old handle names nothing from
 * then on.  Returns 0 when no thread qualifies. */
static int obj_reclaim(void){
    static uint64_t shown = 0;
    if (!obj_reuse()) return 0;
    int best = 0;
    for (int i = 1; i < g_obj_n && i < OBJ_MAX; i++){
        Obj *o = &g_obj[i];
        if (o->kind != OB_THREAD || !o->ended || o->closed || o->refs != 1 || __atomic_load_n(&o->looked, __ATOMIC_RELAXED)) continue;
        if (!best || o->end_seq < g_obj[best].end_seq) best = i;
    }
    if (!best) return 0;
    Obj *o = &g_obj[best];
    pthread_mutex_lock(&o->mtx);
    if (shown++ < 8)
        fprintf(stderr, "  [object] table full: handle 0x%08x of the ended thread tid=%u (entry 0x%08x, started from 0x%08x,"
                        " handle never looked up) goes to a new object\n",
                H_BASE + o->gen * OBJ_MAX + (uint32_t)best, o->tid, o->guest_entry, o->creator);
    o->kind = OB_NONE; o->gen = (o->gen + 1u) % OBJ_GENS;
    pthread_mutex_unlock(&o->mtx);
    g_obj_reclaimed++;
    return best;
}
static uint32_t obj_new(ObKind k){
    pthread_mutex_lock(&g_lock);
    int i = 0;
    if (g_nfree){ i = g_free[--g_nfree]; g_obj_reused++; }
    else if (g_obj_n < OBJ_MAX) i = g_obj_n++;
    else if ((i = obj_reclaim()) != 0) {}
    else if (!g_obj_full++) fprintf(stderr, "  [object] WARNING: object table full (%d)\n", OBJ_MAX - 1);
    pthread_mutex_unlock(&g_lock);
    if (!i) return 0;
    Obj *o=&g_obj[i];
    if (o->prim_ok){
        pthread_mutex_lock(&o->mtx);
        o->signaled = 0; o->manual = 0; o->guest_arg = o->guest_entry = o->tid = 0;
        o->owner_tid = 0; o->rec = 0; o->started = 0; o->pending = 0; o->terminate = 0; o->name[0] = 0;
        o->exit_code = 0; o->ended = 0; o->closed = 0; o->teb = 0;
        o->creator = 0; o->end_seq = 0; o->looked = 0;
        o->refs = 1; o->kind = k;
        pthread_mutex_unlock(&o->mtx);
    } else {
        memset(o,0,sizeof *o); o->kind=k; o->refs = 1;
        pthread_mutex_init(&o->mtx,0); pthread_cond_init(&o->cv,0); o->prim_ok = 1;
    }
    return H_BASE + o->gen * OBJ_MAX + (uint32_t)i;
}
static void obj_free_slot(int i){
    if (!obj_reuse()) return;
    pthread_mutex_lock(&g_lock); g_free[g_nfree++] = i; pthread_mutex_unlock(&g_lock);
}
/* CloseHandle / RegCloseKey: free the slot when the last handle is closed.  A
 * thread's slot is freed once it has ended and its last handle is closed,
 * whichever comes last (guest_thread_die does it when the close came first). */
static void obj_close(uint32_t h){
    int si = obj_slot(h);
    if (si < 0) return;
    Obj *o = &g_obj[si];
    if (!o->kind || o->kind == OB_FILE) return;
    pthread_mutex_lock(&o->mtx);
    int last = --o->refs <= 0, gone = last;
    if (o->kind == OB_THREAD){
        __atomic_fetch_add(&o->looked, 1u, __ATOMIC_RELAXED);
        gone = last && o->ended;
        if (last && !o->ended) o->closed = 1;
    }
    if (gone){ o->kind = OB_NONE; pthread_cond_broadcast(&o->cv); }
    pthread_mutex_unlock(&o->mtx);
    if (gone) obj_free_slot(si);
}
/* for fileio.c to signal the overlapped completion event. */
void win32_signal_event(uint32_t h);

static Obj *obj_get(uint32_t h){
    int i = obj_slot(h);
    if (i < 0 || !g_obj[i].kind) return 0;
    Obj *o = &g_obj[i];
    if (o->kind == OB_THREAD) __atomic_fetch_add(&o->looked, 1u, __ATOMIC_RELAXED);   /* obj_reclaim */
    return o;
}
static void thread_report(void);
/* The object table's occupancy, for the exit report (win32.c win32_report). */
void win32_obj_report(void){
    int k[8] = {0};
    for (int i = 1; i < g_obj_n && i < OBJ_MAX; i++) if (g_obj[i].kind < 8) k[g_obj[i].kind]++;
    fprintf(stderr, "  object table      : %d/%d slots used (event %d, mutex %d, thread %d, key %d, semaphore %d, free %d), %llu reused, full %llu, %llu reclaimed\n",
            g_obj_n - 1, OBJ_MAX - 1, k[OB_EVENT], k[OB_MUTEX], k[OB_THREAD], k[OB_KEY], k[OB_SEM], k[OB_NONE],
            (unsigned long long)g_obj_reused, (unsigned long long)g_obj_full, (unsigned long long)g_obj_reclaimed);
    /* ended threads whose handle is still open, by entry and the code that
     * started them, and how often an import looked their handles up */
    struct { uint32_t entry, creator, n, looked; } grp[6]; int ng = 0, nend = 0;
    for (int i = 1; i < g_obj_n && i < OBJ_MAX; i++){
        Obj *o = &g_obj[i];
        if (o->kind != OB_THREAD || !o->ended) continue;
        nend++;
        int j = 0;
        while (j < ng && (grp[j].entry != o->guest_entry || grp[j].creator != o->creator)) j++;
        if (j == ng){ if (ng == 6) continue; grp[ng].entry = o->guest_entry; grp[ng].creator = o->creator; grp[ng].n = grp[ng].looked = 0; ng++; }
        grp[j].n++; grp[j].looked += __atomic_load_n(&o->looked, __ATOMIC_RELAXED);
    }
    if (nend){
        fprintf(stderr, "  ended threads     : %d with the handle still open:", nend);
        for (int j = 0; j < ng; j++)
            fprintf(stderr, "%s %u x entry 0x%08x from 0x%08x (handles looked up %u times)", j ? ";" : "",
                    grp[j].n, grp[j].entry, grp[j].creator, grp[j].looked);
        fprintf(stderr, "\n");
    }
    thread_report();
}
/* watchdog.c: one line about a kernel object a thread waits on. */
int win32_obj_describe(uint32_t h, char *buf, size_t n){
    static const char *const kn[] = { "none", "event", "mutex", "thread", "file", "key", "semaphore" };
    int i = obj_slot(h);
    if (i < 0){ return snprintf(buf, n, "handle 0x%08x (not ours)", h); }
    Obj *o = &g_obj[i];
    return snprintf(buf, n, "handle 0x%08x (%s%s%s, signaled %d, owner tid %u, thread tid %u)", h,
                    o->kind <= OB_SEM ? kn[o->kind] : "?", o->name[0] ? " " : "", o->name,
                    o->signaled, o->owner_tid, o->tid);
}
/* [status]-style counts: kernel-object slots in use, threads running. */
int win32_obj_live(void){
    int n = 0;
    for (int i = 1; i < g_obj_n && i < OBJ_MAX; i++) if (g_obj[i].kind != OB_NONE) n++;
    return n;
}

/* ---- guest thread ---- */
#define GTHREAD_STACK 0x00100000u          /* 1 MB */
/* 16 stacks at 0x7E000000..0x7F000000, below the main stack (boot.c STACK_LO);
 * the game starts 8 threads.  (They were at 0x60000000, now the buffer heap's.) */
#define GTHREAD_TOP   0x7F000000u
static uint32_t g_tstack_next = 0x7E000000u;
uint64_t g_threads_started = 0, g_threads_exited = 0;

typedef struct { uint32_t entry, arg, teb; Obj *ob; } TArg;

void mem_altstack_install(void);
/* Guest threads need a BIG stack: in lifted code every guest call is a host C
 * call, and lifted frames are wide.  The main guest thread (tests/boot.c) got
 * 1 GB, but the worker threads the game opens with CreateThread got the macOS
 * default of 512 KB via `pthread_create(...,0,...)` -> a HOST STACK OVERFLOW in
 * deep recursion (SIGSEGV, an address outside guest space).  The reservation
 * is virtual address space; it is only committed as it gets used. */
/* Guest thread stacks: 1 MB slots in a small area (16 of them).  The game starts worker
 * threads at every race load, and TerminateThread used to do nothing, so they piled up and
 * the 16 slots ran out after ~9 races ("no room for another guest thread stack", exit 7).
 * Now slots are recycled when a thread ends, and TerminateThread really ends the thread
 * (at its next return from a wait/sleep, where it gets the guest lock back). */
static uint32_t g_tfree[64]; static int g_tfree_n = 0;
static _Thread_local uint32_t tl_stack_lo = 0;
static uint32_t tstack_get(void){
    uint32_t lo = 0;
    pthread_mutex_lock(&g_lock);
    if (g_tfree_n > 0) lo = g_tfree[--g_tfree_n];
    else if (g_tstack_next + GTHREAD_STACK <= GTHREAD_TOP){ lo = g_tstack_next; g_tstack_next += GTHREAD_STACK; }
    pthread_mutex_unlock(&g_lock);
    return lo;
}
static void tstack_put(uint32_t lo){
    if (!lo) return;
    pthread_mutex_lock(&g_lock);
    if (g_tfree_n < 64) g_tfree[g_tfree_n++] = lo;
    pthread_mutex_unlock(&g_lock);
}
/* TEBs: 0x2000 each from 0x00C20000; 0x00C60000 belongs to the timer thread.
 * They used to be handed out one after the other and never again, and the
 * game starts a thread per race load: after ~24 loads a new thread's TEB was
 * the timer thread's, and the next ones went on into whatever lies above.
 * A thread's TEB is now given back when it ends. */
#define TEB_FIRST 0x00C20000u
#define TEB_TIMER 0x00C60000u
static uint32_t g_teb_free[256]; static int g_nteb_free = 0;
static uint32_t g_teb_next = TEB_FIRST;
static uint64_t g_teb_reused = 0;
static uint32_t teb_take(void){                       /* g_lock held */
    if (g_nteb_free){ g_teb_reused++; return g_teb_free[--g_nteb_free]; }
    if (g_teb_next == TEB_TIMER) g_teb_next += 0x2000u;
    uint32_t t = g_teb_next; g_teb_next += 0x2000u;
    return t;
}
static void thread_report(void){
    fprintf(stderr, "  threads           : %llu started, %llu ended; TEBs %llu reused (next 0x%08x); critical sections %d of %d\n",
            (unsigned long long)g_threads_started, (unsigned long long)g_threads_exited,
            (unsigned long long)g_teb_reused, g_teb_next, g_cs_used, MAXCS);
    void win32_gil_report(void); win32_gil_report();
}
/* Windows' thread exit semantics for GetExitCodeThread (STILL_ACTIVE while a
 * thread runs, then its real exit code): NFSU2_THREAD_EXIT=windows.  Off by
 * default: the exe has always been told that every thread had ended with 0,
 * and its RealCore wait loop (0x6F5A04) spins until that is true, so with
 * the Windows answer it now yields while it polls a running thread. */
static int exit_semantics(void){
    static int g = -1;
    if (g < 0){ const char *e = getenv("NFSU2_THREAD_EXIT"); g = e && !strcasecmp(e, "windows"); }
    return g;
}
static int wait_thread_killed(void){ return tl_obj && ((Obj*)tl_obj)->terminate; }
/* The thread ended (its entry returned, ExitThread, or TerminateThread):
 * CPU slot, TEB and stack given back, exit code recorded, waiters woken; the
 * object's slot is freed if its last handle was closed already.  Called WITH
 * the guest lock held; does not return. */
static void guest_thread_die(uint32_t code){
    Obj *o = (Obj*)tl_obj;
    static uint64_t ends = 0;                         /* guest lock held: obj_reclaim's order */
    if (tl_cpu) unreg_cpu(tl_cpu);
    if (o){
        pthread_mutex_lock(&g_lock);
        if (o->teb && g_nteb_free < 256) g_teb_free[g_nteb_free++] = o->teb;
        pthread_mutex_unlock(&g_lock);
        pthread_mutex_lock(&o->mtx);
        o->teb = 0; o->exit_code = code; o->ended = 1; o->signaled = 1; o->end_seq = ++ends;
        pthread_cond_broadcast(&o->cv);
        int gone = o->closed;
        if (gone) o->kind = OB_NONE;
        pthread_mutex_unlock(&o->mtx);
        if (gone) obj_free_slot((int)(o - g_obj));
    }
    { static int sh = 0; if (thread_log() && sh++ < 200)
        fprintf(stderr, "  [thread] tid=%u ends (exit code %u), stack slot %08x recycled\n", o ? o->tid : 0u, code, tl_stack_lo); }
    tstack_put(tl_stack_lo); tl_stack_lo = 0;
    __sync_fetch_and_add(&g_threads_exited, 1);
    guest_unlock();
    pthread_exit(0);
}

static int guest_pthread_create(pthread_t *th, void *(*fn)(void*), void *arg){
    pthread_attr_t at;
    if (pthread_attr_init(&at) != 0) return pthread_create(th, 0, fn, arg);
    pthread_attr_setstacksize(&at, 256ull*1024ull*1024ull);
    int rc = pthread_create(th, &at, fn, arg);
    pthread_attr_destroy(&at);
    if (rc != 0) rc = pthread_create(th, 0, fn, arg);   /* last resort */
    return rc;
}

static void *guest_thread_main(void *p){
    mem_altstack_install();
    TArg *t = (TArg*)p;
    CPU cpu; memset(&cpu,0,sizeof cpu);
    uint32_t stack_lo, stack_hi;
    stack_lo = tstack_get();
    if (!stack_lo){
        fprintf(stderr, "  [thread] no room for another guest thread stack\n"); exit(7); }
    stack_hi = stack_lo + GTHREAD_STACK; tl_stack_lo = stack_lo;
    mem_commit(stack_lo, GTHREAD_STACK);
    memset(g_mem + stack_lo, 0, GTHREAD_STACK);     /* a recycled slot starts clean */
    memset(g_mem + t->teb, 0, 0x2000);              /* so does a recycled TEB (TLS, last error) */
    cpu.esp = stack_hi - 0x1000u;
    cpu.top = 0; cpu.fcw = 0x037f; cpu.mxcsr = 0x1F80u;
    cpu.fs_base = t->teb; cpu.gs_base = t->teb;
    /* TEB */
    MR32(t->teb+0x00)=0xFFFFFFFFu; MR32(t->teb+0x04)=stack_hi; MR32(t->teb+0x08)=stack_lo;
    MR32(t->teb+0x18)=t->teb; MR32(t->teb+0x24)=t->ob?t->ob->tid:0;
    MR32(t->teb+0x2C)=t->teb+0x1000u; MR32(t->teb+0x30)=0x00C10000u;
    /* stdcall: arg, then the return address */
    { CPU *c=&cpu; PUSH32(t->arg); PUSH32(0xDEAD7EADu); }
    __sync_fetch_and_add(&g_threads_started, 1);
    { static int sh=0; if (getenv("VERBOSE") && sh<40){ sh++;
        fprintf(stderr,"      [thread] STARTED entry=0x%08x arg=0x%08x teb=0x%08x tid=%u\n",
                t->entry, t->arg, t->teb, t->ob?t->ob->tid:0); } }
    tl_obj = t->ob;
    /* diagnostics: so it is recognizable in thread lists (perflog thread.csv, sample) */
    { char nm[32]; snprintf(nm, sizeof nm, "guest %u @%06x", t->ob ? t->ob->tid : 0u, t->entry & 0xFFFFFFu);
      pthread_setname_np(nm); }
    guest_lock(&cpu);
    dispatch_indirect(&cpu, t->entry);
    free(t);
    guest_thread_die(cpu.eax);                       /* returned normally */
    return 0;
}

void win32_signal_event(uint32_t h){
    Obj *o = obj_get(h);
    if (!o || o->kind != OB_EVENT) return;
    pthread_mutex_lock(&o->mtx);
    o->signaled = 1;
    pthread_cond_broadcast(&o->cv);
    pthread_mutex_unlock(&o->mtx);
}

/* ---- WINMM multimedia timer -------------------------------------------
 * The NFSU2 front end drives its update loop from a timeSetEvent callback; if
 * left as a stub the menu animations don't advance and input isn't processed.
 * The game re-arms the one-shot timer inside the callback, so opening a thread
 * per timer doesn't work: a SINGLE timer thread processes all entries in turn. */
#define MAXTIMER 32
typedef struct {
    uint32_t proc, user, id;
    uint64_t due_us;          /* 0 = empty */
    uint32_t period_us;       /* 0 = one-shot */
} Timer;

static Timer    g_tm[MAXTIMER];
static uint32_t g_timer_next_id = 1;
static int      g_timer_running = 0;
uint64_t        g_timer_ticks = 0;

/* Timers must also use GAME time; otherwise when the emulator is slow the
 * callbacks run far too often relative to the game's own time. */
uint64_t host_us(void);
static uint64_t now_us(void){ return host_us(); }

static void *timer_thread_main(void *p){
    (void)p;
    mem_altstack_install();
    CPU cpu; memset(&cpu,0,sizeof cpu);
    uint32_t stack_lo, stack_hi, teb;
    stack_lo = tstack_get();
    if (!stack_lo){
        fprintf(stderr, "  [thread] no room for another guest thread stack\n"); exit(7); }
    stack_hi = stack_lo + GTHREAD_STACK;
    teb = 0x00C60000u;
    mem_commit(stack_lo, GTHREAD_STACK);
    mem_commit(teb, 0x2000);
    cpu.top = 0; cpu.fcw = 0x037f; cpu.mxcsr = 0x1F80u;
    cpu.fs_base = teb; cpu.gs_base = teb;
    MR32(teb+0x00)=0xFFFFFFFFu; MR32(teb+0x04)=stack_hi; MR32(teb+0x08)=stack_lo;
    MR32(teb+0x18)=teb; MR32(teb+0x24)=999u;
    MR32(teb+0x2C)=teb+0x1000u; MR32(teb+0x30)=0x00C10000u;

    for (;;){
        struct timespec ts = {0, 1000000L};      /* 1 ms */
        nanosleep(&ts, 0);
        uint64_t now = now_us();
        for (int i = 0; i < MAXTIMER; i++){
            uint32_t proc, user, id;
            pthread_mutex_lock(&g_lock);
            if (!g_tm[i].due_us || g_tm[i].due_us > now){ pthread_mutex_unlock(&g_lock); continue; }
            proc = g_tm[i].proc; user = g_tm[i].user; id = g_tm[i].id;
            if (g_tm[i].period_us) g_tm[i].due_us = now + g_tm[i].period_us;
            else                   g_tm[i].due_us = 0;      /* a one-shot ends */
            pthread_mutex_unlock(&g_lock);

            cpu.esp = stack_hi - 0x1000u;
            { CPU *c=&cpu;
              /* stdcall: dw2, dw1, dwUser, uMsg, uTimerID  (right to left) */
              PUSH32(0u); PUSH32(0u); PUSH32(user); PUSH32(0u); PUSH32(id);
              PUSH32(0xDEAD7EADu); }
            guest_lock(&cpu);
            dispatch_indirect(&cpu, proc);
            guest_unlock();
            g_timer_ticks++;
        }
    }
    return 0;
}

/* ---- registry: in memory, "not found" default ---- */
/* If the game doesn't find a value it uses its own default - which is what we want. */
#define ERROR_SUCCESS         0u
#define ERROR_FILE_NOT_FOUND  2u

/* ---- exported API ---- */
static uint32_t A(CPU *c, int i){ return MR32(c->esp + 4u*(uint32_t)i); }

/* --- simple persistent registry ----------------------------------------
 * The settings the game writes (graphics detail, resolution, sound) used to be
 * thrown away.  Here they are kept and written to the ~/.nfsu2_registry file. */
#define MAXREG 128
static struct { char name[64]; int is_str; uint32_t dw; char sv[128]; } g_reg[MAXREG];
static int g_regn = 0;
static int g_reg_loaded = 0;

static const char *reg_path(void){
    static char pth[512];
    const char *h = getenv("HOME");
    snprintf(pth, sizeof pth, "%s/.nfsu2_registry", h ? h : ".");
    return pth;
}
static void reg_save(void);
static void reg_load(void){
    if (g_reg_loaded) return;
    g_reg_loaded = 1;
    FILE *f = fopen(reg_path(), "r");
    if (!f){
        /* regseed.c: no registry yet, the highest graphics instead of the
         * game's first-run check (NFSU2_SEED_REGISTRY=1) */
        int n = 0; const char *const *seed = 0;
        { const char *const *regseed_lines(int *); seed = regseed_lines(&n); }
        for (int k = 0; k < n && g_regn < MAXREG; k++){
            char nm[64]; unsigned dw = 0;
            if (sscanf(seed[k], "d %63[^=]=%u", nm, &dw) != 2) continue;
            snprintf(g_reg[g_regn].name, 64, "%s", nm);
            g_reg[g_regn].is_str = 0; g_reg[g_regn].dw = dw; g_regn++;
        }
        if (n){
            snprintf(g_reg[g_regn].name, 64, "PortSettingsRepaired");
            g_reg[g_regn].is_str = 0; g_reg[g_regn].dw = 1; g_regn++;
            reg_save();
            fprintf(stderr, "registry: first launch, seeded with the highest graphics settings (%d values,"
                            " NFSU2_SEED_REGISTRY); the game's first-run check is skipped\n", n);
        }
        return;
    }
    char line[256];
    while (fgets(line, sizeof line, f) && g_regn < MAXREG){
        char nm[64], val[128]; int isstr = 0; unsigned dw = 0;
        if (sscanf(line, "d %63[^=]=%u", nm, &dw) == 2){
            snprintf(g_reg[g_regn].name, 64, "%s", nm);
            g_reg[g_regn].is_str = 0; g_reg[g_regn].dw = dw; g_regn++;
        } else if (sscanf(line, "s %63[^=]=%127[^\n]", nm, val) == 2){
            snprintf(g_reg[g_regn].name, 64, "%s", nm);
            snprintf(g_reg[g_regn].sv, 128, "%s", val);
            g_reg[g_regn].is_str = 1; g_regn++;
        }
        (void)isstr;
    }
    fclose(f);
    /* One-time repair.  Before 2026-10-25 the game's first-run hardware detection
     * measured a 0 MHz CPU (EFLAGS ID bit, see eflags_get in cpu.h) and saved every
     * graphics option at its minimum, then NotFirstTime=1, so it never detected
     * again: no crowds, short draw distance (pop-in), no reflections.  If the saved
     * settings carry exactly that signature, drop NotFirstTime and the g_* values
     * so the next launch detects again.  Done once (PortSettingsRepaired). */
    int fixed = 0, zero = 0;
    for (int i = 0; i < g_regn; i++){
        if (!strcasecmp(g_reg[i].name, "PortSettingsRepaired")) fixed = 1;
        if (!g_reg[i].is_str && g_reg[i].dw == 0 &&
            (!strcasecmp(g_reg[i].name, "g_PerformanceLevel") ||
             !strcasecmp(g_reg[i].name, "g_WorldLodLevel") ||
             !strcasecmp(g_reg[i].name, "g_CarLodLevel") ||
             !strcasecmp(g_reg[i].name, "g_CrowdEnable"))) zero++;
    }
    if (!fixed && g_regn < MAXREG){
        if (zero == 4){
            int k = 0;
            for (int i = 0; i < g_regn; i++){
                if (!strncmp(g_reg[i].name, "g_", 2) ||
                    !strcasecmp(g_reg[i].name, "NotFirstTime")) continue;
                if (k != i) g_reg[k] = g_reg[i];
                k++;
            }
            g_regn = k;
            fprintf(stderr, "registry: minimum settings from the old hardware detection"
                            " found; detecting again\n");
        }
        snprintf(g_reg[g_regn].name, 64, "PortSettingsRepaired");
        g_reg[g_regn].is_str = 0; g_reg[g_regn].dw = 1; g_regn++;
        reg_save();
    }
}
/* Written to "<file>.tmp" and renamed over the old file, so quitting (or a
 * crash) in the middle of the game's 29 back-to-back RegSetValueExA calls can
 * never leave a truncated registry behind (from th0mk's nfsu2-web). */
static void reg_save(void){
    char tmp[600]; snprintf(tmp, sizeof tmp, "%s.tmp", reg_path());
    FILE *f = fopen(tmp, "w");
    if (!f) return;
    for (int i = 0; i < g_regn; i++){
        if (g_reg[i].is_str) fprintf(f, "s %s=%s\n", g_reg[i].name, g_reg[i].sv);
        else                 fprintf(f, "d %s=%u\n", g_reg[i].name, g_reg[i].dw);
    }
    if (fclose(f) == 0) rename(tmp, reg_path());
    else unlink(tmp);
}
static int reg_find(const char *nm){
    reg_load();
    for (int i = 0; i < g_regn; i++)
        if (!strcasecmp(g_reg[i].name, nm)) return i;
    return -1;
}
static void reg_put_dword(const char *nm, uint32_t v){
    int i = reg_find(nm);
    if (i < 0){ if (g_regn >= MAXREG) return; i = g_regn++;
                snprintf(g_reg[i].name, 64, "%s", nm); }
    g_reg[i].is_str = 0; g_reg[i].dw = v; reg_save();
}
static void reg_put_string(const char *nm, const char *v){
    int i = reg_find(nm);
    if (i < 0){ if (g_regn >= MAXREG) return; i = g_regn++;
                snprintf(g_reg[i].name, 64, "%s", nm); }
    g_reg[i].is_str = 1; snprintf(g_reg[i].sv, 128, "%s", v); reg_save();
}

/* For the runtime's own settings in the same registry file (powerunits.c,
 * hornmenu.c's HornVolume): read, and set with the file written at once. */
int win32_reg_get_dword(const char *nm, uint32_t *out){
    int i = reg_find(nm);
    if (i < 0 || g_reg[i].is_str) return 0;
    *out = g_reg[i].dw;
    return 1;
}
void win32_reg_put_dword(const char *nm, uint32_t v){ reg_put_dword(nm, v); }

int win32_ext_call(CPU *c, const char *n, uint32_t *out){
    uint32_t r = 0;
    /* --- Registry --- */
    if (!strcmp(n,"RegOpenKeyA")){ uint32_t p=A(c,2); if(p) MR32(p)=obj_new(OB_KEY); r=ERROR_SUCCESS; }
    else if (!strcmp(n,"RegOpenKeyExA")){
        if (getenv("REGLOG")){ uint32_t sp=A(c,1);
            fprintf(stderr,"  [registry] OpenKeyEx(\"%s\")\n",
                    (sp && mem_is_committed(sp)) ? (const char*)(g_mem+sp) : "(null)"); }
        uint32_t p=A(c,4); if(p) MR32(p)=obj_new(OB_KEY); r=ERROR_SUCCESS; }
    else if (!strcmp(n,"RegCreateKeyA")){ uint32_t p=A(c,2); if(p) MR32(p)=obj_new(OB_KEY); r=ERROR_SUCCESS; }
    else if (!strcmp(n,"RegCreateKeyExA")){ uint32_t p=A(c,7); if(p) MR32(p)=obj_new(OB_KEY); r=ERROR_SUCCESS; }
    else if (!strcmp(n,"RegQueryValueExA")){
        /* An empty registry sends the game down the "first install" path ON EVERY
         * LAUNCH (NotFirstTime isn't found), and without install information the
         * front-end flow doesn't progress.  We return a reasonable
         * installed-game profile. */
        uint32_t nameptr=A(c,1), ptype=A(c,3), pdata=A(c,4), pcb=A(c,5);
        const char *vn = (nameptr && mem_is_committed(nameptr))
                         ? (const char*)(g_mem+nameptr) : "";
        if (getenv("REGLOG"))
            fprintf(stderr,"  [registry] QueryValue(\"%s\")\n", vn);

        const char *sval = 0; uint32_t dval = 0; int have_d = 0;
        const char *language_registry(void);    /* runtime/language.c: NFSU2_LANGUAGE */
        int set_lang = !strcasecmp(vn,"Language") && language_registry();
        { int ri = set_lang ? -1 : reg_find(vn);   /* look at the SAVED value first */
          if (ri >= 0){
              if (g_reg[ri].is_str) sval = g_reg[ri].sv;
              else { dval = g_reg[ri].dw; have_d = 1; }
          } }
        if (sval || have_d) { /* the saved value will be used */ }
        /* NotFirstTime is NOT faked any more: it used to read 1 on an empty
         * registry (from the days when writes were dropped and every launch was
         * a "first launch"), so the game never ran its first-run hardware
         * detection and kept every graphics setting at 0.  Writes persist now: the
         * first launch detects, writes NotFirstTime=1 itself, and later launches
         * read it back.  REGFIRST=1 restores the fake. */
        else if (!strcasecmp(vn,"NotFirstTime") && getenv("REGFIRST")){ dval=1; have_d=1; }
        else if (set_lang)                        sval=language_registry();
        else if (!strcasecmp(vn,"Language"))      sval="English";
        else if (!strcasecmp(vn,"Install Dir"))   sval="C:\\NFSU2";
        else if (!strcasecmp(vn,"CD Drive"))      sval="C:\\NFSU2";
        else if (!strcasecmp(vn,"StreamingInstall")){ dval=0; have_d=1; }
        else if (!strcasecmp(vn,"VERSION"))       sval="1.2.0.0";
        else if (!strcasecmp(vn,"SIZE")){ dval=0; have_d=1; }
        /* HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0 "~MHz".  The movie
         * player's timer (sub_006f625d) reads it; without it the timer calibrates
         * RDTSC against QueryPerformanceCounter, waiting for two measurements that
         * agree.  Our QPC is the virtual clock and RDTSC is real time, so they never
         * agree and the first movie hung for ever.  3000 matches rdtsc_shim (3 GHz). */
        else if (!strcasecmp(vn,"~MHz")){ dval=3000; have_d=1; }

        if (sval){
            uint32_t need = (uint32_t)strlen(sval) + 1u;
            if (ptype){ mem_commit(ptype,4); MR32(ptype)=1u; }      /* REG_SZ */
            if (!pdata){ if(pcb){ mem_commit(pcb,4); MR32(pcb)=need; } r=ERROR_SUCCESS; }
            else {
                uint32_t cap = pcb ? MR32(pcb) : need;
                if (cap < need){ if(pcb) MR32(pcb)=need; r=234u; } /* ERROR_MORE_DATA */
                else { mem_commit(pdata,need); memcpy(g_mem+pdata, sval, need);
                       if(pcb) MR32(pcb)=need; r=ERROR_SUCCESS; }
            }
        } else if (have_d){
            if (ptype){ mem_commit(ptype,4); MR32(ptype)=4u; }      /* REG_DWORD */
            if (!pdata){ if(pcb){ mem_commit(pcb,4); MR32(pcb)=4u; } r=ERROR_SUCCESS; }
            else {
                uint32_t cap = pcb ? MR32(pcb) : 4u;
                if (cap < 4u){ if(pcb) MR32(pcb)=4u; r=234u; }
                else { mem_commit(pdata,4); MR32(pdata)=dval;
                       if(pcb) MR32(pcb)=4u; r=ERROR_SUCCESS; }
            }
        } else {
            if(pcb){ mem_commit(pcb,4); MR32(pcb)=0; }
            r=ERROR_FILE_NOT_FOUND;
        }
    }
    else if (!strcmp(n,"RegQueryValueA")){ r=ERROR_FILE_NOT_FOUND; }
    else if (!strcmp(n,"RegSetValueExA")||!strcmp(n,"RegSetValueA")){
        /* Writes used to be SILENTLY DROPPED: the graphics/sound settings the game
         * saved were reset on every launch.  Now they are kept and written to
         * disk. */
        uint32_t nameptr=A(c,1), type=A(c,3), pdata=A(c,4), cb=A(c,5);
        const char *vn = (nameptr && mem_is_committed(nameptr))
                         ? (const char*)(g_mem+nameptr) : "";
        if (*vn){
            if (type == 4u && pdata && mem_is_committed(pdata+3))
                reg_put_dword(vn, MR32(pdata));
            else if (type == 1u && pdata && mem_is_committed(pdata))
                reg_put_string(vn, (const char*)(g_mem+pdata));
            if (getenv("REGLOG"))
                fprintf(stderr,"  [registry] SetValue(\"%s\") type=%u size=%u\n", vn, type, cb);
        }
        r=ERROR_SUCCESS; }
    else if (!strcmp(n,"RegCloseKey")){ Obj *o = obj_get(A(c,0)); if (o && o->kind == OB_KEY) obj_close(A(c,0)); r=ERROR_SUCCESS; }
    else if (!strcmp(n,"RegDeleteKeyA")||!strcmp(n,"RegDeleteValueA")) r=ERROR_SUCCESS;
    else if (!strcmp(n,"RegEnumKeyExA")||!strcmp(n,"RegEnumValueA")) r=259u; /* ERROR_NO_MORE_ITEMS */
    /* --- window / USER32 --- */
    /* The window message path.  DirectInput devices are only Acquired when the
     * application gets FOCUS; the game learns this from the
     * WM_ACTIVATEAPP/WM_SETFOCUS messages.  Since PeekMessage always returned 0
     * and DispatchMessage never called the window procedure, the game never said
     * "I'm active" -> the keyboard was never Acquired.                  */

    else if (!strcmp(n,"RegisterClassExA")||!strcmp(n,"RegisterClassA")){
        /* WNDCLASSEXA: +8 lpfnWndProc | WNDCLASSA: +4 lpfnWndProc */
        uint32_t wc=A(c,0);
        if (wc && mem_is_committed(wc+11)){
            uint32_t off = !strcmp(n,"RegisterClassExA") ? 8u : 4u;
            uint32_t wp = MR32(wc+off);
            if (wp) { g_wndproc = wp;
                fprintf(stderr,"  [window] class registered, procedure=0x%08x\n", wp); }
        }
        r=0xC001u; }
    else if (!strcmp(n,"UnregisterClassA")) r=1;
    else if (!strcmp(n,"CreateWindowExA")){
        r = g_hwnd;
        if (!g_wm_activated){ g_wm_activated = 1;
            wm_push(0x0018u, 1u, 0u);   /* WM_SHOWWINDOW  */
            wm_push(0x001Cu, 1u, 0u);   /* WM_ACTIVATEAPP  active */
            wm_push(0x0006u, 1u, 0u);   /* WM_ACTIVATE     WA_ACTIVE */
            wm_push(0x0007u, 0u, 0u);   /* WM_SETFOCUS     */
            wm_push(0x000Fu, 0u, 0u);   /* WM_PAINT        */
        } }
    else if (!strcmp(n,"DestroyWindow")) r=1;
    else if (!strcmp(n,"GetDesktopWindow")) r=0x00B00000u;
    else if (!strcmp(n,"GetActiveWindow")||!strcmp(n,"GetForegroundWindow")) r=0x00B00001u;
    else if (!strcmp(n,"LoadIconA")||!strcmp(n,"LoadCursorA")) r=0x00B10001u;
    else if (!strcmp(n,"SetCursor")) r=0x00B10001u;
    else if (!strcmp(n,"ShowCursor")){ static int cnt=0; r=(uint32_t)(A(c,0)?++cnt:--cnt); }
    else if (!strcmp(n,"GetCursorPos")){ uint32_t p=A(c,0);
        if(p){ int mx=0,my=0; void metal_get_cursor(int*,int*); metal_get_cursor(&mx,&my);
               mem_commit(p,8); MR32(p)=(uint32_t)mx; MR32(p+4)=(uint32_t)my; } r=1; }
    else if (!strcmp(n,"SetCursorPos")) r=1;
    else if (!strcmp(n,"GetSystemMetrics")){
        unsigned gw = 1280, gh = 720; void metal_game_size(unsigned*,unsigned*); metal_game_size(&gw,&gh);
        switch(A(c,0)){ case 0: r=gw; break; case 1: r=gh; break;
                        case 4: r=19; break; case 5: r=1; break; case 6: r=1; break;
                        case 32: r=4; case 33: r=4; break; default: r=0; } }
    else if (!strcmp(n,"AdjustWindowRect")){ r=1; }
    else if (!strcmp(n,"GetClientRect")||!strcmp(n,"GetWindowRect")){
        /* The game's real resolution: cursor mapping follows it (see
         * metal_game_size). */
        unsigned gw = 1280, gh = 720; void metal_game_size(unsigned*,unsigned*); metal_game_size(&gw,&gh);
        uint32_t p=A(c,1); if(p){mem_commit(p,16);MR32(p)=0;MR32(p+4)=0;MR32(p+8)=gw;MR32(p+12)=gh;} r=1; }
    else if (!strcmp(n,"ShowWindow")||!strcmp(n,"UpdateWindow")||!strcmp(n,"SetFocus")
           ||!strcmp(n,"SetForegroundWindow")||!strcmp(n,"SetWindowPos")
           ||!strcmp(n,"InvalidateRect")||!strcmp(n,"SetWindowTextA")) r=1;
    else if (!strcmp(n,"SetWindowLongA")||!strcmp(n,"GetWindowLongA")) r=0;
    else if (!strcmp(n,"PeekMessageA")||!strcmp(n,"GetMessageA")){
        /* MSG: +0 hwnd +4 message +8 wParam +12 lParam +16 time +20 pt */
        uint32_t pm=A(c,0), m=0, wp=0, lp=0;
        int remove = !strcmp(n,"GetMessageA") ? 1 : (A(c,4) & 1u);
        if (g_wmq_head != g_wmq_tail){
            if (remove) wm_pop(&m,&wp,&lp);
            else { m=g_wmq[g_wmq_head].msg; wp=g_wmq[g_wmq_head].wp; lp=g_wmq[g_wmq_head].lp; }
            if (pm){ mem_commit(pm,28);
                MR32(pm)=g_hwnd; MR32(pm+4)=m; MR32(pm+8)=wp; MR32(pm+12)=lp;
                MR32(pm+16)=0; MR32(pm+20)=0; MR32(pm+24)=0; }
            g_wm_sent++;
            r=1;
        } else if ((wp = (uint32_t)metal_take_char(remove)) != 0xFFFFFFFFu){
            /* A typed character (see metal.m char_push).  The WM_CHAR that Windows's
             * TranslateMessage would produce; lParam: repeat=1. */
            if (pm){ mem_commit(pm,28);
                MR32(pm)=g_hwnd; MR32(pm+4)=0x0102u; MR32(pm+8)=wp; MR32(pm+12)=1u;
                MR32(pm+16)=0; MR32(pm+20)=0; MR32(pm+24)=0; }
            g_wm_sent++;
            r=1;
        } else {
            if (pm){ mem_commit(pm,28); memset(g_mem+pm,0,28); MR32(pm)=g_hwnd; }
            r = !strcmp(n,"GetMessageA") ? 1u : 0u;   /* GetMessage 0 = WM_QUIT */
        }
    }
    else if (!strcmp(n,"DispatchMessageA")){
        uint32_t pm=A(c,0);
        if (g_wndproc && pm && mem_is_committed(pm+15)){
            uint32_t args[4] = { MR32(pm), MR32(pm+4), MR32(pm+8), MR32(pm+12) };
            if (args[1]){ g_wm_dispatched++; r = call_guest(c, g_wndproc, 4, args); }
        }
    }
    else if (!strcmp(n,"TranslateMessage")
           ||!strcmp(n,"DefWindowProcA")||!strcmp(n,"PostMessageA")
           ||!strcmp(n,"SendMessageA")||!strcmp(n,"PostQuitMessage")) r=0;
    else if (!strcmp(n,"ReleaseCapture")||!strcmp(n,"SetCapture")) r=1;
    else if (!strcmp(n,"IsIconic")) r=0;
    else if (!strcmp(n,"GetKeyboardState")){ uint32_t p=A(c,0); if(p){mem_commit(p,256);memset(g_mem+p,0,256);} r=1; }
    else if (!strcmp(n,"GetAsyncKeyState")) r=0;
    /* --- synchronization --- */
    else if (!strcmp(n,"CreateEventA")){
        uint32_t h=obj_new(OB_EVENT); Obj*o=obj_get(h);
        if(o){ o->manual=(int)A(c,1); o->signaled=(int)A(c,2); } r=h; }
    else if (!strcmp(n,"SetEvent")){ Obj*o=obj_get(A(c,0));
        { uint32_t h=A(c,0);
          if (h>=H_BASE && h<H_BASE+64){ g_wstat[h-H_BASE].sets++;
            g_wstat[h-H_BASE].setter_tid =
                (c->fs_base && mem_is_committed(c->fs_base+0x24u))
                ? MR32(c->fs_base+0x24u) : 0u; } }
        if(o){ pthread_mutex_lock(&o->mtx); o->signaled=1; pthread_cond_broadcast(&o->cv); pthread_mutex_unlock(&o->mtx);} r=1; }
    else if (!strcmp(n,"ResetEvent")){ Obj*o=obj_get(A(c,0));
        if(o){ pthread_mutex_lock(&o->mtx); o->signaled=0; pthread_mutex_unlock(&o->mtx);} r=1; }
    else if (!strcmp(n,"CreateMutexA")){
        uint32_t h=obj_new(OB_MUTEX); Obj*o=obj_get(h);
        if(o){ if (A(c,1)){ o->signaled=0; o->owner_tid=cur_tid(c); o->rec=1; }
               else       { o->signaled=1; o->owner_tid=0; o->rec=0; } }
        r=h; }
    else if (!strcmp(n,"ReleaseMutex")){
        Obj*o=obj_get(A(c,0)); uint32_t me=cur_tid(c);
        r=0;
        if(o){ pthread_mutex_lock(&o->mtx);
               if (o->kind == OB_MUTEX){
                   if (o->owner_tid == me && o->rec > 0){
                       if (--o->rec == 0){ o->owner_tid = 0; o->signaled = 1;
                                           pthread_cond_broadcast(&o->cv); }
                       r=1;
                   } else r=0;            /* we aren't the owner */
               } else { o->signaled=1; pthread_cond_broadcast(&o->cv); r=1; }
               pthread_mutex_unlock(&o->mtx); }
    }
    else if (!strcmp(n,"CreateSemaphoreA")){ uint32_t h=obj_new(OB_SEM); Obj*o=obj_get(h); if(o) o->signaled=(int)A(c,1); r=h; }
    else if (!strcmp(n,"ReleaseSemaphore")){ Obj*o=obj_get(A(c,0));
        if(o){ pthread_mutex_lock(&o->mtx); o->signaled+=(int)A(c,1); pthread_cond_broadcast(&o->cv); pthread_mutex_unlock(&o->mtx);} r=1; }
    else if (!strcmp(n,"WaitForSingleObject")){
        Obj*o=obj_get(A(c,0)); uint32_t ms=A(c,1);
        { uint32_t h=A(c,0);
          uint32_t tid = (c->fs_base && mem_is_committed(c->fs_base+0x24u))
                         ? MR32(c->fs_base+0x24u) : 0u;
          if (h>=H_BASE && h<H_BASE+64){ g_wstat[h-H_BASE].waits++;
                                         g_wstat[h-H_BASE].waiter_tid = tid; }
          static int sh=0;
          if (++sh % 400 == 0){
            fprintf(stderr,"  [event] handle  type  signal  wait  SetEvent  waiting-tid\n");
            for (int i=0;i<64;i++) if (g_wstat[i].waits || g_wstat[i].sets)
                fprintf(stderr, "         h%-4d %3d %6d %8llu %9llu  tid=%u\n", i,
                        g_obj[i].kind, g_obj[i].signaled,
                        (unsigned long long)g_wstat[i].waits,
                        (unsigned long long)g_wstat[i].sets,
                        g_wstat[i].waiter_tid);
          } }
        if(!o){ r=0; }
        else if (o->kind == OB_MUTEX && (tl_noyield || gil_keep_for_mutex()) && mutex_take_now(o, cur_tid(c))){ if (!tl_noyield) g_gil_kept++; r=0; }   /* WAIT_OBJECT_0 */
        else {
            /* MUTEX: ownership + RECURSION (wait_ready).  The same thread must be able to take
             * the same mutex again; otherwise the game's CRT wrapper that takes nested locks
             * deadlocks itself (this is how the video player froze). */
            uint32_t me = cur_tid(c);
            uint64_t deadline = wait_deadline(ms, o->kind == OB_MUTEX && ms == 0xFFFFFFFFu ? ms : 2000u), us;
            ts_set(TS_WAIT, A(c,0));
            guest_yield_begin();
            pthread_mutex_lock(&o->mtx);
            while (!wait_ready(o, me) && !wait_thread_killed() && (us = wait_slice(deadline, 50000u))){
                struct timespec ts = { (time_t)(us / 1000000u), (long)(us % 1000000u) * 1000L };
                pthread_cond_timedwait_relative_np(&o->cv, &o->mtx, &ts);
            }
            r = wait_ready(o, me) ? 0u : 0x102u;        /* WAIT_OBJECT_0 / WAIT_TIMEOUT */
            if (!r) wait_take(o, me);
            pthread_mutex_unlock(&o->mtx);
            guest_yield_end();
        } }
    /* --- thread --- */
    else if (!strcmp(n,"CreateThread")){
        uint32_t entry=A(c,2), arg=A(c,3), ptid=A(c,5);
        { static int sc=0; if (thread_log() && sc++ < 200) fprintf(stderr, "  [thread] CreateThread entry=0x%08x arg=0x%08x flags=0x%x\n", entry, arg, A(c,4)); }
        { static int sh=0; if (getenv("VERBOSE") && sh<40){ sh++;
            fprintf(stderr,"      [thread] CreateThread(attr=0x%08x stack=0x%x entry=0x%08x arg=0x%08x flags=0x%x ptid=0x%08x)\n",
                    A(c,0),A(c,1),entry,arg,A(c,4),ptid); } }
        uint32_t h=obj_new(OB_THREAD); Obj*o=obj_get(h);
        static uint32_t next_tid=100;
        if(o){
            o->tid = ++next_tid; o->guest_entry = entry; o->guest_arg = arg;
            o->creator = c->eip; o->looked = 0;   /* the return address; the game's own lookups count from here */
            if(ptid) MR32(ptid)=o->tid;
            uint32_t teb;
            pthread_mutex_lock(&g_lock);
            teb = teb_take();
            pthread_mutex_unlock(&g_lock);
            o->teb = teb;
            mem_commit(teb, 0x2000);
            TArg *t = calloc(1,sizeof *t);
            t->entry=entry; t->arg=arg; t->teb=teb; t->ob=o;
            o->pending = t;
            if (A(c,4) & 0x4u){                 /* CREATE_SUSPENDED */
                o->started = 0;                 /* ResumeThread will wait */
            } else {
                if (guest_pthread_create(&o->th,guest_thread_main,t)==0){
                    o->started=1; o->pending=0; pthread_detach(o->th);
                } else free(t);
            }
        }
        r=h; }
    else if (!strcmp(n,"GetCurrentThread")) r=0xFFFFFFFEu;
    else if (!strcmp(n,"ResumeThread")){
        Obj*o=obj_get(A(c,0));
        if (o && !o->started && o->pending){
            if (guest_pthread_create(&o->th,guest_thread_main,o->pending)==0){
                o->started=1; o->pending=0; pthread_detach(o->th); }
        }
        r=1; }
    else if (!strcmp(n,"SuspendThread")) r=0;
    else if (!strcmp(n,"ExitThread")){
        /* REALLY terminate the guest thread. Otherwise execution falls from
         * _endthreadex into the _threadstartex prologue and the thread restarts itself. */
        guest_thread_die(A(c,0));
        r=1; }
    else if (!strcmp(n,"TerminateThread")){
        Obj *to = obj_get(A(c,0));
        { static int sh = 0; if (thread_log() && sh++ < 200)
            fprintf(stderr, "  [thread] TerminateThread tid=%u%s\n", to ? to->tid : 0u, to == tl_obj ? " (self)" : ""); }
        if (to && to->kind == OB_THREAD){
            if (to == (Obj*)tl_obj) guest_thread_die(A(c,1));
            if (!to->ended && !to->terminate) to->exit_code = A(c,1);
            to->terminate = 1;
        }
        r=1; }
    else if (!strcmp(n,"GetExitCodeThread")){
        uint32_t h=A(c,0), p=A(c,1); Obj *o = obj_get(h);           /* looked up: obj_reclaim keeps it */
        if (!exit_semantics()){ if(p) MR32(p)=0; r=1; }             /* the old answer: ended, with 0 */
        else if (h == 0xFFFFFFFEu){ if(p) MR32(p)=0x103u; r=1; }   /* GetCurrentThread() */
        else if (!o || o->kind != OB_THREAD) r=0;
        else {
            uint32_t code = o->ended ? o->exit_code : 0x103u;        /* STILL_ACTIVE */
            if (p){ mem_commit(p,4); MR32(p)=code; }
            r=1;
            { static int sh = 0; if (thread_log() && o->ended && sh++ < 64)
                fprintf(stderr, "  [thread] GetExitCodeThread(tid=%u) -> %u\n", o->tid, code); }
            /* A poll loop without a sleep (RealCore 0x6F5A04): on Windows the
             * scheduler would run the thread it waits for, here that thread
             * needs the guest lock: give it up for a moment. */
            if (!o->ended){ guest_yield_begin(); struct timespec ts={0,1000000L}; nanosleep(&ts,0); guest_yield_end(); }
        } }
    else if (!strcmp(n,"SetThreadAffinityMask")||!strcmp(n,"SetProcessAffinityMask")) r=1;
    else if (!strcmp(n,"GetProcessAffinityMask")){
        uint32_t a=A(c,1),b=A(c,2); if(a) MR32(a)=0xFF; if(b) MR32(b)=0xFF; r=1; }
    else if (!strcmp(n,"SetPriorityClass")) r=1;
    else if (!strcmp(n,"GetPriorityClass")) r=0x20;
    /* --- handles / misc --- */
    else if (!strcmp(n,"Sleep")){
        uint32_t ms=A(c,0);
        ts_set(TS_SLEEP, ms);
        guest_yield_begin();
        { struct timespec ts={ (time_t)(ms/1000u), (long)((ms%1000u)*1000000u) };
          if(!ms){ ts.tv_nsec = 200000L; }        /* Sleep(0): just yield */
          nanosleep(&ts,0); }
        guest_yield_end();
        r=0; }
    else if (!strcmp(n,"SleepEx")){
        uint32_t ms=A(c,0);
        ts_set(TS_SLEEP, ms);
        guest_yield_begin();
        { struct timespec ts={ (time_t)(ms/1000u), (long)((ms%1000u)*1000000u) };
          if(!ms) ts.tv_nsec = 200000L;
          nanosleep(&ts,0); }
        guest_yield_end();
        r=0; }
    else if (!strcmp(n,"WaitForMultipleObjects")){
        uint32_t cnt=A(c,0), parr=A(c,1), waitall=A(c,2), ms=A(c,3);
        /* Unknown handles are skipped, as before.  Wait-all checks and takes every object
         * under all of their locks, taken in address order: a partial take could hand an
         * auto-reset event or a semaphore count to two waiters. */
        Obj *objs[64], *locks[64];
        uint32_t idx[64], nobj = 0, nl = 0, me = cur_tid(c);
        if (!cnt || cnt > 64u || !parr || !mem_is_committed(parr) || !mem_is_committed(parr + 4u*cnt - 1u)){
            r = 0xFFFFFFFFu;                                         /* WAIT_FAILED */
        } else {
            for (uint32_t i = 0; i < cnt; i++){
                Obj *o = obj_get(MR32(parr + 4u*i));
                if (!o) continue;
                objs[nobj] = o; idx[nobj++] = i;
                uint32_t j = 0;
                while (j < nl && locks[j] < o) j++;
                if (j < nl && locks[j] == o) continue;                /* the same object twice */
                memmove(locks + j + 1u, locks + j, (nl - j) * sizeof *locks);
                locks[j] = o; nl++;
            }
            uint64_t deadline = wait_deadline(ms, 200u), us;
            ts_set(TS_WAITM, MR32(parr));
            guest_yield_begin();
            for (;;){
                uint32_t got = 0x102u;
                if (waitall && nl){
                    for (uint32_t i = 0; i < nl; i++) pthread_mutex_lock(&locks[i]->mtx);
                    uint32_t ready = 0;
                    for (uint32_t i = 0; i < nl; i++) ready += wait_ready(locks[i], me) != 0;
                    if (ready == nl){ for (uint32_t i = 0; i < nl; i++) wait_take(locks[i], me); got = 0; }
                    for (uint32_t i = nl; i > 0; i--) pthread_mutex_unlock(&locks[i-1u]->mtx);
                } else if (!waitall){
                    for (uint32_t k = 0; k < nobj && got == 0x102u; k++){
                        pthread_mutex_lock(&objs[k]->mtx);
                        if (wait_ready(objs[k], me)){ wait_take(objs[k], me); got = idx[k]; }
                        pthread_mutex_unlock(&objs[k]->mtx);
                    }
                }
                r = got;
                if (got != 0x102u || wait_thread_killed() || !(us = wait_slice(deadline, 1000u))) break;
                struct timespec ts = { 0, (long)us * 1000L }; nanosleep(&ts, 0);
            }
            guest_yield_end();
        } }
    else if (!strcmp(n,"SwitchToThread")){ guest_yield_begin(); sched_yield(); guest_yield_end(); r=1; }
    else if (!strcmp(n,"CloseHandle")){ obj_close(A(c,0)); r=1; }
    else if (!strcmp(n,"DuplicateHandle")){ uint32_t p=A(c,3); if(p) MR32(p)=A(c,1);
        { Obj *o = obj_get(A(c,1)); if (o){ pthread_mutex_lock(&o->mtx); o->refs++; pthread_mutex_unlock(&o->mtx); } }
        r=1; }
    else if (!strcmp(n,"SetErrorMode")) r=0;
    else if (!strcmp(n,"GetLogicalDrives")) r=0x0000000Cu;             /* C: and D: */
    else if (!strcmp(n,"GetDriveTypeA")){
#if NFS_EXE_NA
        /* The North American v1.2 no-CD executable still looks for a CD-ROM
         * drive (sub_005bf450: GetDriveTypeA == DRIVE_CDROM; the disc contents
         * check is patched out) and otherwise shows "Please insert Disc 2"
         * forever.  D: is that drive; paths on it resolve to the game folder. */
        uint32_t p=A(c,0); char d = p ? (char)MR8(p) : 'C';
        r = (d=='D' || d=='d') ? 5u : 3u;                                  /* DRIVE_CDROM : DRIVE_FIXED */
#else
        r=3;                                                           /* DRIVE_FIXED */
#endif
    }
    else if (!strcmp(n,"GetCurrentDirectoryA")){
        uint32_t p=A(c,1); const char*s="C:\\NFSU2"; uint32_t l=(uint32_t)strlen(s);
        if(p){ mem_commit(p,l+1); memcpy(g_mem+p,s,l); MR8(p+l)=0; } r=l; }
    else if (!strcmp(n,"SetCurrentDirectoryA")) r=1;
    else if (!strcmp(n,"GetLongPathNameA")||!strcmp(n,"GetShortPathNameA")){
        uint32_t src=A(c,0), dst=A(c,1), sz=A(c,2);
        uint32_t l = src? (uint32_t)strlen((char*)(g_mem+src)) : 0;
        if(dst && sz>l){ memcpy(g_mem+dst, g_mem+src, l+1); }
        r=l; }
    /* The timestamps of save files (the WIN32_FIND_DATA FILETIMEs).  When a profile
     * is found the game feeds them into the CRT's localtime; they used to be
     * unimplemented -> garbage -> localtime NULL -> crash at guest address 0x14
     * (tm_year).  They were never called until a profile had been saved. */
    else if (!strcmp(n,"FileTimeToLocalFileTime")||!strcmp(n,"LocalFileTimeToFileTime")){
        uint32_t s=A(c,0), d=A(c,1); r=0;
        if (s && d && mem_is_committed(s+7)){
            uint64_t ft = (uint64_t)MR32(s) | ((uint64_t)MR32(s+4) << 32);
            time_t t = time(0); struct tm lt; localtime_r(&t, &lt);
            int64_t off = (int64_t)lt.tm_gmtoff * 10000000ll;
            ft = !strcmp(n,"FileTimeToLocalFileTime") ? ft + (uint64_t)off : ft - (uint64_t)off;
            mem_commit(d,8); MR32(d)=(uint32_t)ft; MR32(d+4)=(uint32_t)(ft>>32); r=1; } }
    else if (!strcmp(n,"FileTimeToSystemTime")){
        /* SYSTEMTIME: wYear wMonth wDayOfWeek wDay wHour wMinute wSecond wMs */
        uint32_t s=A(c,0), d=A(c,1); r=0;
        if (s && d && mem_is_committed(s+7)){
            uint64_t ft = (uint64_t)MR32(s) | ((uint64_t)MR32(s+4) << 32);
            uint64_t sec = ft / 10000000ull;
            if (sec >= 11644473600ull){
                time_t t = (time_t)(sec - 11644473600ull); struct tm g;
                if (gmtime_r(&t, &g)){
                    mem_commit(d,16);
                    MR16(d)    = (uint16_t)(g.tm_year + 1900);
                    MR16(d+2)  = (uint16_t)(g.tm_mon + 1);
                    MR16(d+4)  = (uint16_t)g.tm_wday;
                    MR16(d+6)  = (uint16_t)g.tm_mday;
                    MR16(d+8)  = (uint16_t)g.tm_hour;
                    MR16(d+10) = (uint16_t)g.tm_min;
                    MR16(d+12) = (uint16_t)g.tm_sec;
                    MR16(d+14) = (uint16_t)((ft / 10000ull) % 1000ull);
                    r=1; } } } }
    else if (!strcmp(n,"GetTimeZoneInformation")){ uint32_t hle_tz_info(uint32_t); r = hle_tz_info(A(c,0)); }   /* hlefix.c */
    else if (!strcmp(n,"GetFullPathNameA")){
        /* (lpFileName, nBufferLength, lpBuffer, lpFilePart)
         * The career save builds the profile path with this
         * ("C:\NFSU2\NFS Underground 2").  It used to be unimplemented: it
         * returned 0 and left the buffer empty, the game tried to write to a
         * garbage path and said "Unable to save <name>".  The current
         * directory is always C:\NFSU2. */
        uint32_t src=A(c,0), sz=A(c,1), dst=A(c,2), fpart=A(c,3);
        const char *in = (src && mem_is_committed(src)) ? (const char*)(g_mem+src) : "";
        char full[1024]; size_t k = 0;
        if (in[0] && in[1] == ':')                    /* "X:..." */
            { full[k++] = in[0]; full[k++] = ':'; in += 2; }
        else { memcpy(full, "C:", 2); k = 2; }
        if (*in != '\\' && *in != '/'){               /* relative: the current directory */
            memcpy(full + k, "\\NFSU2", 6); k += 6; }
        /* component by component: skip ".", ".." goes one up */
        while (*in && k < sizeof full - 2){
            while (*in == '\\' || *in == '/') in++;
            if (!*in) break;
            const char *e2 = in; while (*e2 && *e2 != '\\' && *e2 != '/') e2++;
            size_t L = (size_t)(e2 - in);
            if (L == 1 && in[0] == '.') { in = e2; continue; }
            if (L == 2 && in[0] == '.' && in[1] == '.'){
                while (k > 2 && full[k-1] != '\\') k--;
                if (k > 2) k--;
                in = e2; continue; }
            if (k + 1 + L >= sizeof full - 1) break;
            full[k++] = '\\'; memcpy(full + k, in, L); k += L; in = e2;
        }
        if (k == 2) full[k++] = '\\';                 /* only "C:\" */
        /* the trailing separator is kept ("dir\" -> "C:\...\dir\") */
        { size_t il = src && mem_is_committed(src) ? strlen((const char*)(g_mem+src)) : 0;
          const char *s0 = (const char*)(g_mem+src);
          if (il && (s0[il-1]=='\\' || s0[il-1]=='/') && full[k-1] != '\\') full[k++] = '\\'; }
        full[k] = 0;
        if (dst && sz > k){
            mem_commit(dst, (uint32_t)k + 1); memcpy(g_mem+dst, full, k + 1);
            if (fpart){ mem_commit(fpart, 4);
                char *ls = strrchr(full, '\\');
                MR32(fpart) = (ls && ls[1]) ? dst + (uint32_t)(ls + 1 - full) : 0; }
            r = (uint32_t)k;
        } else r = (uint32_t)k + 1;                   /* the required size (including NUL) */
    }
    else if (!strcmp(n,"GetSystemDirectoryA")||!strcmp(n,"GetWindowsDirectoryA")){
        uint32_t p=A(c,0); const char*s="C:\\Windows"; uint32_t l=(uint32_t)strlen(s);
        if(p){ mem_commit(p,l+1); memcpy(g_mem+p,s,l); MR8(p+l)=0; } r=l; }
    else if (!strcmp(n,"GetSystemTimeAsFileTime")){
        uint32_t p=A(c,0); if(p){ mem_commit(p,8);
            static uint64_t ft = 130000000000000000ull; ft += 100000;
            MR32(p)=(uint32_t)ft; MR32(p+4)=(uint32_t)(ft>>32); } r=0; }
    else if (!strcmp(n,"GetLocalTime")||!strcmp(n,"GetSystemTime")){
        uint32_t p=A(c,0); if(p){ mem_commit(p,16); memset(g_mem+p,0,16);
            MR16(p)=2026; MR16(p+2)=8; MR16(p+6)=24; MR16(p+8)=12; } r=0; }
    /* --- copy protection / anti-debug: return failure --- */
    else if (!strcmp(n,"CreateToolhelp32Snapshot")) r=0xFFFFFFFFu;
    else if (!strcmp(n,"Process32First")||!strcmp(n,"Process32Next")) r=0;
    else if (!strcmp(n,"IsDebuggerPresent")) r=0;
    /* --- resources --- */
    else if (!strcmp(n,"FindResourceA")) r = res_find(A(c,1), A(c,2), 0);
    else if (!strcmp(n,"FindResourceW")) r = res_find(A(c,1), A(c,2), 1);
    else if (!strcmp(n,"LoadResource"))  r = A(c,1);            /* carry the HRSRC */
    else if (!strcmp(n,"LockResource"))  r = res_data(A(c,0));
    else if (!strcmp(n,"SizeofResource"))r = res_size(A(c,1));
    else if (!strcmp(n,"FreeResource"))  r = 1;
    else if (!strcmp(n,"GetSystemInfo")){
        uint32_t p=A(c,0); if(p){ mem_commit(p,36); memset(g_mem+p,0,36);
            MR32(p+4)=4096; MR32(p+20)=10; MR32(p+32)=0x000006d8; } r=0; }
    else if (!strcmp(n,"GlobalMemoryStatus")){
        uint32_t p=A(c,0); if(p){ mem_commit(p,32); memset(g_mem+p,0,32);
            MR32(p)=32; MR32(p+4)=50; MR32(p+8)=0x40000000u; MR32(p+12)=0x20000000u; } r=0; }
    else if (!strcmp(n,"IsBadReadPtr")||!strcmp(n,"IsBadWritePtr")||!strcmp(n,"IsBadCodePtr")) r=0;
    /* the guest's printf (hlefix.c) */
    else if (!strcmp(n,"wvsprintfA")||!strcmp(n,"wsprintfA")){   /* (out, fmt, va_list) | cdecl (out, fmt, ...) */
        uint32_t hle_vformat(uint32_t, uint32_t, const char *, uint32_t);
        uint32_t o = A(c,0), f = A(c,1), va = n[1] == 'v' ? A(c,2) : c->esp + 8u;
        r = (o && f && mem_is_committed(f)) ? hle_vformat(o, 1025u, (const char *)(g_mem + f), va) : 0; }
    else if (!strcmp(n,"GetDiskFreeSpaceExA")||!strcmp(n,"GetDiskFreeSpaceA")){   /* hlefix.c */
        uint32_t hle_disk_free(uint32_t, int); r = hle_disk_free(c->esp, n[16] == 'E'); }
    else if (!strcmp(n,"DeleteObject")||!strcmp(n,"EndPaint")) r = 1;
    else if (!strcmp(n,"BeginPaint")){ uint32_t ps=A(c,1); if (ps){ mem_commit(ps,64); memset(g_mem+ps,0,64); } r = 0x00B20001u; }
    else if (!strcmp(n,"GetThreadPriority")) r = 0;            /* THREAD_PRIORITY_NORMAL */
    else if (!strcmp(n,"SetThreadPriority")) r = 1;
    else if (!strcmp(n,"OutputDebugStringA")){ uint32_t p=A(c,0);
        if(p) fprintf(stderr,"[dbg] %s", (char*)(g_mem+p)); r=0; }
    else if (!strcmp(n,"timeBeginPeriod")||!strcmp(n,"timeEndPeriod")) r=0;
    else if (!strcmp(n,"timeGetTime")){ uint32_t host_ms(void); r = host_ms(); }
    else if (!strcmp(n,"timeSetEvent")){
        /* (uDelay, uResolution, lpTimeProc, dwUser, fuEvent) */
        uint32_t delay=A(c,0), proc=A(c,2), user=A(c,3), flags=A(c,4);
        uint32_t id=0;
        if (proc && !getenv("NOTIMER")){
            pthread_mutex_lock(&g_lock);
            if (!g_timer_running){
                g_timer_running = 1;
                pthread_t th2;
                if (pthread_create(&th2,0,timer_thread_main,0)==0) pthread_detach(th2);
                else g_timer_running = 0;
            }
            for (int i=0;i<MAXTIMER;i++){
                if (g_tm[i].due_us) continue;
                uint32_t us = delay ? delay*1000u : 1000u;
                g_tm[i].proc=proc; g_tm[i].user=user;
                g_tm[i].id = id = g_timer_next_id++;
                g_tm[i].period_us = (flags & 1u) ? us : 0u;
                g_tm[i].due_us = now_us() + us;
                break;
            }
            pthread_mutex_unlock(&g_lock);
            { static int sh2=0; if (sh2<3){ sh2++;
                fprintf(stderr,"  [timer] timeSetEvent %u ms, %s, callback 0x%08x\n",
                        delay, (flags&1u)?"periodic":"one-shot", proc); } }
        }
        r=id; }
    else if (!strcmp(n,"timeKillEvent")){
        uint32_t id=A(c,0);
        pthread_mutex_lock(&g_lock);
        for (int i=0;i<MAXTIMER;i++)
            if (g_tm[i].due_us && g_tm[i].id==id){ g_tm[i].due_us=0; break; }
        pthread_mutex_unlock(&g_lock);
        r=0; }
    else if (!strcmp(n,"timeGetDevCaps")){
        uint32_t p=A(c,0);
        if(p){ mem_commit(p,8); MR32(p)=1u; MR32(p+4)=1000000u; }
        r=0; }
    else if (!strcmp(n,"timeBeginPeriod")||!strcmp(n,"timeEndPeriod")) r=0;
    else if (!strcmp(n,"joyGetNumDevs")) r=0;
    /* --- REAL critical sections -----------------------------------------
     * If left as a no-op stub, the GIL's fair sharing (it releases the lock every
     * 1024 Win32 calls) breaks mutual exclusion: a thread can lose the lock while
     * inside a critical section.                                        */
    else if (!strcmp(n,"InitializeCriticalSection")||
             !strcmp(n,"InitializeCriticalSectionAndSpinCount")){
        (void)cs_for(A(c,0)); r=1; }
    else if (!strcmp(n,"EnterCriticalSection")){
        pthread_mutex_t *m = cs_for(A(c,0));
        if (m){
            g_cs_enter++;
            if (pthread_mutex_trylock(m) != 0){
                g_cs_contended++;
                ts_set(TS_CS, A(c,0));
                guest_yield_begin();          /* release the GIL while waiting */
                pthread_mutex_lock(m);
                guest_yield_end();
            }
            tl_cs_depth++;
            cs_owned(m, cur_tid(c), +1);
        }
        r=1; }
    else if (!strcmp(n,"TryEnterCriticalSection")){
        pthread_mutex_t *m = cs_for(A(c,0));
        r=1;
        if (m){ if (pthread_mutex_trylock(m)==0){ tl_cs_depth++; cs_owned(m, cur_tid(c), +1); } else r=0; } }
    else if (!strcmp(n,"LeaveCriticalSection")){
        pthread_mutex_t *m = cs_for(A(c,0));
        if (m && tl_cs_depth > 0){ tl_cs_depth--; cs_owned(m, 0, -1); pthread_mutex_unlock(m); }
        r=1; }
    else if (!strcmp(n,"DeleteCriticalSection")) r=1;
    else return 0;                       /* this layer isn't interested */
    *out = r;
    return 1;
}
uint64_t win32_ext_threads(void){ return g_threads_started; }
uint64_t win32_ext_threads_exited(void){ return g_threads_exited; }
