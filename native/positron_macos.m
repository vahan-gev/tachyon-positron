/* Positron native shim — macOS (Cocoa + WebKit).
 *
 * A flat, FFI-safe C surface (numbers + C strings) the Tachyon-side library
 * drives. It hosts a WKWebView inside an NSWindow, and manages "sidecar"
 * child processes (e.g. a Node.js server) so a real app — not just static
 * HTML/CSS — can run behind the window. Each sidecar is spawned into its own
 * process group and the whole group is signalled on quit, so a `next start`
 * (npm -> node) subtree dies with the window instead of leaking.
 *
 * Set PW_AUTOQUIT_MS in the environment to auto-close (used by tests/CI).
 */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <spawn.h>
#include <netdb.h>
#include <sys/socket.h>
#include <libgen.h>
#include <mach-o/dyld.h>

extern char** environ;

static NSWindow*  g_win = nil;
static WKWebView* g_web = nil;
static int        g_devtools = 0;

/* ---------- sidecar child processes ---------- */

#define PW_MAXPROC 32
static pid_t g_pids[PW_MAXPROC];
static int   g_npid = 0;

static void pw_killall(void) {
    for (int i = 0; i < g_npid; i++)
        if (g_pids[i] > 0) kill(-g_pids[i], SIGTERM);  /* whole process group */
}

/* ---------- app delegate ---------- */

@interface PWDelegate : NSObject <NSApplicationDelegate>
@end
@implementation PWDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)a { return YES; }
- (void)applicationWillTerminate:(NSNotification*)n { pw_killall(); }
@end

/* ---------- window / webview ---------- */

/* Call before pn_window to turn on the Web Inspector (right-click > Inspect). */
void pn_devtools(int32_t on) { g_devtools = on ? 1 : 0; }

void pn_window(const char* title, int32_t w, int32_t h) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        static PWDelegate* d = nil;
        d = [PWDelegate new];
        [NSApp setDelegate:d];
        atexit(pw_killall);

        NSRect frame = NSMakeRect(0, 0, w, h);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_win = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:style
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
        [g_win setTitle:[NSString stringWithUTF8String:title ? title : "Positron"]];
        [g_win center];
        [g_win setReleasedWhenClosed:NO];

        WKWebViewConfiguration* cfg = [WKWebViewConfiguration new];
        if (g_devtools)
            [cfg.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
        g_web = [[WKWebView alloc] initWithFrame:frame configuration:cfg];
        [g_web setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [g_win setContentView:g_web];
    }
}

void pn_load_url(const char* url) {
    NSString* s = [NSString stringWithUTF8String:url ? url : ""];
    NSURL* u = [NSURL URLWithString:s];
    if (u) [g_web loadRequest:[NSURLRequest requestWithURL:u]];
}

void pn_load_html(const char* html) {
    [g_web loadHTMLString:[NSString stringWithUTF8String:html ? html : ""] baseURL:nil];
}

void pn_set_title(const char* t) {
    [g_win setTitle:[NSString stringWithUTF8String:t ? t : ""]];
}

void pn_eval(const char* js) {
    [g_web evaluateJavaScript:[NSString stringWithUTF8String:js ? js : ""]
             completionHandler:nil];
}

void pn_run(void) {
    @autoreleasepool {
        [g_win makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        const char* aq = getenv("PW_AUTOQUIT_MS");
        if (aq) {
            double s = atof(aq) / 1000.0;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        }
        [NSApp run];
    }
}

void pn_quit(void) { [NSApp terminate:nil]; }

/* ---------- sidecar processes ---------- */

/* Run `cmd` via /bin/sh in a fresh process group; returns the pid (or -1). */
int32_t pn_spawn(const char* cmd) {
    if (g_npid >= PW_MAXPROC || !cmd) return -1;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);           /* new group == child pid */
    char* argv[] = { (char*)"sh", (char*)"-c", (char*)cmd, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/bin/sh", NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    if (rc != 0) return -1;
    g_pids[g_npid++] = pid;
    return (int32_t)pid;
}

void pn_kill(int32_t pid) { if (pid > 0) kill(-(pid_t)pid, SIGTERM); }

/* Block until host:port accepts a TCP connection, or timeout_ms elapses. */
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
            } else {
                freeaddrinfo(res);
            }
        }
        usleep(100 * 1000);
        waited += 100;
    }
    return 0;
}

/* Directory containing the running executable (for locating bundled assets). */
static char g_execdir[4096];
const char* pn_exec_dir(void) {
    char buf[4096];
    uint32_t sz = sizeof buf;
    if (_NSGetExecutablePath(buf, &sz) != 0) { g_execdir[0] = 0; return g_execdir; }
    char real[4096];
    if (realpath(buf, real)) strncpy(buf, real, sizeof buf - 1);
    strncpy(g_execdir, dirname(buf), sizeof g_execdir - 1);
    g_execdir[sizeof g_execdir - 1] = 0;
    return g_execdir;
}
