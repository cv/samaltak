/* Non-blocking TCP sockets. A socket with a read (write) semaphore is "armed"
 * until it becomes readable/acceptable (writable); then the semaphore is
 * signaled once. Read is re-armed by every recv/accept; write is armed by a
 * send that would block or was partial. */
#include "platform.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

enum { K_SOCK = 1 };
typedef struct {
    int read_sem, write_sem;
    bool read_armed, write_armed;
} sock_sems;
static pf_table socks;
static sock_sems sems[1024];
static int armed_count; /* sockets with any semaphore */

static int err(const char *what)
{
    pf_set_error("%s: %s", what, strerror(errno));
    return 0;
}

static int fd_of(int s)
{
    pf_obj *o = pf_table_get(&socks, s, K_SOCK);
    if (!o) {
        pf_set_error("bad socket handle %d", s);
        return -1;
    }
    return (int)o->i;
}

static int wrap(int fd)
{
    int one = 1;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    int h = pf_table_add(&socks, K_SOCK, NULL);
    if (h >= (int)(sizeof sems / sizeof sems[0])) {
        pf_table_remove(&socks, h);
        close(fd);
        return pf_set_error("too many sockets"), 0;
    }
    socks.v[h].i = fd;
    sems[h] = (sock_sems){0};
    return h;
}

static struct addrinfo *resolve(const char *host, int port, bool passive)
{
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM, .ai_flags = passive ? AI_PASSIVE : 0}, *ai;
    char ps[16];
    snprintf(ps, sizeof ps, "%d", port);
    int r = getaddrinfo(host && *host ? host : NULL, ps, &hints, &ai);
    if (r != 0) {
        pf_set_error("getaddrinfo %s: %s", host ? host : "", gai_strerror(r));
        return NULL;
    }
    return ai;
}

int pf_socket_listen(const char *host, int port, int backlog)
{
    platform_init();
    struct addrinfo *ai = resolve(host, port, true);
    if (!ai) return 0;
    int fd = socket(ai->ai_family, SOCK_STREAM, 0), one = 1;
    if (fd < 0) return freeaddrinfo(ai), err("socket");
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(fd, ai->ai_addr, ai->ai_addrlen) != 0 || listen(fd, backlog) != 0) {
        err("bind/listen");
        close(fd);
        freeaddrinfo(ai);
        return 0;
    }
    freeaddrinfo(ai);
    return wrap(fd);
}

/* Blocking connect (meant for localhost), then non-blocking. */
int pf_socket_connect(const char *host, int port)
{
    platform_init();
    struct addrinfo *ai = resolve(host, port, false);
    if (!ai) return 0;
    int fd = -1;
    for (struct addrinfo *a = ai; a; a = a->ai_next) {
        fd = socket(a->ai_family, SOCK_STREAM, 0);
        if (fd >= 0 && connect(fd, a->ai_addr, a->ai_addrlen) == 0) break;
        if (fd >= 0) close(fd);
        fd = -1;
    }
    if (fd < 0) err("connect");
    freeaddrinfo(ai);
    if (fd < 0) return 0;
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    return wrap(fd);
}

int pf_socket_accept(int s, bool *would_block)
{
    int fd = fd_of(s);
    *would_block = false;
    if (fd < 0) return 0;
    sems[s].read_armed = true;
    int c = accept(fd, NULL, NULL);
    if (c < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == ECONNABORTED || errno == EINTR) {
            *would_block = true;
            pf_set_error("");
            return 0;
        }
        return err("accept");
    }
    int one = 1;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    return wrap(c);
}

int64_t pf_socket_recv(int s, void *buf, size_t n)
{
    int fd = fd_of(s);
    if (fd < 0) return -2;
    sems[s].read_armed = true;
    ssize_t r;
    do r = recv(fd, buf, n, 0);
    while (r < 0 && errno == EINTR);
    if (r >= 0) return r;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return -1;
    err("recv");
    return -2;
}

int64_t pf_socket_send(int s, const void *buf, size_t n)
{
    int fd = fd_of(s);
    if (fd < 0) return -2;
    ssize_t r;
    do r = send(fd, buf, n, 0);
    while (r < 0 && errno == EINTR);
    sems[s].write_armed = (r >= 0 && (size_t)r < n) || (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK));
    if (r >= 0) return r;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return -1;
    err("send");
    return -2;
}

bool pf_socket_semaphores(int s, int read_index, int write_index)
{
    if (fd_of(s) < 0) return false;
    bool had = sems[s].read_sem || sems[s].write_sem;
    sems[s] = (sock_sems){read_index, write_index, true, false};
    armed_count += (read_index || write_index) - had;
    pf_update_poll_interval();
    return true;
}

bool pf_socket_close(int s)
{
    int fd = fd_of(s);
    if (fd < 0) return false;
    pf_socket_semaphores(s, 0, 0);
    pf_table_remove(&socks, s);
    return close(fd) == 0 || err("close");
}

int pf_socket_local_port(int s)
{
    int fd = fd_of(s);
    struct sockaddr_storage ss;
    socklen_t len = sizeof ss;
    if (fd < 0) return 0;
    if (getsockname(fd, (struct sockaddr *)&ss, &len) != 0) return err("getsockname");
    return ntohs(ss.ss_family == AF_INET6 ? ((struct sockaddr_in6 *)&ss)->sin6_port : ((struct sockaddr_in *)&ss)->sin_port);
}

static short events_of(int h)
{
    return (sems[h].read_sem && sems[h].read_armed ? POLLIN : 0) | (sems[h].write_sem && sems[h].write_armed ? POLLOUT : 0);
}

bool pf_socket_any_armed(void) { return armed_count > 0; }

/* Fills pollfds (struct pollfd[]) with armed sockets; answers the count. */
int pf_socket_poll_fds(void *pollfds, int max)
{
    struct pollfd *p = pollfds;
    int n = 0;
    for (int h = 1; h < socks.n && n < max; h++) {
        if (socks.v[h].kind != K_SOCK) continue;
        short ev = events_of(h);
        if (ev) p[n++] = (struct pollfd){.fd = (int)socks.v[h].i, .events = ev};
    }
    return n;
}

void pf_socket_poll(int timeout_ms)
{
    struct pollfd p[256];
    int hs[256], n = 0;
    for (int h = 1; h < socks.n && n < 256; h++) {
        if (socks.v[h].kind != K_SOCK) continue;
        short ev = events_of(h);
        if (!ev) continue;
        p[n] = (struct pollfd){.fd = (int)socks.v[h].i, .events = ev};
        hs[n++] = h;
    }
    if (n == 0) {
        if (timeout_ms > 0) poll(NULL, 0, timeout_ms);
        return;
    }
    if (poll(p, n, timeout_ms) <= 0) return;
    for (int i = 0; i < n; i++) {
        sock_sems *s = &sems[hs[i]];
        short r = p[i].revents;
        if (!r) continue;
        if ((r & (POLLIN | POLLHUP | POLLERR)) && (p[i].events & POLLIN)) {
            s->read_armed = false;
            signal_external_semaphore(s->read_sem);
        }
        if ((r & (POLLOUT | POLLHUP | POLLERR)) && (p[i].events & POLLOUT)) {
            s->write_armed = false;
            signal_external_semaphore(s->write_sem);
        }
    }
}

int pf_socket_handle_count(void) { return pf_table_count(&socks, -1); }
