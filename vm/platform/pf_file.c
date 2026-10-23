/* Files (raw fds, unbuffered), directories, FIFOs, child processes. */
#include "platform.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

enum { K_FILE = 1 };
static pf_table files;

static bool err(const char *what, const char *path)
{
    pf_set_error("%s %s: %s", what, path ? path : "", strerror(errno));
    return false;
}

static int fd_of(int f)
{
    pf_obj *o = pf_table_get(&files, f, K_FILE);
    if (!o) {
        pf_set_error("bad file handle %d", f);
        return -1;
    }
    return (int)o->i;
}

int pf_file_open(const char *path, int mode)
{
    static const int flags[] = {O_RDONLY, O_RDWR | O_CREAT, O_WRONLY | O_APPEND | O_CREAT, O_RDWR | O_CREAT | O_TRUNC};
    platform_init();
    if (mode < 0 || mode > 3) return pf_set_error("bad file mode %d", mode), 0;
    int fd = open(path, flags[mode] | O_CLOEXEC, 0644);
    if (fd < 0) return err("open", path), 0;
    int h = pf_table_add(&files, K_FILE, NULL);
    files.v[h].i = fd;
    return h;
}

/* Write-behind: a background thread performs queued writes, so a slow reader (a FIFO into ffmpeg) does not block the
   VM thread. At most WB_MAX writes are pending at once; flush and close wait until a file's writes are done. */
enum { WB_MAX = 3 };
typedef struct wb_job { int fd; char *data; size_t len; struct wb_job *next; } wb_job;
static pthread_mutex_t wb_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t wb_added = PTHREAD_COND_INITIALIZER, wb_finished = PTHREAD_COND_INITIALIZER;
static wb_job *wb_head, *wb_tail;
static int wb_pending, wb_failed_fd = -1, wb_errno;
static bool wb_started;

static void *wb_main(void *unused)
{
    for (;;) {
        pthread_mutex_lock(&wb_lock);
        while (!wb_head) pthread_cond_wait(&wb_added, &wb_lock);
        wb_job *j = wb_head; /* stays queued while it is written, so wb_drain waits for it */
        pthread_mutex_unlock(&wb_lock);
        size_t done = 0;
        int e = 0;
        while (done < j->len) {
            ssize_t r = write(j->fd, j->data + done, j->len - done);
            if (r < 0 && errno == EINTR) continue;
            if (r < 0) { e = errno; break; }
            done += r;
        }
        pthread_mutex_lock(&wb_lock);
        wb_head = j->next;
        if (!wb_head) wb_tail = NULL;
        wb_pending--;
        if (e) { wb_failed_fd = j->fd; wb_errno = e; }
        pthread_cond_broadcast(&wb_finished);
        pthread_mutex_unlock(&wb_lock);
        free(j->data);
        free(j);
    }
    return NULL;
}

static bool wb_has(int fd)
{
    for (wb_job *j = wb_head; j; j = j->next)
        if (j->fd == fd) return true;
    return false;
}

/* Wait until fd's queued writes are done; false (errno set) if one failed. */
static bool wb_drain(int fd)
{
    pthread_mutex_lock(&wb_lock);
    while (wb_has(fd)) pthread_cond_wait(&wb_finished, &wb_lock);
    bool failed = wb_failed_fd == fd;
    if (failed) { wb_failed_fd = -1; errno = wb_errno; }
    pthread_mutex_unlock(&wb_lock);
    return !failed;
}

int64_t pf_file_write_behind(int f, const void *buf, size_t n)
{
    int fd = fd_of(f);
    if (fd < 0) return -1;
    pthread_mutex_lock(&wb_lock);
    if (wb_failed_fd == fd) {
        wb_failed_fd = -1;
        errno = wb_errno;
        pthread_mutex_unlock(&wb_lock);
        return err("write", NULL), -1;
    }
    if (wb_pending >= WB_MAX) { pthread_mutex_unlock(&wb_lock); return 0; }
    wb_job *j = malloc(sizeof *j);
    char *data = malloc(n ? n : 1);
    if (!j || !data) { free(j); free(data); pthread_mutex_unlock(&wb_lock); return pf_set_error("out of memory"), -1; }
    memcpy(data, buf, n);
    *j = (wb_job){fd, data, n, NULL};
    if (wb_tail) wb_tail->next = j; else wb_head = j;
    wb_tail = j;
    wb_pending++;
    if (!wb_started) {
        pthread_t t;
        if (pthread_create(&t, NULL, wb_main, NULL) == 0) { pthread_detach(t); wb_started = true; }
    }
    pthread_cond_signal(&wb_added);
    pthread_mutex_unlock(&wb_lock);
    return (int64_t)n;
}

bool pf_file_close(int f)
{
    int fd = fd_of(f);
    if (fd < 0) return false;
    wb_drain(fd);
    pf_table_remove(&files, f);
    return close(fd) == 0 || err("close", NULL);
}

int64_t pf_file_read(int f, void *buf, size_t n)
{
    int fd = fd_of(f);
    if (fd < 0) return -1;
    ssize_t r;
    do r = read(fd, buf, n);
    while (r < 0 && errno == EINTR);
    if (r < 0) err("read", NULL);
    return r;
}

int64_t pf_file_write(int f, const void *buf, size_t n)
{
    int fd = fd_of(f);
    if (fd < 0) return -1;
    size_t done = 0;
    while (done < n) {
        ssize_t r = write(fd, (const char *)buf + done, n - done);
        if (r < 0 && errno == EINTR) continue;
        if (r < 0) return err("write", NULL), -1;
        done += r;
    }
    return (int64_t)done;
}

int64_t pf_file_size(int f)
{
    int fd = fd_of(f);
    struct stat st;
    if (fd < 0) return -1;
    if (fstat(fd, &st) != 0) return err("fstat", NULL), -1;
    return st.st_size;
}

int64_t pf_file_position(int f)
{
    int fd = fd_of(f);
    if (fd < 0) return -1;
    off_t r = lseek(fd, 0, SEEK_CUR);
    if (r < 0) err("lseek", NULL);
    return r;
}

bool pf_file_seek(int f, int64_t pos)
{
    int fd = fd_of(f);
    if (fd < 0) return false;
    return lseek(fd, pos, SEEK_SET) >= 0 || err("lseek", NULL);
}

/* Writes are unbuffered, so flush only pushes regular files to disk. */
bool pf_file_flush(int f)
{
    int fd = fd_of(f);
    struct stat st;
    if (fd < 0) return false;
    if (!wb_drain(fd)) return err("write", NULL);
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && fsync(fd) != 0) return err("fsync", NULL);
    return true;
}

bool pf_file_delete(const char *path)
{
    return unlink(path) == 0 || (errno == EISDIR || errno == EPERM ? rmdir(path) == 0 : false) || err("delete", path);
}

bool pf_file_rename(const char *from, const char *to) { return rename(from, to) == 0 || err("rename", from); }

bool pf_file_stat(const char *path, pf_stat *s)
{
    struct stat st;
    memset(s, 0, sizeof *s);
    if (stat(path, &st) != 0) return errno == ENOENT || errno == ENOTDIR || err("stat", path);
    s->exists = true;
    s->is_dir = S_ISDIR(st.st_mode);
    s->size = st.st_size;
    s->mtime_us = (int64_t)st.st_mtimespec.tv_sec * 1000000 + st.st_mtimespec.tv_nsec / 1000;
    return true;
}

char **pf_dir_entries(const char *path, int *n)
{
    DIR *d = opendir(path);
    if (!d) return err("opendir", path), NULL;
    int cap = 64;
    char **v = malloc(sizeof *v * cap);
    struct dirent *e;
    *n = 0;
    bool ok = v != NULL;
    while (ok && (e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        if (*n == cap) {
            char **nv = realloc(v, sizeof *v * (cap *= 2));
            if (!(ok = nv != NULL)) break;
            v = nv;
        }
        ok = (v[*n] = strdup(e->d_name)) != NULL;
        *n += ok;
    }
    closedir(d);
    if (!ok) {
        while (v && *n > 0) free(v[--*n]);
        free(v);
        pf_set_error("out of memory");
        return NULL;
    }
    return v;
}

bool pf_dir_create(const char *path) { return mkdir(path, 0755) == 0 || err("mkdir", path); }

char *pf_cwd(void)
{
    char *p = getcwd(NULL, 0);
    if (!p) err("getcwd", NULL);
    return p;
}

bool pf_mkfifo(const char *path) { return mkfifo(path, 0644) == 0 || err("mkfifo", path); }

/* argv[0] is looked up in PATH; stdio is inherited. */
int64_t pf_spawn(char *const argv[])
{
    pid_t pid;
    platform_init();
    int r = posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ);
    if (r != 0) {
        errno = r;
        return err("posix_spawnp", argv[0]), -1;
    }
    return pid;
}

/* status: exit code, or 128 + signal number */
bool pf_process_wait(int64_t pid, bool block, int *status, bool *done)
{
    int st;
    pid_t r;
    do r = waitpid((pid_t)pid, &st, block ? 0 : WNOHANG);
    while (r < 0 && errno == EINTR);
    if (r < 0) return err("waitpid", NULL);
    *done = r != 0;
    if (*done) *status = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
    return true;
}

int pf_file_handle_count(void) { return pf_table_count(&files, -1); }
