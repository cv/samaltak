/* Pseudo-terminals: a child process (a shell) on the slave side of a new pty,
 * the master fd in the socket table (kind PF_FD_PTY), so reading, writing and
 * the readiness semaphores work like a socket's (pf_socket.c). The child gets
 * its own session with the slave as controlling terminal, default signal
 * dispositions (the VM ignores SIGPIPE) and no other inherited fds. */
#include "platform.h"

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <util.h>

extern char **environ;

typedef struct {
    pid_t pid;
    bool reaped;
} pty_child;

static int64_t hung_up[64]; /* closed before they ended: reaped later */

static void reap_hung_up(void)
{
    for (int i = 0; i < 64; i++)
        if (hung_up[i] && waitpid((pid_t)hung_up[i], NULL, WNOHANG) != 0) hung_up[i] = 0;
}

static int err(const char *what)
{
    pf_set_error("%s: %s", what, strerror(errno));
    return 0;
}

/* malloc'd path of argv0, searched in PATH (from envp, else ours) unless it has a slash */
static char *resolve(const char *argv0, char *const envp[])
{
    if (strchr(argv0, '/')) return access(argv0, X_OK) == 0 ? strdup(argv0) : NULL;
    const char *path = NULL;
    for (char *const *e = envp; e && *e && !path; e++)
        if (!strncmp(*e, "PATH=", 5)) path = *e + 5;
    if (!path) path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    size_t n = strlen(argv0);
    while (*path) {
        const char *end = strchr(path, ':');
        size_t len = end ? (size_t)(end - path) : strlen(path);
        char *cand = malloc(len + n + 2);
        if (!cand) return NULL;
        memcpy(cand, path, len);
        cand[len] = '/';
        memcpy(cand + len + 1, argv0, n + 1);
        if (len && access(cand, X_OK) == 0) return cand;
        free(cand);
        if (!end) break;
        path = end + 1;
    }
    errno = ENOENT;
    return NULL;
}

/* envp (or ours) with TERM=xterm-256color unless envp sets TERM; the strings are shared, the array malloc'd */
static char **child_env(char *const envp[])
{
    char *const *src = envp ? envp : environ;
    size_t n = 0;
    bool has_term = false;
    for (; src[n]; n++) has_term |= envp && !strncmp(src[n], "TERM=", 5);
    char **env = malloc((n + 2) * sizeof *env);
    if (!env) return NULL;
    size_t k = 0;
    for (size_t i = 0; i < n; i++)
        if (envp || strncmp(src[i], "TERM=", 5)) env[k++] = src[i];
    if (!has_term) env[k++] = "TERM=xterm-256color";
    env[k] = NULL;
    return env;
}

int pf_pty_spawn(char *const argv[], char *const envp[], const char *cwd, int rows, int cols, int64_t *pid_out)
{
    platform_init();
    reap_hung_up();
    char *path = resolve(argv[0], envp);
    if (!path) return err(argv[0]);
    char **env = child_env(envp);
    pty_child *child = malloc(sizeof *child);
    if (!env || !child) {
        free(path), free(env), free(child);
        return pf_set_error("out of memory"), 0;
    }
    struct winsize ws = {.ws_row = (unsigned short)rows, .ws_col = (unsigned short)cols};
    int max_fd = getdtablesize();
    if (max_fd > 65536) max_fd = 65536;
    int master;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid == 0) {
        /* child: async-signal-safe calls only */
        struct sigaction dfl = {.sa_handler = SIG_DFL};
        sigset_t none;
        for (int s = 1; s < NSIG; s++) sigaction(s, &dfl, NULL);
        sigemptyset(&none);
        sigprocmask(SIG_SETMASK, &none, NULL);
        for (int fd = 3; fd < max_fd; fd++) close(fd);
        if (cwd && chdir(cwd) != 0) (void)!write(2, "samaltak: cannot change directory\r\n", 35);
        execve(path, argv, env);
        (void)!write(2, "samaltak: cannot execute ", 25);
        (void)!write(2, path, strlen(path));
        (void)!write(2, "\r\n", 2);
        _exit(127);
    }
    int saved = errno;
    free(path);
    free(env);
    if (pid < 0) {
        free(child);
        errno = saved;
        return err("forkpty");
    }
    *child = (pty_child){pid, false};
    int h = pf_fd_add(master, PF_FD_PTY, child);
    if (!h) {
        close(master);
        kill(pid, SIGHUP);
        hung_up[pid % 64] = pid;
        free(child);
        return 0;
    }
    *pid_out = pid;
    return h;
}

bool pf_pty_resize(int p, int rows, int cols)
{
    pf_obj *o = pf_fd_get(p, PF_FD_PTY);
    if (!o) return false;
    struct winsize ws = {.ws_row = (unsigned short)rows, .ws_col = (unsigned short)cols};
    return ioctl((int)o->i, TIOCSWINSZ, &ws) == 0 || err("TIOCSWINSZ");
}

bool pf_pty_wait(int p, bool block, int *status, bool *done)
{
    pf_obj *o = pf_fd_get(p, PF_FD_PTY);
    if (!o) return false;
    pty_child *c = o->ptr;
    if (c->reaped) return pf_set_error("pty child already waited for"), false;
    if (!pf_process_wait(c->pid, block, status, done)) return false;
    c->reaped = *done;
    return true;
}

bool pf_pty_close(int p)
{
    pf_obj *o = pf_fd_get(p, PF_FD_PTY);
    if (!o) return false;
    pty_child *c = o->ptr;
    bool ok = pf_fd_close(p, PF_FD_PTY);
    if (!c->reaped) {
        kill(-c->pid, SIGHUP); /* its process group: the shell and its foreground job */
        kill(c->pid, SIGHUP);
        if (waitpid(c->pid, NULL, WNOHANG) == 0) {
            reap_hung_up();
            for (int i = 0; i < 64; i++)
                if (!hung_up[i] || i == 63) {
                    hung_up[i] = c->pid;
                    break;
                }
        }
    }
    free(c);
    return ok;
}
