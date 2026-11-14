use std::fs;
use std::path::PathBuf;
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, WindowEvent,
};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

/// The store shared with the agent CLI and the `mindpalace` Claude Code skill.
/// MINDPALACE_DATA overrides everywhere. Dev builds use the repo; installed
/// builds use the platform data dir (%APPDATA% / XDG_DATA_HOME).
fn data_file() -> PathBuf {
    if let Ok(p) = std::env::var("MINDPALACE_DATA") {
        return PathBuf::from(p);
    }
    #[cfg(debug_assertions)]
    {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../agent/data/palace.json")
    }
    #[cfg(not(debug_assertions))]
    {
        let base = if cfg!(target_os = "windows") {
            PathBuf::from(std::env::var("APPDATA").unwrap_or_else(|_| ".".into()))
        } else {
            match std::env::var("XDG_DATA_HOME") {
                Ok(x) => PathBuf::from(x),
                Err(_) => PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into()))
                    .join(".local")
                    .join("share"),
            }
        };
        base.join("MindPalace").join("palace.json")
    }
}

/// Optional per-install settings, written by the installers. Lives next to
/// palace.json (config.json); MINDPALACE_CONFIG overrides the location.
/// Every field is optional — absent means today's built-in defaults.
#[derive(serde::Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
struct AppConfig {
    hotkey: Option<String>,
    fallback_hotkey: Option<String>,
    window: Option<WindowSize>,
    autostart: Option<bool>,
    search_url: Option<String>,
    /// "dark" or "light" forces a theme; absent/other = follow the OS.
    theme: Option<String>,
}

#[derive(serde::Deserialize)]
struct WindowSize {
    width: f64,
    height: f64,
}

fn load_config() -> AppConfig {
    let path = match std::env::var("MINDPALACE_CONFIG") {
        Ok(p) => PathBuf::from(p),
        Err(_) => data_dir().join("config.json"),
    };
    fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

#[tauri::command]
fn load_items() -> Result<String, String> {
    let path = data_file();
    if !path.exists() {
        return Ok("[]".into());
    }
    fs::read_to_string(&path).map_err(|e| e.to_string())
}

/// Directory that holds palace.json and the vault folder.
fn data_dir() -> PathBuf {
    data_file().parent().expect("data file has a parent").to_path_buf()
}

/// Resolve a store-relative path (e.g. "vault/x.png") and confine it to the
/// data directory — item content is data, not a free file-system handle.
fn resolve_rel(rel: &str) -> Result<PathBuf, String> {
    let base = dunce::canonicalize(data_dir()).map_err(|e| e.to_string())?;
    let joined = base.join(rel);
    let canon = dunce::canonicalize(&joined).map_err(|e| e.to_string())?;
    if !canon.starts_with(&base) {
        return Err("path escapes the data directory".into());
    }
    Ok(canon)
}

fn vault_dir() -> Result<PathBuf, String> {
    let dir = data_dir().join("vault");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn short_id() -> String {
    uuid::Uuid::new_v4().simple().to_string()[..8].to_string()
}

/// Save a pasted image (base64-encoded bytes) into the vault.
#[tauri::command]
fn save_image(b64: String, ext: String) -> Result<String, String> {
    use base64::Engine;
    if !ext.chars().all(|c| c.is_ascii_alphanumeric()) || ext.len() > 5 {
        return Err("bad extension".into());
    }
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(b64)
        .map_err(|e| e.to_string())?;
    let name = format!("{}.{}", short_id(), ext);
    fs::write(vault_dir()?.join(&name), bytes).map_err(|e| e.to_string())?;
    Ok(format!("vault/{name}"))
}

#[derive(serde::Serialize)]
struct ImportedFile {
    path: String,
    name: String,
    size: u64,
}

/// Copy a dropped file into the vault (original name kept, prefixed with an id).
#[tauri::command]
fn import_file(src: String) -> Result<ImportedFile, String> {
    let srcp = PathBuf::from(&src);
    let fname = srcp
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or("no file name")?
        .to_string();
    let name = format!("{}-{}", short_id(), fname);
    let dest = vault_dir()?.join(&name);
    fs::copy(&srcp, &dest).map_err(|e| e.to_string())?;
    let size = fs::metadata(&dest).map_err(|e| e.to_string())?.len();
    Ok(ImportedFile {
        path: format!("vault/{name}"),
        name: fname,
        size,
    })
}

/// Read a vault file as base64 (thumbnails / previews).
#[tauri::command]
fn read_file_b64(rel: String) -> Result<String, String> {
    use base64::Engine;
    let bytes = fs::read(resolve_rel(&rel)?).map_err(|e| e.to_string())?;
    Ok(base64::engine::general_purpose::STANDARD.encode(bytes))
}

/// Open a vault file with its default application.
#[tauri::command]
fn open_vault_path(rel: String) -> Result<(), String> {
    tauri_plugin_opener::open_path(resolve_rel(&rel)?, None::<&str>).map_err(|e| e.to_string())
}

/// Absolute path of a vault file (e.g. to copy a file item's path).
#[tauri::command]
fn resolve_vault_path(rel: String) -> Result<String, String> {
    Ok(resolve_rel(&rel)?.to_string_lossy().into_owned())
}

/// Reveal a vault file in Explorer.
#[tauri::command]
fn reveal_vault_path(rel: String) -> Result<(), String> {
    tauri_plugin_opener::reveal_item_in_dir(resolve_rel(&rel)?).map_err(|e| e.to_string())
}

/// Open the default browser with a web search for `query` (the editor's
/// `--search` inline command). The engine is config.json's `searchUrl`
/// prefix; the query is percent-encoded here, so the page can't be steered
/// by note content beyond the search terms.
#[tauri::command]
fn web_search(query: String) -> Result<(), String> {
    let base = load_config()
        .search_url
        .unwrap_or_else(|| "https://www.google.com/search?q=".into());
    let mut enc = String::with_capacity(query.len() * 3);
    for b in query.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                enc.push(b as char)
            }
            _ => enc.push_str(&format!("%{b:02X}")),
        }
    }
    let url = format!("{base}{enc}");
    let result = tauri_plugin_opener::open_url(&url, None::<&str>);
    // One-line breadcrumb next to palace.json — ground truth when a search
    // "does nothing" (overwritten every call, so it never grows).
    let _ = fs::write(
        data_dir().join("search.log"),
        format!("{:?}\nurl: {url}\nresult: {result:?}\n", std::time::SystemTime::now()),
    );
    result.map_err(|e| e.to_string())
}

// ─── AI integration (opt-in, pluggable CLI backends) ──────────────────
//
// Privacy contract: `ai_run` is the ONLY place note text reaches an AI, and
// it refuses while config.json has no backend. Everything else in the app is
// local. The instructions per command live in SKILLS.md next to palace.json.

/// Raw config.json as a Value — used for read-modify-write so unknown keys
/// (and keys the typed AppConfig doesn't model) always survive.
fn config_value() -> serde_json::Value {
    let path = match std::env::var("MINDPALACE_CONFIG") {
        Ok(p) => PathBuf::from(p),
        Err(_) => data_dir().join("config.json"),
    };
    fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| serde_json::json!({}))
}

fn write_config_value(v: &serde_json::Value) -> Result<(), String> {
    let path = match std::env::var("MINDPALACE_CONFIG") {
        Ok(p) => PathBuf::from(p),
        Err(_) => data_dir().join("config.json"),
    };
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    fs::write(&path, serde_json::to_string_pretty(v).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}

const AI_BACKENDS: &[&str] = &["claude", "codex", "opencode", "ollama"];

/// Find how to invoke a CLI: a ready-to-use argv prefix, or None.
/// Handles npm's .cmd shims on Windows (they need `cmd /C`).
fn resolve_cli(name: &str) -> Option<Vec<String>> {
    #[cfg(target_os = "windows")]
    let finder = ("where.exe", name);
    #[cfg(not(target_os = "windows"))]
    let finder = ("which", name);
    if let Ok((out, _, ok)) = run_argv(&[finder.0.into(), finder.1.into()], 10) {
        if ok {
            if let Some(path) = out.lines().next().map(str::trim).filter(|l| !l.is_empty()) {
                let lower = path.to_lowercase();
                if lower.ends_with(".cmd") || lower.ends_with(".bat") {
                    return Some(vec!["cmd".into(), "/C".into(), path.into()]);
                }
                return Some(vec![path.into()]);
            }
        }
    }
    #[cfg(target_os = "windows")]
    {
        let home = std::env::var("USERPROFILE").unwrap_or_default();
        let p = PathBuf::from(home).join(".local").join("bin").join(format!("{name}.exe"));
        if p.exists() {
            return Some(vec![p.to_string_lossy().into_owned()]);
        }
    }
    None
}

/// Run argv with no window, null stdin, piped output, and a hard timeout.
/// Output is drained on threads so a chatty child can never deadlock us.
fn run_argv(argv: &[String], timeout_secs: u64) -> Result<(String, String, bool), String> {
    use std::io::Read;
    use std::process::Stdio;
    let (prog, rest) = argv.split_first().ok_or("empty command")?;
    let mut cmd = std::process::Command::new(prog);
    cmd.args(rest)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let mut child = cmd.spawn().map_err(|e| format!("could not start {prog}: {e}"))?;
    let mut so = child.stdout.take().unwrap();
    let mut se = child.stderr.take().unwrap();
    let t_out = std::thread::spawn(move || {
        let mut s = String::new();
        let _ = so.read_to_string(&mut s);
        s
    });
    let t_err = std::thread::spawn(move || {
        let mut s = String::new();
        let _ = se.read_to_string(&mut s);
        s
    });
    let started = std::time::Instant::now();
    let status = loop {
        match child.try_wait().map_err(|e| e.to_string())? {
            Some(st) => break st,
            None => {
                if started.elapsed().as_secs() >= timeout_secs {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("timed out after {timeout_secs}s"));
                }
                std::thread::sleep(std::time::Duration::from_millis(150));
            }
        }
    };
    let stdout = t_out.join().unwrap_or_default();
    let stderr = t_err.join().unwrap_or_default();
    Ok((stdout, stderr, status.success()))
}

fn skills_file() -> PathBuf {
    data_dir().join("SKILLS.md")
}

const DEFAULT_SKILLS: &str = r#"# MindPalace AI skills

Each `## name` section below is an inline command: end a line in the pad
with `--name` and press Enter. The section text is the instruction given to
the AI, followed by your line's text. Add your own section (for example
`## summarize`) to create a new command - no code changes needed.

AI runs only while connected (the star button in the titlebar). Only the
single line you run a command on is ever sent - never the whole note.

## translate

Translate the text that follows between Japanese and English: if it is
Japanese, translate it to natural English; otherwise translate it to natural
Japanese. Reply with ONLY the translation - no explanations, no quotes.

## rephrase

Rephrase the text that follows to be clearer, more natural and concise.
Keep the original language and the meaning. Reply with ONLY the rephrased
text - no explanations.
"#;

/// Parse `## name` section names out of SKILLS.md.
fn skill_names(md: &str) -> Vec<String> {
    md.lines()
        .filter_map(|l| l.strip_prefix("## "))
        .map(|s| s.trim().to_lowercase())
        .collect()
}

/// Body of one `## name` section.
fn skill_body(md: &str, name: &str) -> Option<String> {
    let mut body = String::new();
    let mut inside = false;
    for line in md.lines() {
        if let Some(h) = line.strip_prefix("## ") {
            inside = h.trim().eq_ignore_ascii_case(name);
            continue;
        }
        if inside {
            body.push_str(line);
            body.push('\n');
        }
    }
    let body = body.trim().to_string();
    if body.is_empty() { None } else { Some(body) }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct AiStatus {
    backend: Option<String>,
    version: Option<String>,
    available: Vec<String>,
    skills: Vec<String>,
}

fn current_backend() -> Option<String> {
    match config_value().get("ai") {
        Some(serde_json::Value::String(s)) if !s.is_empty() => Some(s.clone()),
        _ => None,
    }
}

fn status_now(check: bool) -> AiStatus {
    let backend = current_backend();
    let mut available = Vec::new();
    let mut version = None;
    if check {
        for name in AI_BACKENDS {
            if let Some(mut argv) = resolve_cli(name) {
                argv.push("--version".into());
                if let Ok((out, _, true)) = run_argv(&argv, 20) {
                    available.push((*name).to_string());
                    let is_current =
                        backend.as_deref() == Some(*name) || (backend.is_none() && version.is_none());
                    if is_current {
                        version = out.lines().next().map(|l| l.trim().to_string());
                    }
                }
            }
        }
    }
    let skills = fs::read_to_string(skills_file())
        .map(|md| skill_names(&md))
        .unwrap_or_default();
    AiStatus { backend, version, available, skills }
}

#[tauri::command]
fn ai_status(check: bool) -> AiStatus {
    status_now(check)
}

/// Connect (backend name) or disconnect (false). Creates SKILLS.md with the
/// default translate/rephrase skills on first connect.
#[tauri::command]
fn ai_set(backend: serde_json::Value) -> Result<AiStatus, String> {
    let mut cfg = config_value();
    match &backend {
        serde_json::Value::String(name) if AI_BACKENDS.contains(&name.as_str()) || name == "custom" => {
            cfg["ai"] = backend.clone();
            if !skills_file().exists() {
                fs::write(skills_file(), DEFAULT_SKILLS).map_err(|e| e.to_string())?;
            }
        }
        _ => {
            cfg["ai"] = serde_json::Value::Bool(false);
        }
    }
    write_config_value(&cfg)?;
    Ok(status_now(false))
}

/// Run one SKILLS.md skill on one piece of text. The only AI entry point.
#[tauri::command]
fn ai_run(task: String, text: String) -> Result<String, String> {
    let backend = current_backend().ok_or("AI is off — click the AI button to connect")?;
    if !task.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-') {
        return Err("bad skill name".into());
    }
    let md = fs::read_to_string(skills_file())
        .map_err(|_| "SKILLS.md not found next to palace.json — reconnect AI to recreate it")?;
    let instruction = skill_body(&md, &task)
        .ok_or_else(|| format!("no '## {task}' skill in SKILLS.md"))?;
    let prompt = format!("{instruction}\n\nText:\n{text}");

    let cfg = config_value();
    let mut argv: Vec<String> = match backend.as_str() {
        "custom" => {
            let tmpl = cfg
                .get("aiCommand")
                .and_then(|v| v.as_array())
                .ok_or("backend 'custom' needs \"aiCommand\": [...] in config.json")?;
            let mut argv: Vec<String> = tmpl
                .iter()
                .map(|v| v.as_str().unwrap_or_default().replace("{prompt}", &prompt))
                .collect();
            if !tmpl.iter().any(|v| v.as_str().unwrap_or_default().contains("{prompt}")) {
                argv.push(prompt.clone());
            }
            argv
        }
        name => {
            let mut argv = resolve_cli(name)
                .ok_or_else(|| format!("{name} CLI not found — is it installed and on PATH?"))?;
            match name {
                "claude" => argv.push("-p".into()),
                "codex" => argv.push("exec".into()),
                "opencode" => argv.push("run".into()),
                "ollama" => {
                    argv.push("run".into());
                    let model = cfg
                        .get("aiModel")
                        .and_then(|v| v.as_str())
                        .ok_or("ollama needs \"aiModel\" in config.json (e.g. \"qwen2.5:3b\")")?;
                    argv.push(model.into());
                }
                _ => return Err(format!("unknown backend {name}")),
            }
            argv.push(prompt.clone());
            argv
        }
    };
    if argv.is_empty() {
        argv.push(prompt);
    }
    let (stdout, stderr, ok) = run_argv(&argv, 90)?;
    // Breadcrumb like search.log — ground truth when an AI reply looks wrong.
    let _ = fs::write(
        data_dir().join("ai.log"),
        format!(
            "task: {task}\nargv[0]: {}\nn_args: {}\nok: {ok}\nstdout({}): {}\nstderr({}): {}\n",
            argv[0],
            argv.len(),
            stdout.len(),
            stdout.chars().take(400).collect::<String>(),
            stderr.len(),
            stderr.chars().take(400).collect::<String>()
        ),
    );
    let out = stdout.trim();
    if ok && !out.is_empty() {
        Ok(out.to_string())
    } else {
        let tail: String = stderr.trim().chars().rev().take(200).collect::<String>().chars().rev().collect();
        Err(if tail.is_empty() { "AI returned nothing".into() } else { tail })
    }
}

#[tauri::command]
fn save_items(json: String) -> Result<(), String> {
    // The store is also edited by hand/skill: never write something that
    // would corrupt it for the other tools.
    serde_json::from_str::<Vec<serde_json::Value>>(&json)
        .map_err(|e| format!("refusing to save: not a JSON item array: {e}"))?;
    let path = data_file();
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    fs::write(&path, json).map_err(|e| e.to_string())
}

fn toggle_window(app: &tauri::AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        // A minimized window still reports is_visible() == true, but with
        // skipTaskbar there is no taskbar button to restore it — treat it
        // as hidden and bring it back, or it is lost forever.
        let minimized = win.is_minimized().unwrap_or(false);
        if win.is_visible().unwrap_or(false) && !minimized {
            let _ = win.hide();
        } else {
            let _ = win.unminimize();
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Launching a second instance toggles the existing window instead.
        // On Wayland (where app-registered global hotkeys don't work) this
        // is the hotkey: bind the compositor key to exec the binary.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            toggle_window(app);
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        toggle_window(app);
                    }
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            load_items,
            save_items,
            save_image,
            import_file,
            read_file_b64,
            open_vault_path,
            reveal_vault_path,
            resolve_vault_path,
            web_search,
            ai_status,
            ai_set,
            ai_run
        ])
        .setup(|app| {
            let win = app.get_webview_window("main").unwrap();
            let cfg = load_config();

            // Theme: follow the OS by default; config.json `theme` forces one
            // (set_theme also flips the webview's prefers-color-scheme, which
            // drives every color in CSS).
            match cfg.theme.as_deref() {
                Some("dark") => { let _ = win.set_theme(Some(tauri::Theme::Dark)); }
                Some("light") => { let _ = win.set_theme(Some(tauri::Theme::Light)); }
                _ => {}
            }

            // OS-level glass: real acrylic blur behind the transparent window,
            // tinted to match the effective theme and re-tinted on OS switches.
            #[cfg(target_os = "windows")]
            {
                use window_vibrancy::apply_acrylic;
                fn tint(theme: tauri::Theme) -> (u8, u8, u8, u8) {
                    match theme {
                        tauri::Theme::Light => (245, 245, 245, 160),
                        _ => (18, 18, 18, 140),
                    }
                }
                let _ = apply_acrylic(&win, Some(tint(win.theme().unwrap_or(tauri::Theme::Dark))));
                let acrylic_win = win.clone();
                win.on_window_event(move |e| {
                    if let tauri::WindowEvent::ThemeChanged(t) = e {
                        let _ = apply_acrylic(&acrylic_win, Some(tint(*t)));
                    }
                });
            }

            if let Some(size) = &cfg.window {
                let _ = win.set_size(tauri::LogicalSize::new(size.width, size.height));
                let _ = win.center();
            }

            // Global hotkey: config.json's choice first, then its fallback,
            // then the built-in pair — first one that parses and registers wins
            // (another app may own a combination).
            let gs = app.global_shortcut();
            let mut candidates: Vec<String> = Vec::new();
            candidates.extend(cfg.hotkey.clone());
            candidates.extend(cfg.fallback_hotkey.clone());
            candidates.push("ctrl+shift+space".into());
            candidates.push("alt+space".into());
            let mut registered: Option<String> = None;
            for cand in candidates {
                if let Ok(sc) = cand.parse::<Shortcut>() {
                    if gs.register(sc).is_ok() {
                        registered = Some(cand);
                        break;
                    }
                }
            }
            let tooltip = match &registered {
                Some(k) => format!("MindPalace ({k})"),
                None => "MindPalace".to_string(),
            };

            // Tray: left click toggles; menu has Show/Hide and Quit.
            let show = MenuItem::with_id(app, "toggle", "Show / Hide", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;
            TrayIconBuilder::with_id("tray")
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip(&tooltip)
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "toggle" => toggle_window(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    use tauri::tray::{MouseButton, MouseButtonState, TrayIconEvent};
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_window(tray.app_handle());
                    }
                })
                .build(app)?;

            // Autostart only in release builds — a dev-build registry entry
            // would point at a temporary target/debug exe.
            #[cfg(not(debug_assertions))]
            {
                use tauri_plugin_autostart::ManagerExt;
                if cfg.autostart.unwrap_or(true) {
                    let _ = app.autolaunch().enable();
                } else {
                    let _ = app.autolaunch().disable();
                }
            }
            #[cfg(debug_assertions)]
            let _ = &cfg.autostart;

            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                // Close button hides to tray; Quit lives in the tray menu.
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Integration check: exercises SKILLS.md lookup + CLI spawn end to end.
    /// Needs MINDPALACE_DATA pointing at a store with SKILLS.md and ai set.
    #[test]
    #[ignore]
    fn ai_roundtrip() {
        let out = ai_run("translate".into(), "see you tomorrow".into());
        eprintln!("ai_run -> {out:?}");
        let text = out.expect("ai_run failed");
        assert!(!text.is_empty());
        assert_ne!(text.trim(), "see you tomorrow", "AI echoed the input");
    }
}
