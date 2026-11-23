/* Fixed-purpose native child for process_ffi_test.py. No shell or external commands. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static void bytes(const char *name, const char *value)
{
    printf("%s=", name);
    if (!value)
        putchar('-');
    else
        for (const unsigned char *p = (const unsigned char *)value; *p; ++p)
            printf("%02x", (unsigned)*p);
    putchar('\n');
}

static int size(const char *name)
{
    struct winsize ws;
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) < 0)
        return 0;
    printf("%s=%u %u\n", name, (unsigned)ws.ws_row, (unsigned)ws.ws_col);
    return 1;
}

int main(int argc, char **argv)
{
    char cwd[4096], input[128];
    const char *mode = argc > 1 ? argv[1] : "";
    alarm(10); /* Bound children even if their VM fails before releasing them. */
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (!strcmp(mode, "signal")) {
        signal(SIGTERM, SIG_DFL);
        raise(SIGTERM);
        return 90;
    }
    if (!strcmp(mode, "large")) {
        if (argc != 4100 || strcmp(argv[4099], "large-tail"))
            return 99;
        for (int i = 2; i < 4099; ++i)
            if (argv[i][0])
                return 99;
        return 0;
    }
    if (!getcwd(cwd, sizeof cwd))
        return 91;
    if (!strcmp(mode, "pty") || !strcmp(mode, "pty-report")) {
        struct termios tty;
        if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO) ||
            tcgetattr(STDIN_FILENO, &tty) < 0)
            return 92;
        tty.c_lflag &= ~ECHO;
        if (tcsetattr(STDIN_FILENO, TCSANOW, &tty) < 0 || !size("size"))
            return 93;
        printf("pid=%ld\n", (long)getpid());
        bytes("cwd", cwd);
        bytes("env", getenv("PROCESS_FFI_BYTES"));
        bytes("parent", getenv("PROCESS_FFI_PARENT"));
        bytes("term", getenv("TERM"));
        puts("ready");
        if (!strcmp(mode, "pty")) {
            if (!fgets(input, sizeof input, stdin) || !size("resized"))
                return 94;
            bytes("input", input);
        }
        return 23;
    }
    if (strcmp(mode, "hold") && strcmp(mode, "exec"))
        return 95;
    printf("%s-pid=%ld\n", mode, (long)getpid());
    bytes("cwd", cwd);
    bytes("parent", getenv("PROCESS_FFI_PARENT"));
    for (int i = 0; i < argc; ++i)
        bytes("arg", argv[i]);
    if (!strcmp(mode, "hold")) {
        struct timespec pause = {0, 1000000L};
        while (access("release", F_OK) != 0) {
            if (errno != ENOENT)
                return 96;
            nanosleep(&pause, NULL);
        }
        return 37;
    }
    /* The isolated VM inherits one fixture fd that must not survive replacement. */
    const char *fd = getenv("PROCESS_FFI_FD");
    if (!fd || fcntl(atoi(fd), F_GETFD) != -1 || errno != EBADF)
        return 97;
    if (!fgets(input, sizeof input, stdin))
        return 98;
    bytes("input", input);
    fputs("exec-stderr\n", stderr);
    return 43;
}
