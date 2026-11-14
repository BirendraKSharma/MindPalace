import { useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import Editor, { type EditorHandle } from "./Editor";
import { itemScore } from "./fuzzy";
import { aiState } from "./commands";
import "./App.css";

interface AiStatus {
  backend: string | null;
  version: string | null;
  available: string[];
  skills: string[];
}

interface Item {
  id: string;
  type: "text" | "image" | "file";
  content: string;
  title: string;
  tags: string[];
  summary: string;
  createdAt: string;
  pinned: boolean;
  archived: boolean;
}

type Filter = "all" | "text" | "image" | "file" | "arc";

const appWindow = getCurrentWindow();

function relTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1) return "now";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  const d = Math.floor(h / 24);
  if (d < 30) return `${d}d`;
  return new Date(iso).toLocaleDateString();
}

function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

const IMG_RE = /\.(png|jpe?g|gif|webp|bmp)$/i;

function mimeOf(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase() ?? "";
  const map: Record<string, string> = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    bmp: "image/bmp",
  };
  return map[ext] ?? "application/octet-stream";
}

function u8ToB64(u8: Uint8Array): string {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < u8.length; i += chunk) {
    s += String.fromCharCode(...u8.subarray(i, i + chunk));
  }
  return btoa(s);
}

function titleFrom(content: string): string {
  const first = content.split("\n").find((l) => l.trim()) ?? "";
  return first.replace(/^#+\s*/, "").slice(0, 60) || "(untitled)";
}

function newId(): string {
  return crypto.randomUUID().slice(0, 8);
}

export default function App() {
  const [items, setItems] = useState<Item[]>([]);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [activeId, setActiveId] = useState<string | null>(null);
  const [buffer, setBuffer] = useState({ key: "new", initial: "" });
  const [status, setStatus] = useState<string>("");
  const [ai, setAi] = useState<AiStatus | null>(null);
  const [thumbs, setThumbs] = useState<Record<string, string>>({});
  const [dragging, setDragging] = useState(false);
  const [sel, setSel] = useState(0);

  const editorRef = useRef<EditorHandle>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const itemsRef = useRef(items);
  itemsRef.current = items;
  const activeIdRef = useRef(activeId);
  activeIdRef.current = activeId;
  const thumbsLoading = useRef(new Set<string>());
  const pending = useRef<{ timer: number | null; content: string | null }>({
    timer: null,
    content: null,
  });

  async function persist(next: Item[]) {
    setItems(next);
    try {
      await invoke("save_items", { json: JSON.stringify(next, null, 2) });
    } catch (e) {
      console.error(e);
    }
  }

  function flush() {
    const content = pending.current.content;
    if (pending.current.timer) {
      clearTimeout(pending.current.timer);
      pending.current.timer = null;
    }
    pending.current.content = null;
    if (content === null) return;
    if (activeIdRef.current === null) {
      if (!content.trim()) return;
      const item: Item = {
        id: newId(),
        type: "text",
        content,
        title: titleFrom(content),
        tags: [],
        summary: "",
        createdAt: new Date().toISOString(),
        pinned: false,
        archived: false,
      };
      activeIdRef.current = item.id;
      setActiveId(item.id);
      void persist([...itemsRef.current, item]);
    } else {
      void persist(
        itemsRef.current.map((i) =>
          i.id === activeIdRef.current
            ? { ...i, content, title: titleFrom(content) }
            : i,
        ),
      );
    }
    setStatus("saved");
  }

  function queueSave(content: string) {
    pending.current.content = content;
    if (pending.current.timer) clearTimeout(pending.current.timer);
    pending.current.timer = window.setTimeout(flush, 700);
    setStatus("…");
  }

  function setActive(id: string | null) {
    setActiveId(id);
    activeIdRef.current = id;
  }

  /** Keep React state and the editor's module-level aiState in sync. */
  function applyAiStatus(s: AiStatus) {
    setAi(s);
    aiState.backend = s.backend;
    aiState.skills = new Set(s.skills);
  }

  async function toggleAi() {
    try {
      if (ai?.backend) {
        applyAiStatus(await invoke<AiStatus>("ai_set", { backend: false }));
        setStatus("AI off");
        return;
      }
      setStatus("looking for AI…");
      const probe = await invoke<AiStatus>("ai_status", { check: true });
      if (probe.available.length === 0) {
        setStatus("no AI CLI found (claude / codex / opencode / ollama)");
        return;
      }
      const s = await invoke<AiStatus>("ai_set", { backend: probe.available[0] });
      applyAiStatus(s);
      setStatus(`AI connected (${probe.version ?? probe.available[0]})`);
    } catch (e) {
      setStatus(`AI: ${String(e)}`);
    }
  }

  function newNote() {
    flush();
    setActive(null);
    setBuffer({ key: crypto.randomUUID(), initial: "" });
    setStatus("");
  }

  function openItem(item: Item) {
    if (item.id === activeIdRef.current) return;
    flush();
    setActive(item.id);
    if (item.type === "text") {
      setBuffer({ key: item.id + ":" + crypto.randomUUID(), initial: item.content });
    }
    setStatus("");
  }

  /** Add fully-formed non-text items (paste / drop) and select the last one. */
  async function addMedia(newItems: Item[]) {
    if (newItems.length === 0) return;
    flush();
    await persist([...itemsRef.current, ...newItems]);
    setActive(newItems[newItems.length - 1].id);
  }

  async function reload() {
    try {
      const json = await invoke<string>("load_items");
      setItems(JSON.parse(json));
    } catch (e) {
      console.error(e);
    }
  }

  useEffect(() => {
    void reload();
    // Restore the AI connection state (config read only — no AI process
    // is ever started here; connecting is always an explicit click).
    invoke<AiStatus>("ai_status", { check: false }).then(applyAiStatus).catch(() => {});
  }, []);

  // Load thumbnails for image items lazily.
  useEffect(() => {
    for (const i of items) {
      if (i.type !== "image" || thumbs[i.id] || thumbsLoading.current.has(i.id)) continue;
      thumbsLoading.current.add(i.id);
      invoke<string>("read_file_b64", { rel: i.content })
        .then((b64) =>
          setThumbs((t) => ({ ...t, [i.id]: `data:${mimeOf(i.content)};base64,${b64}` })),
        )
        .catch(console.error)
        .finally(() => thumbsLoading.current.delete(i.id));
    }
  }, [items, thumbs]);

  // Clipboard: pasting an image anywhere captures it into the vault.
  useEffect(() => {
    const onPaste = async (e: ClipboardEvent) => {
      const list = e.clipboardData?.items;
      if (!list) return;
      const img = Array.from(list).find((i) => i.type.startsWith("image/"));
      if (!img) return;
      e.preventDefault();
      const file = img.getAsFile();
      if (!file) return;
      const bytes = new Uint8Array(await file.arrayBuffer());
      const ext = (img.type.split("/")[1] || "png").replace("jpeg", "jpg");
      try {
        const rel = await invoke<string>("save_image", { b64: u8ToB64(bytes), ext });
        const stamp = new Date();
        await addMedia([
          {
            id: newId(),
            type: "image",
            content: rel,
            title: `image ${stamp.toLocaleDateString()} ${stamp.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`,
            tags: [],
            summary: fmtSize(bytes.length),
            createdAt: stamp.toISOString(),
            pinned: false,
            archived: false,
          },
        ]);
      } catch (err) {
        console.error(err);
      }
    };
    window.addEventListener("paste", onPaste);
    return () => window.removeEventListener("paste", onPaste);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Native drag & drop: copy dropped files into the vault.
  useEffect(() => {
    const un = getCurrentWebview().onDragDropEvent(async (event) => {
      const p = event.payload;
      if (p.type === "enter" || p.type === "over") setDragging(true);
      else if (p.type === "leave") setDragging(false);
      else if (p.type === "drop") {
        setDragging(false);
        const added: Item[] = [];
        for (const src of p.paths) {
          try {
            const info = await invoke<{ path: string; name: string; size: number }>(
              "import_file",
              { src },
            );
            added.push({
              id: newId(),
              type: IMG_RE.test(info.name) ? "image" : "file",
              content: info.path,
              title: info.name,
              tags: [],
              summary: fmtSize(info.size),
              createdAt: new Date().toISOString(),
              pinned: false,
              archived: false,
            });
          } catch (err) {
            console.error(src, err);
          }
        }
        await addMedia(added);
      }
    });
    return () => {
      void un.then((f) => f());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if ((e.target as HTMLElement | null)?.closest(".cm-panels")) return;
        flush();
        void appWindow.hide();
      } else if (e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === "n") {
        e.preventDefault();
        newNote();
      } else if (e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === "s") {
        e.preventDefault();
        flush();
      } else if (e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === "k") {
        e.preventDefault();
        searchRef.current?.focus();
        searchRef.current?.select();
      }
    };
    window.addEventListener("keydown", onKey);
    const unlisten = appWindow.onFocusChanged(({ payload: focused }) => {
      if (focused) {
        void reload();
        // pick up SKILLS.md / config.json edits made while we were hidden
        invoke<AiStatus>("ai_status", { check: false }).then(applyAiStatus).catch(() => {});
        editorRef.current?.focus();
      } else {
        flush();
      }
    });
    return () => {
      window.removeEventListener("keydown", onKey);
      void unlisten.then((f) => f());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function copyImage(item: Item) {
    let url = thumbs[item.id];
    if (!url) {
      const b64 = await invoke<string>("read_file_b64", { rel: item.content });
      url = `data:${mimeOf(item.content)};base64,${b64}`;
    }
    const blob = await (await fetch(url)).blob();
    await navigator.clipboard.write([new ClipboardItem({ [blob.type]: blob })]);
  }

  /** Copy the item to the clipboard and hide — find, grab, paste elsewhere. */
  async function grab(item: Item) {
    try {
      if (item.type === "text") {
        await navigator.clipboard.writeText(item.content);
      } else if (item.type === "image") {
        await copyImage(item);
      } else {
        const abs = await invoke<string>("resolve_vault_path", { rel: item.content });
        await navigator.clipboard.writeText(abs);
      }
      flush();
      void appWindow.hide();
    } catch (e) {
      console.error(e);
    }
  }

  function togglePin(item: Item) {
    void persist(
      itemsRef.current.map((i) => (i.id === item.id ? { ...i, pinned: !i.pinned } : i)),
    );
  }

  function toggleArchive(item: Item) {
    void persist(
      itemsRef.current.map((i) =>
        i.id === item.id ? { ...i, archived: !i.archived } : i,
      ),
    );
  }

  const visible = useMemo(() => {
    const terms = query.split(/\s+/).filter(Boolean);
    let list =
      filter === "arc" ? items.filter((i) => i.archived) : items.filter((i) => !i.archived);
    if (filter !== "all" && filter !== "arc") list = list.filter((i) => i.type === filter);
    if (terms.length) {
      return list
        .map((item) => ({ item, s: itemScore(item, terms) }))
        .filter((x) => x.s > 0)
        .sort((a, b) => b.s - a.s)
        .map((x) => x.item);
    }
    return [...list].sort(
      (a, b) =>
        Number(b.pinned) - Number(a.pinned) || b.createdAt.localeCompare(a.createdAt),
    );
  }, [items, query, filter]);

  // Keep the keyboard selection valid and visible.
  useEffect(() => {
    setSel(0);
  }, [query, filter]);
  useEffect(() => {
    if (sel >= visible.length) setSel(Math.max(visible.length - 1, 0));
    listRef.current
      ?.querySelector(`[data-idx="${sel}"]`)
      ?.scrollIntoView({ block: "nearest" });
  }, [sel, visible]);

  function onSearchKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSel((s) => Math.min(s + 1, visible.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSel((s) => Math.max(s - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const it = visible[sel];
      if (!it) return;
      if (e.ctrlKey) void grab(it);
      else openItem(it);
    } else if (e.key === "Escape" && query) {
      // First Esc clears the search; a second one (global handler) hides.
      e.stopPropagation();
      setQuery("");
    }
  }

  const activeItem = items.find((i) => i.id === activeId);
  const showPreview = activeItem && activeItem.type !== "text";

  return (
    <div className="shell">
      {dragging && <div className="dropzone">drop to save</div>}
      <header
        className="titlebar"
        onMouseDown={(e) => {
          // Drag the window from anywhere on the bar except its buttons,
          // like a normal titlebar. Explicit startDragging is more reliable
          // than the data-tauri-drag-region attribute.
          if (e.button === 0 && !(e.target as HTMLElement).closest("button")) {
            void appWindow.startDragging();
          }
        }}
      >
        <span className="brand">mindpalace</span>
        <span className="status">{status}</span>
        <div className="winbtns">
          <button
            className={"aibtn" + (ai?.backend ? " on" : "")}
            onClick={() => void toggleAi()}
            title={
              ai?.backend
                ? `AI connected: ${ai.backend} — click to disconnect`
                : "Connect AI — off by default; nothing is ever sent while off"
            }
          >
            <svg width="13" height="13" viewBox="0 0 24 24" aria-hidden="true">
              <path
                d="M12 2l2.3 6.9L21 11.2l-6.7 2.3L12 20.4l-2.3-6.9L3 11.2l6.7-2.3z"
                fill="currentColor"
              />
            </svg>
          </button>
          <button
            onClick={() => {
              flush();
              void appWindow.close();
            }}
            title="Hide to tray"
          >
            ✕
          </button>
        </div>
      </header>

      <div className="main">
        <aside className="sidebar">
          <div className="toolbar">
            <input
              ref={searchRef}
              className="search"
              placeholder="search…  (Ctrl+K)"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={onSearchKey}
              spellCheck={false}
            />
            <button className="new" onClick={newNote} title="New note (Ctrl+N)">
              new
            </button>
          </div>
          <div className="filters">
            {(["all", "text", "image", "file", "arc"] as Filter[]).map((f) => (
              <button
                key={f}
                className={filter === f ? "on" : ""}
                onClick={() => setFilter(f)}
              >
                {f}
              </button>
            ))}
          </div>
          <div className="list" ref={listRef}>
            {visible.length === 0 && (
              <div className="empty">{query ? "no matches" : "empty"}</div>
            )}
            {visible.map((item, idx) => (
              <div
                key={item.id}
                data-idx={idx}
                className={
                  "item" +
                  (item.id === activeId ? " active" : "") +
                  (query && idx === sel ? " sel" : "")
                }
                onClick={() => openItem(item)}
              >
                <div className="row">
                  {item.type === "image" && thumbs[item.id] && (
                    <img className="thumb" src={thumbs[item.id]} alt="" />
                  )}
                  {item.type === "file" && (
                    <span className="ext">
                      {(item.title.split(".").pop() ?? "file").slice(0, 4)}
                    </span>
                  )}
                  <span className="title">
                    {item.pinned && <span className="pin">●</span>}
                    {item.title || "(untitled)"}
                  </span>
                  <span className="time">{relTime(item.createdAt)}</span>
                  <span className="rowactions">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        togglePin(item);
                      }}
                    >
                      {item.pinned ? "unpin" : "pin"}
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleArchive(item);
                      }}
                    >
                      {item.archived ? "restore" : "arc"}
                    </button>
                  </span>
                </div>
                {item.tags.length > 0 && (
                  <div className="tags">
                    {item.tags.slice(0, 3).map((t) => (
                      <span key={t}>#{t}</span>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </aside>

        <section className="pad">
          {showPreview ? (
            <div className="preview">
              {activeItem.type === "image" &&
                (thumbs[activeItem.id] ? (
                  <img className="full" src={thumbs[activeItem.id]} alt={activeItem.title} />
                ) : (
                  <div className="empty">loading…</div>
                ))}
              {activeItem.type === "file" && (
                <div className="filecard">
                  <div className="fname">{activeItem.title}</div>
                  <div className="fmeta">{activeItem.summary}</div>
                </div>
              )}
              <div className="actions">
                <button onClick={() => void invoke("open_vault_path", { rel: activeItem.content })}>
                  open
                </button>
                <button onClick={() => void invoke("reveal_vault_path", { rel: activeItem.content })}>
                  reveal
                </button>
                {activeItem.type === "image" && (
                  <button onClick={() => void copyImage(activeItem)}>copy</button>
                )}
              </div>
            </div>
          ) : (
            <Editor
              ref={editorRef}
              docId={buffer.key}
              initial={buffer.initial}
              onChange={queueSave}
            />
          )}
        </section>
      </div>
    </div>
  );
}
