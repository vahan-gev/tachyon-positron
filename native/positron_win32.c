/* Positron native shim — Windows (Win32 + Microsoft Edge WebView2).
 *
 * Same flat C ABI as the other platforms. A WebView2 control fills a Win32
 * window; sidecar child processes (e.g. a Node.js server) run inside a Job
 * Object so the whole subtree is killed when the app exits.
 *
 * Requires the WebView2 SDK header (WebView2.h) at build time — put its folder
 * on C_INCLUDE_PATH — and, at runtime, WebView2Loader.dll plus the Edge
 * WebView2 runtime (present on current Windows 10/11). The loader entry point
 * is resolved dynamically, so no import library is needed.
 *
 * Set PW_AUTOQUIT_MS to auto-close (tests/CI).
 */
#ifndef UNICODE
#define UNICODE
#endif
#define COBJMACROS
#include <windows.h>
#include <objbase.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <WebView2.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HWND                     g_hwnd = NULL;
static ICoreWebView2Controller* g_controller = NULL;
static ICoreWebView2*           g_webview = NULL;
static int                      g_devtools = 0;
static wchar_t                  g_pending_url[4096] = L"";
static int                      g_have_pending = 0;

/* forward-declared handler singletons (defined at the bottom) */
static ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler g_envHandler;
static ICoreWebView2CreateCoreWebView2ControllerCompletedHandler  g_ctrlHandler;

/* ---------- helpers ---------- */

static wchar_t* pw_wide(const char* s) {
    if (!s) s = "";
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    wchar_t* w = (wchar_t*)malloc((size_t)n * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}

/* ---------- sidecar child processes (Job Object kills the whole tree) ---------- */

#define PW_MAXPROC 32
static PROCESS_INFORMATION g_procs[PW_MAXPROC];
static int    g_nproc = 0;
static HANDLE g_job = NULL;

static void pw_ensure_job(void) {
    if (g_job) return;
    g_job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info;
    memset(&info, 0, sizeof info);
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(g_job, JobObjectExtendedLimitInformation, &info, sizeof info);
}

static void pw_killall(void) {
    for (int i = 0; i < g_nproc; i++)
        if (g_procs[i].hProcess) TerminateProcess(g_procs[i].hProcess, 0);
    if (g_job) { CloseHandle(g_job); g_job = NULL; }  /* kill-on-close reaps children */
}

/* ---------- window proc ---------- */

static LRESULT CALLBACK pw_wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_SIZE:
            if (g_controller) {
                RECT b; GetClientRect(hwnd, &b);
                ICoreWebView2Controller_put_Bounds(g_controller, b);
            }
            return 0;
        case WM_TIMER:
            PostQuitMessage(0);
            return 0;
        case WM_DESTROY:
            pw_killall();
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

/* ---------- window / webview ---------- */

typedef HRESULT (STDMETHODCALLTYPE *CreateEnv_t)(
    PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions*,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*);

void pn_devtools(int32_t on) { g_devtools = on ? 1 : 0; }

void pn_window(const char* title, int32_t w, int32_t h) {
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

    WNDCLASSW wc;
    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc   = pw_wndproc;
    wc.hInstance     = GetModuleHandleW(NULL);
    wc.lpszClassName = L"PositronWindow";
    wc.hCursor       = LoadCursorW(NULL, IDC_ARROW);
    RegisterClassW(&wc);

    wchar_t* wtitle = pw_wide(title ? title : "Positron");
    g_hwnd = CreateWindowExW(0, L"PositronWindow", wtitle, WS_OVERLAPPEDWINDOW,
                             CW_USEDEFAULT, CW_USEDEFAULT, w, h,
                             NULL, NULL, wc.hInstance, NULL);
    free(wtitle);

    HMODULE loader = LoadLibraryW(L"WebView2Loader.dll");
    if (!loader) { fprintf(stderr, "positron: WebView2Loader.dll not found\n"); return; }
    CreateEnv_t create =
        (CreateEnv_t)GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");
    if (!create) { fprintf(stderr, "positron: WebView2 entry point missing\n"); return; }

    /* async — the environment/controller are created while the loop pumps */
    create(NULL, NULL, NULL, &g_envHandler);
}

void pn_load_url(const char* url) {
    wchar_t* w = pw_wide(url);
    wcsncpy(g_pending_url, w, 4095);
    g_pending_url[4095] = 0;
    g_have_pending = 1;
    free(w);
    if (g_webview) ICoreWebView2_Navigate(g_webview, g_pending_url);
}

void pn_load_html(const char* html) {
    wchar_t* w = pw_wide(html);
    if (g_webview) ICoreWebView2_NavigateToString(g_webview, w);
    free(w);
}

void pn_set_title(const char* t) {
    wchar_t* w = pw_wide(t);
    if (g_hwnd) SetWindowTextW(g_hwnd, w);
    free(w);
}

void pn_eval(const char* js) {
    wchar_t* w = pw_wide(js);
    if (g_webview) ICoreWebView2_ExecuteScript(g_webview, w, NULL);
    free(w);
}

void pn_run(void) {
    if (!g_hwnd) return;
    ShowWindow(g_hwnd, SW_SHOW);
    UpdateWindow(g_hwnd);
    const char* aq = getenv("PW_AUTOQUIT_MS");
    if (aq) SetTimer(g_hwnd, 1, (UINT)atoi(aq), NULL);
    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    pw_killall();
}

void pn_quit(void) {
    pw_killall();
    PostQuitMessage(0);
}

/* ---------- sidecar processes ---------- */

int32_t pn_spawn(const char* cmd) {
    if (g_nproc >= PW_MAXPROC || !cmd) return -1;
    pw_ensure_job();

    wchar_t* wcmd = pw_wide(cmd);
    size_t len = wcslen(wcmd) + 16;
    wchar_t* line = (wchar_t*)malloc(len * sizeof(wchar_t));
    _snwprintf(line, len, L"cmd /c %s", wcmd);
    free(wcmd);

    STARTUPINFOW si;
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof pi);

    BOOL ok = CreateProcessW(NULL, line, NULL, NULL, FALSE,
                             CREATE_NEW_PROCESS_GROUP | CREATE_SUSPENDED,
                             NULL, NULL, &si, &pi);
    free(line);
    if (!ok) return -1;
    AssignProcessToJobObject(g_job, pi.hProcess);
    ResumeThread(pi.hThread);
    g_procs[g_nproc++] = pi;
    return (int32_t)pi.dwProcessId;
}

void pn_kill(int32_t pid) {
    for (int i = 0; i < g_nproc; i++)
        if (g_procs[i].dwProcessId == (DWORD)pid && g_procs[i].hProcess)
            TerminateProcess(g_procs[i].hProcess, 0);
}

int32_t pn_wait_port(const char* host, int32_t port, int32_t timeout_ms) {
    WSADATA wsa;
    static int inited = 0;
    if (!inited) { WSAStartup(MAKEWORD(2, 2), &wsa); inited = 1; }

    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    char portstr[16];
    snprintf(portstr, sizeof portstr, "%d", port);

    int waited = 0;
    while (waited <= timeout_ms) {
        if (getaddrinfo(host ? host : "127.0.0.1", portstr, &hints, &res) == 0 && res) {
            SOCKET s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
            if (s != INVALID_SOCKET) {
                int ok = connect(s, res->ai_addr, (int)res->ai_addrlen);
                closesocket(s);
                freeaddrinfo(res);
                if (ok == 0) return 1;
            } else freeaddrinfo(res);
            res = NULL;
        }
        Sleep(100);
        waited += 100;
    }
    return 0;
}

static char g_execdir[4096];
const char* pn_exec_dir(void) {
    wchar_t buf[4096];
    DWORD n = GetModuleFileNameW(NULL, buf, 4096);
    if (n == 0) { strcpy(g_execdir, "."); return g_execdir; }
    for (DWORD i = n; i > 0; i--) {              /* strip the file name */
        if (buf[i - 1] == L'\\' || buf[i - 1] == L'/') { buf[i - 1] = 0; break; }
    }
    WideCharToMultiByte(CP_UTF8, 0, buf, -1, g_execdir, sizeof g_execdir, NULL, NULL);
    return g_execdir;
}

/* ---------- WebView2 async completion handlers (COM) ---------- */

static HRESULT STDMETHODCALLTYPE H_QueryInterface(void* This, REFIID riid, void** ppv) {
    (void)riid; *ppv = This; return S_OK;
}
static ULONG STDMETHODCALLTYPE H_AddRef(void* This)  { (void)This; return 1; }
static ULONG STDMETHODCALLTYPE H_Release(void* This) { (void)This; return 1; }

/* environment ready -> create the controller for our window */
static HRESULT STDMETHODCALLTYPE EnvH_Invoke(
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler* This,
        HRESULT result, ICoreWebView2Environment* env) {
    (void)This; (void)result;
    if (env)
        ICoreWebView2Environment_CreateCoreWebView2Controller(env, g_hwnd, &g_ctrlHandler);
    return S_OK;
}

/* controller ready -> grab the webview, size it, navigate */
static HRESULT STDMETHODCALLTYPE CtrlH_Invoke(
        ICoreWebView2CreateCoreWebView2ControllerCompletedHandler* This,
        HRESULT result, ICoreWebView2Controller* controller) {
    (void)This; (void)result;
    if (!controller) return S_OK;
    g_controller = controller;
    ICoreWebView2Controller_AddRef(controller);
    ICoreWebView2Controller_get_CoreWebView2(controller, &g_webview);

    RECT b; GetClientRect(g_hwnd, &b);
    ICoreWebView2Controller_put_Bounds(controller, b);

    if (g_webview) {
        ICoreWebView2Settings* settings = NULL;
        if (SUCCEEDED(ICoreWebView2_get_Settings(g_webview, &settings)) && settings)
            ICoreWebView2Settings_put_AreDevToolsEnabled(settings, g_devtools ? TRUE : FALSE);
        if (g_have_pending)
            ICoreWebView2_Navigate(g_webview, g_pending_url);
    }
    return S_OK;
}

static ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl g_envVtbl = {
    (void*)H_QueryInterface, (void*)H_AddRef, (void*)H_Release, EnvH_Invoke
};
static ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl g_ctrlVtbl = {
    (void*)H_QueryInterface, (void*)H_AddRef, (void*)H_Release, CtrlH_Invoke
};
static ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler g_envHandler = { &g_envVtbl };
static ICoreWebView2CreateCoreWebView2ControllerCompletedHandler  g_ctrlHandler = { &g_ctrlVtbl };
