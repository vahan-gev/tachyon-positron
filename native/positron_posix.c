/* Positron native shim — POSIX fallback (Linux) and Windows placeholder.
 *
 * The sidecar-process and wait-for-port pieces are real and work on any POSIX
 * system; only the native window is macOS-only in this release. On non-macOS
 * platforms the window calls print a clear notice instead of opening a window,
 * so programs still link and run (headless) rather than failing to build.
 *
 * A full Linux backend (WebKitGTK) and Windows backend (WebView2) are planned.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
/* ---- Windows: placeholder ---- */
void pn_window(const char* t, int32_t w, int32_t h) {
    (void)t; (void)w; (void)h;
    fprintf(stderr, "positron: native window not yet supported on Windows\n");
}
void pn_devtools(int32_t on) { (void)on; }
void pn_load_url(const char* u) { (void)u; }
void pn_load_html(const char* h) { (void)h; }
void pn_set_title(const char* t) { (void)t; }
void pn_eval(const char* j) { (void)j; }
void pn_run(void) {}
void pn_quit(void) {}
int32_t pn_spawn(const char* cmd) { return cmd ? (int32_t)_spawnl(_P_NOWAIT, "cmd", "cmd", "/c", cmd, NULL) : -1; }
void pn_kill(int32_t pid) { (void)pid; }
int32_t pn_wait_port(const char* host, int32_t port, int32_t ms) { (void)host; (void)port; (void)ms; return 0; }
const char* pn_exec_dir(void) { return "."; }

#else
/* ---- Linux / other POSIX ---- */
#include <unistd.h>
#include <signal.h>
#include <spawn.h>
#include <netdb.h>
#include <sys/socket.h>
#include <libgen.h>

extern char** environ;

#define PW_MAXPROC 32
static pid_t g_pids[PW_MAXPROC];
static int   g_npid = 0;

static void pw_killall(void) {
    for (int i = 0; i < g_npid; i++)
        if (g_pids[i] > 0) kill(-g_pids[i], SIGTERM);
}

void pn_window(const char* t, int32_t w, int32_t h) {
    (void)t; (void)w; (void)h;
    fprintf(stderr, "positron: native window not yet supported on this platform "
                    "(macOS only in this release)\n");
    atexit(pw_killall);
}
void pn_devtools(int32_t on) { (void)on; }
void pn_load_url(const char* u) { (void)u; }
void pn_load_html(const char* h) { (void)h; }
void pn_set_title(const char* t) { (void)t; }
void pn_eval(const char* j) { (void)j; }
void pn_run(void) {}
void pn_quit(void) { pw_killall(); }

int32_t pn_spawn(const char* cmd) {
    if (g_npid >= PW_MAXPROC || !cmd) return -1;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);
    char* argv[] = { (char*)"sh", (char*)"-c", (char*)cmd, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/bin/sh", NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    if (rc != 0) return -1;
    g_pids[g_npid++] = pid;
    return (int32_t)pid;
}
void pn_kill(int32_t pid) { if (pid > 0) kill(-(pid_t)pid, SIGTERM); }

int32_t pn_wait_port(const char* host, int32_t port, int32_t timeout_ms) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    char portstr[16];
    snprintf(portstr, sizeof portstr, "%d", port);
    int waited = 0;
    while (waited <= timeout_ms) {
        struct addrinfo* res = NULL;
        if (getaddrinfo(host ? host : "127.0.0.1", portstr, &hints, &res) == 0 && res) {
            int s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
            if (s >= 0) {
                int ok = connect(s, res->ai_addr, res->ai_addrlen);
                close(s);
                freeaddrinfo(res);
                if (ok == 0) return 1;
            } else freeaddrinfo(res);
        }
        usleep(100 * 1000);
        waited += 100;
    }
    return 0;
}

static char g_execdir[4096];
const char* pn_exec_dir(void) {
    ssize_t n = readlink("/proc/self/exe", g_execdir, sizeof g_execdir - 1);
    if (n <= 0) { strcpy(g_execdir, "."); return g_execdir; }
    g_execdir[n] = 0;
    return dirname(g_execdir);
}
#endif
