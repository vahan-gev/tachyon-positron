/* Positron native shim — Linux (GTK 3 + WebKitGTK).
 *
 * Same flat C ABI as the macOS shim: a WebKitGTK view fills a GTK window, and
 * sidecar child processes (e.g. a Node.js server) are spawned in their own
 * process group and killed when the app exits.
 *
 * Link flags come from pkg-config (see Tachyon.toml); the header include paths
 * ride along on the same cc line. Set PW_AUTOQUIT_MS to auto-close (tests/CI).
 */
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <spawn.h>
#include <netdb.h>
#include <sys/socket.h>
#include <libgen.h>

extern char** environ;

static GtkWidget* g_win = NULL;
static GtkWidget* g_web = NULL;
static int        g_devtools = 0;

/* ---------- sidecar child processes ---------- */

#define PW_MAXPROC 32
static pid_t g_pids[PW_MAXPROC];
static int   g_npid = 0;

static void pw_killall(void) {
    for (int i = 0; i < g_npid; i++)
        if (g_pids[i] > 0) kill(-g_pids[i], SIGTERM);
}

/* ---------- window / webview ---------- */

static void pw_on_destroy(GtkWidget* w, gpointer data) {
    (void)w; (void)data;
    pw_killall();
    gtk_main_quit();
}

void pn_devtools(int32_t on) { g_devtools = on ? 1 : 0; }

void pn_window(const char* title, int32_t w, int32_t h) {
    if (!gtk_init_check(0, NULL)) {
        fprintf(stderr, "positron: could not initialize GTK (no display?)\n");
        return;
    }
    g_win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(g_win), title ? title : "Positron");
    gtk_window_set_default_size(GTK_WINDOW(g_win), w, h);
    gtk_window_set_position(GTK_WINDOW(g_win), GTK_WIN_POS_CENTER);
    g_signal_connect(g_win, "destroy", G_CALLBACK(pw_on_destroy), NULL);

    g_web = webkit_web_view_new();
    if (g_devtools) {
        WebKitSettings* s = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(g_web));
        webkit_settings_set_enable_developer_extras(s, TRUE);
    }
    gtk_container_add(GTK_CONTAINER(g_win), g_web);
    atexit(pw_killall);
}

void pn_load_url(const char* url) {
    if (g_web) webkit_web_view_load_uri(WEBKIT_WEB_VIEW(g_web), url ? url : "");
}

void pn_load_html(const char* html) {
    if (g_web) webkit_web_view_load_html(WEBKIT_WEB_VIEW(g_web), html ? html : "", NULL);
}

void pn_set_title(const char* t) {
    if (g_win) gtk_window_set_title(GTK_WINDOW(g_win), t ? t : "");
}

void pn_eval(const char* js) {
    if (g_web)
        webkit_web_view_run_javascript(WEBKIT_WEB_VIEW(g_web), js ? js : "",
                                       NULL, NULL, NULL);
}

static gboolean pw_autoquit(gpointer data) {
    (void)data;
    gtk_main_quit();
    return FALSE;
}

void pn_run(void) {
    if (!g_win) return;
    gtk_widget_show_all(g_win);
    const char* aq = getenv("PW_AUTOQUIT_MS");
    if (aq) g_timeout_add((guint)atoi(aq), pw_autoquit, NULL);
    gtk_main();
}

void pn_quit(void) {
    pw_killall();
    gtk_main_quit();
}

/* ---------- sidecar processes ---------- */

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
