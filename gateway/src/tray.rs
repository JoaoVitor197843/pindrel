//! Tray icon of the Windows gateway: whether it runs, start / stop / restart, and shortcuts to the settings and the log.
//!
//! A separate program on purpose (`pindrel-gateway-tray.exe`, cargo feature `tray`): `gateway.exe` stays a process with no
//! interface code in it, and only whoever wants the icon pays for it (a few hundred KB, a couple of MB of RAM). It does not
//! run the gateway itself: it asks the same scripts the Start menu shortcuts use (`start-gateway.ps1`, `stop-gateway.ps1`),
//! so a stop made here and a stop made there behave the same.
//!
//! `pindrel-gateway-tray.exe [--data <folder with gateway.env and gateway.log>]`, next to `gateway.exe`, `gateway.ico`
//! (running) and `gateway-off.ico` (stopped).
#![cfg_attr(windows, windows_subsystem = "windows")]

/// Where a person is sent when something unexpected happens.
const SUPPORT_URL: &str = "https://github.com/JoaoVitor197843/pindrel/issues";

/// The port written in the text of a `gateway.env` (`GATEWAY_PORT=8080`), if there is a valid one. Read with the gateway's
/// own parser, so the icon and the gateway always agree on what the file says.
#[allow(dead_code)]
fn port_in_env(text: &str) -> Option<u16> {
    pindrel_gateway::envfile::parse(text)
        .get("GATEWAY_PORT")?
        .parse::<u16>()
        .ok()
        .filter(|p| *p != 0)
}

/// The text of the tooltip and of the first line of the menu.
#[allow(dead_code)]
fn status_text(running: bool, port: Option<u16>) -> String {
    match (running, port) {
        (true, Some(p)) => format!("Pindrel Gateway: rodando (porta {p})"),
        (true, None) => "Pindrel Gateway: rodando".to_string(),
        (false, _) => "Pindrel Gateway: parado".to_string(),
    }
}

/// Windows paths compare without regard to case or to the kind of slash.
#[allow(dead_code)]
fn same_path(a: &str, b: &str) -> bool {
    let n = |s: &str| s.replace('/', "\\").trim_end_matches('\\').to_lowercase();
    n(a) == n(b)
}

/// A path as a single-quoted PowerShell string. The per-user install lives under the user's folder, and a name such as
/// `D'Ávila` would otherwise end the string early.
#[allow(dead_code)]
fn ps_quoted(path: &str) -> String {
    format!("'{}'", path.replace('\'', "''"))
}

#[cfg(not(windows))]
fn main() {
    eprintln!("pindrel-gateway-tray only exists for Windows ({SUPPORT_URL})");
}

#[cfg(windows)]
fn main() {
    win::run();
}

#[cfg(windows)]
mod win {
    use super::{port_in_env, ps_quoted, same_path, status_text, SUPPORT_URL};
    use std::os::windows::ffi::OsStrExt;
    use std::path::{Path, PathBuf};
    use std::ptr::{null, null_mut};
    use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU32, Ordering};
    use std::sync::OnceLock;
    use windows_sys::Win32::Foundation::{CloseHandle, GetLastError, ERROR_ALREADY_EXISTS, HWND, LPARAM, LRESULT, WPARAM};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
    };
    use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows_sys::Win32::System::Threading::{
        CreateMutexW, CreateProcessW, OpenProcess, QueryFullProcessImageNameW, CREATE_NO_WINDOW, PROCESS_INFORMATION,
        PROCESS_QUERY_LIMITED_INFORMATION, STARTUPINFOW,
    };
    use windows_sys::Win32::UI::Shell::{
        ShellExecuteW, Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NIM_MODIFY, NOTIFYICONDATAW,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        AppendMenuW, CreatePopupMenu, CreateWindowExW, DefWindowProcW, DestroyMenu, DispatchMessageW, GetCursorPos, GetMessageW,
        GetSystemMetrics, LoadIconW, LoadImageW, MessageBoxW, PostMessageW, PostQuitMessage, RegisterClassW, RegisterWindowMessageW,
        SetForegroundWindow, SetTimer, TrackPopupMenu, TranslateMessage, IDI_APPLICATION, IMAGE_ICON, LR_LOADFROMFILE, MB_ICONERROR, MB_OK,
        MF_GRAYED, MF_SEPARATOR, MF_STRING, MSG, SM_CXSMICON, SW_SHOWNORMAL, TPM_RETURNCMD, TPM_RIGHTBUTTON, WM_APP, WM_DESTROY,
        WM_LBUTTONUP, WM_NULL, WM_RBUTTONUP, WM_TIMER, WNDCLASSW,
    };

    const WM_TRAY: u32 = WM_APP + 1;
    const TIMER_ID: usize = 1;
    const TIMER_MS: u32 = 3000;
    const ID_TOGGLE: usize = 2;
    const ID_RESTART: usize = 3;
    const ID_CONFIG: usize = 4;
    const ID_LOG: usize = 5;
    const ID_DATA: usize = 6;
    const ID_QUIT: usize = 7;

    struct Paths {
        app: PathBuf,
        data: PathBuf,
    }

    static PATHS: OnceLock<Paths> = OnceLock::new();
    static RUNNING: AtomicBool = AtomicBool::new(false);
    static ICON_ON: AtomicIsize = AtomicIsize::new(0);
    static ICON_OFF: AtomicIsize = AtomicIsize::new(0);
    static TASKBAR_CREATED: AtomicU32 = AtomicU32::new(0);

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    fn wide_os(s: &std::ffi::OsStr) -> Vec<u16> {
        s.encode_wide().chain(std::iter::once(0)).collect()
    }

    fn paths() -> &'static Paths {
        PATHS.get().expect("paths are set before the window exists")
    }

    /// An error box that says what failed, where the logs are and who to tell.
    unsafe fn fail(hwnd: HWND, what: &str) {
        let text = format!(
            "{what}\n\nPara investigar, veja o registro em:\n{}\n\nSe o problema continuar, fale com quem mantém o projeto:\n{SUPPORT_URL}",
            paths().data.display()
        );
        MessageBoxW(hwnd, wide(&text).as_ptr(), wide("Pindrel Gateway").as_ptr(), MB_OK | MB_ICONERROR);
    }

    unsafe fn load_icon(name: &str) -> isize {
        let file = paths().app.join(name);
        let size = GetSystemMetrics(SM_CXSMICON);
        let h = LoadImageW(
            null_mut(),
            wide_os(file.as_os_str()).as_ptr(),
            IMAGE_ICON,
            size,
            size,
            LR_LOADFROMFILE,
        );
        if h.is_null() {
            // the files are missing: the plain application icon, so the tray still works
            LoadIconW(null_mut(), IDI_APPLICATION) as isize
        } else {
            h as isize
        }
    }

    fn port() -> Option<u16> {
        port_in_env(&std::fs::read_to_string(paths().data.join("gateway.env")).unwrap_or_default())
    }

    /// Is the `gateway.exe` of this folder running? (Another program called gateway.exe does not count.)
    unsafe fn gateway_running() -> bool {
        let want = paths().app.join("gateway.exe");
        let want = want.to_string_lossy().to_string();
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snap as isize == -1 {
            return false;
        }
        let mut entry: PROCESSENTRY32W = std::mem::zeroed();
        entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
        let mut found = false;
        let mut ok = Process32FirstW(snap, &mut entry) != 0;
        while ok && !found {
            let len = entry.szExeFile.iter().position(|c| *c == 0).unwrap_or(entry.szExeFile.len());
            let name = String::from_utf16_lossy(&entry.szExeFile[..len]);
            if name.eq_ignore_ascii_case("gateway.exe") {
                let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, entry.th32ProcessID);
                if !h.is_null() {
                    let mut buf = [0u16; 1024];
                    let mut n = buf.len() as u32;
                    if QueryFullProcessImageNameW(h, 0, buf.as_mut_ptr(), &mut n) != 0 {
                        found = same_path(&String::from_utf16_lossy(&buf[..n as usize]), &want);
                    }
                    CloseHandle(h);
                }
            }
            ok = Process32NextW(snap, &mut entry) != 0;
        }
        CloseHandle(snap);
        found
    }

    unsafe fn notify(hwnd: HWND, op: u32, running: bool) -> bool {
        let mut n: NOTIFYICONDATAW = std::mem::zeroed();
        n.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        n.hWnd = hwnd;
        n.uID = 1;
        n.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        n.uCallbackMessage = WM_TRAY;
        n.hIcon = (if running {
            ICON_ON.load(Ordering::Relaxed)
        } else {
            ICON_OFF.load(Ordering::Relaxed)
        }) as _;
        let tip = wide(&status_text(running, port()));
        let k = tip.len().min(n.szTip.len() - 1);
        n.szTip[..k].copy_from_slice(&tip[..k]);
        Shell_NotifyIconW(op, &n) != 0
    }

    /// Runs a command line with no window.
    unsafe fn run_hidden(command: &str) -> bool {
        let mut line = wide(command);
        let mut si: STARTUPINFOW = std::mem::zeroed();
        si.cb = std::mem::size_of::<STARTUPINFOW>() as u32;
        let mut pi: PROCESS_INFORMATION = std::mem::zeroed();
        let ok = CreateProcessW(
            null(),
            line.as_mut_ptr(),
            null(),
            null(),
            0,
            CREATE_NO_WINDOW,
            null(),
            null(),
            &si,
            &mut pi,
        ) != 0;
        if ok {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
        ok
    }

    fn script(name: &str) -> String {
        paths().app.join(name).display().to_string()
    }

    unsafe fn start(hwnd: HWND) {
        let cmd = format!(
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{}\"",
            script("start-gateway.ps1")
        );
        if !run_hidden(&cmd) {
            fail(hwnd, "Não foi possível iniciar o gateway (o PowerShell não abriu).");
        }
    }

    unsafe fn stop(hwnd: HWND) {
        let cmd = format!(
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{}\"",
            script("stop-gateway.ps1")
        );
        if !run_hidden(&cmd) {
            fail(hwnd, "Não foi possível parar o gateway (o PowerShell não abriu).");
        }
    }

    unsafe fn restart(hwnd: HWND) {
        let cmd = format!(
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"& {}; Start-Sleep -Seconds 1; & {}\"",
            ps_quoted(&script("stop-gateway.ps1")),
            ps_quoted(&script("start-gateway.ps1"))
        );
        if !run_hidden(&cmd) {
            fail(hwnd, "Não foi possível reiniciar o gateway (o PowerShell não abriu).");
        }
    }

    /// Opens a text file in Notepad, or a folder in Explorer.
    unsafe fn open(hwnd: HWND, path: &Path, in_notepad: bool) {
        if !path.exists() {
            let what = format!("{} ainda não existe.", path.display());
            fail(hwnd, &what);
            return;
        }
        let (file, args) = if in_notepad {
            (wide("notepad.exe"), wide(&format!("\"{}\"", path.display())))
        } else {
            (wide_os(path.as_os_str()), vec![0u16])
        };
        let r = ShellExecuteW(
            hwnd,
            wide("open").as_ptr(),
            file.as_ptr(),
            if in_notepad { args.as_ptr() } else { null() },
            null(),
            SW_SHOWNORMAL as _,
        );
        if (r as isize) <= 32 {
            let what = format!("Não foi possível abrir {}.", path.display());
            fail(hwnd, &what);
        }
    }

    unsafe fn menu(hwnd: HWND) {
        let running = gateway_running();
        let m = CreatePopupMenu();
        AppendMenuW(m, MF_STRING | MF_GRAYED, 1, wide(&status_text(running, port())).as_ptr());
        AppendMenuW(m, MF_SEPARATOR, 0, null());
        AppendMenuW(
            m,
            MF_STRING,
            ID_TOGGLE,
            wide(if running { "Parar o gateway" } else { "Iniciar o gateway" }).as_ptr(),
        );
        AppendMenuW(m, MF_STRING, ID_RESTART, wide("Reiniciar o gateway").as_ptr());
        AppendMenuW(m, MF_SEPARATOR, 0, null());
        AppendMenuW(m, MF_STRING, ID_CONFIG, wide("Abrir a configuração (gateway.env)").as_ptr());
        AppendMenuW(m, MF_STRING, ID_LOG, wide("Abrir o registro (gateway.log)").as_ptr());
        AppendMenuW(m, MF_STRING, ID_DATA, wide("Abrir a pasta dos dados").as_ptr());
        AppendMenuW(m, MF_SEPARATOR, 0, null());
        AppendMenuW(
            m,
            MF_STRING,
            ID_QUIT,
            wide(if running {
                "Sair deste ícone (o gateway continua)"
            } else {
                "Sair deste ícone"
            })
            .as_ptr(),
        );
        let mut pt = std::mem::zeroed();
        GetCursorPos(&mut pt);
        // the menu closes when a click lands outside it only if the window is in the foreground first
        SetForegroundWindow(hwnd);
        let id = TrackPopupMenu(m, TPM_RIGHTBUTTON | TPM_RETURNCMD, pt.x, pt.y, 0, hwnd, null());
        PostMessageW(hwnd, WM_NULL, 0, 0);
        DestroyMenu(m);
        match id as usize {
            ID_TOGGLE => {
                if running {
                    stop(hwnd)
                } else {
                    start(hwnd)
                }
            }
            ID_RESTART => restart(hwnd),
            ID_CONFIG => open(hwnd, &paths().data.join("gateway.env"), true),
            ID_LOG => open(hwnd, &paths().data.join("gateway.log"), true),
            ID_DATA => open(hwnd, &paths().data, false),
            ID_QUIT => {
                notify(hwnd, NIM_DELETE, running);
                PostQuitMessage(0);
            }
            _ => {}
        }
    }

    unsafe extern "system" fn proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
        match msg {
            WM_TRAY => {
                let ev = (lp & 0xFFFF) as u32;
                if ev == WM_LBUTTONUP || ev == WM_RBUTTONUP {
                    menu(hwnd);
                }
                0
            }
            WM_TIMER => {
                let now = gateway_running();
                if now != RUNNING.swap(now, Ordering::Relaxed) {
                    notify(hwnd, NIM_MODIFY, now);
                }
                0
            }
            WM_DESTROY => {
                PostQuitMessage(0);
                0
            }
            m if m != 0 && m == TASKBAR_CREATED.load(Ordering::Relaxed) => {
                // Explorer restarted: its tray is empty again
                notify(hwnd, NIM_ADD, RUNNING.load(Ordering::Relaxed));
                0
            }
            _ => DefWindowProcW(hwnd, msg, wp, lp),
        }
    }

    pub fn run() {
        // `--data <folder>`; without it, %LOCALAPPDATA%\Pindrel Gateway
        let mut data: Option<PathBuf> = None;
        let mut args = std::env::args_os().skip(1);
        while let Some(a) = args.next() {
            if a == "--data" {
                data = args.next().map(PathBuf::from);
            }
        }
        let app = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(Path::to_path_buf))
            .unwrap_or_default();
        let data = data.unwrap_or_else(|| PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap_or_default()).join("Pindrel Gateway"));
        let _ = PATHS.set(Paths { app, data });
        unsafe {
            // one icon per person: a second start just leaves
            let name = wide("Local\\PindrelGatewayTray");
            let mutex = CreateMutexW(null(), 0, name.as_ptr());
            if mutex.is_null() || GetLastError() == ERROR_ALREADY_EXISTS {
                return;
            }
            ICON_ON.store(load_icon("gateway.ico"), Ordering::Relaxed);
            ICON_OFF.store(load_icon("gateway-off.ico"), Ordering::Relaxed);
            TASKBAR_CREATED.store(RegisterWindowMessageW(wide("TaskbarCreated").as_ptr()), Ordering::Relaxed);

            let hinst = GetModuleHandleW(null());
            let class = wide("PindrelGatewayTray");
            let wc = WNDCLASSW {
                style: 0,
                lpfnWndProc: Some(proc),
                cbClsExtra: 0,
                cbWndExtra: 0,
                hInstance: hinst,
                hIcon: null_mut(),
                hCursor: null_mut(),
                hbrBackground: null_mut(),
                lpszMenuName: null(),
                lpszClassName: class.as_ptr(),
            };
            if RegisterClassW(&wc) == 0 {
                fail(null_mut(), "Não foi possível criar a janela do ícone (RegisterClassW falhou).");
                return;
            }
            // a hidden top-level window (not a message-only one: only those receive "TaskbarCreated")
            let hwnd = CreateWindowExW(
                0,
                class.as_ptr(),
                wide("Pindrel Gateway").as_ptr(),
                0,
                0,
                0,
                0,
                0,
                null_mut(),
                null_mut(),
                hinst,
                null(),
            );
            if hwnd.is_null() {
                fail(null_mut(), "Não foi possível criar a janela do ícone (CreateWindowExW falhou).");
                return;
            }
            let running = gateway_running();
            RUNNING.store(running, Ordering::Relaxed);
            if !notify(hwnd, NIM_ADD, running) {
                fail(hwnd, "O Windows não aceitou o ícone da bandeja (Shell_NotifyIconW falhou).");
                return;
            }
            SetTimer(hwnd, TIMER_ID, TIMER_MS, None);
            let mut msg: MSG = std::mem::zeroed();
            while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
            CloseHandle(mutex);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_port_comes_from_the_last_valid_line() {
        assert_eq!(port_in_env("SERVER_NAME=x\nGATEWAY_PORT=8087\n"), Some(8087));
        assert_eq!(
            port_in_env("# GATEWAY_PORT=1\nGATEWAY_PORT = 9\n"),
            Some(9),
            "same reading as the gateway: spaces around = are fine"
        );
        assert_eq!(port_in_env("export GATEWAY_PORT=\"8081\"\n"), Some(8081));
        assert_eq!(port_in_env("GATEWAY_PORT=70000\n"), None);
        assert_eq!(port_in_env("GATEWAY_PORT=0\n"), None);
        assert_eq!(port_in_env("GATEWAY_PORT=abc\n"), None);
        assert_eq!(port_in_env("GATEWAY_PORT=1\nGATEWAY_PORT=2\n"), Some(2));
        assert_eq!(port_in_env(""), None);
    }

    #[test]
    fn the_status_says_what_runs() {
        assert_eq!(status_text(true, Some(8080)), "Pindrel Gateway: rodando (porta 8080)");
        assert_eq!(status_text(true, None), "Pindrel Gateway: rodando");
        assert_eq!(status_text(false, Some(8080)), "Pindrel Gateway: parado");
    }

    #[test]
    fn a_quote_in_a_path_does_not_end_the_powershell_string() {
        assert_eq!(ps_quoted(r"C:\Program Files\x.ps1"), r"'C:\Program Files\x.ps1'");
        assert_eq!(
            ps_quoted(r"C:\Users\D'Ávila\AppData\Local\Programs\x.ps1"),
            r"'C:\Users\D''Ávila\AppData\Local\Programs\x.ps1'"
        );
    }

    #[test]
    fn paths_compare_like_windows_does() {
        assert!(same_path(r"C:\Users\Ana\gateway.exe", r"c:/users/ana/GATEWAY.EXE"));
        assert!(same_path(r"C:\x\", r"C:\x"));
        assert!(!same_path(r"C:\a\gateway.exe", r"C:\b\gateway.exe"));
    }
}
