import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
} from "react";
import { EditorState, Compartment } from "@codemirror/state";
import {
  EditorView,
  keymap,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
} from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { markdown } from "@codemirror/lang-markdown";
import { syntaxHighlighting, HighlightStyle } from "@codemirror/language";
import { tags } from "@lezer/highlight";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { COMMAND_RE, aiState, evalExpr, formatResult } from "./commands";

// Inline commands: Enter on a line ending in `--calc` or `--search` acts on
// the line instead of inserting a newline (see commands.ts, SHORTCUTS.md).
function runInlineCommand(view: EditorView): boolean {
  const { head, empty } = view.state.selection.main;
  if (!empty) return false;
  const line = view.state.doc.lineAt(head);
  const m = COMMAND_RE.exec(line.text);
  if (!m) return false;
  const [, text, cmd] = m;

  if (cmd === "calc") {
    const v = evalExpr(text);
    if (v === null) return false; // not arithmetic — insert the newline as usual
    const out = `${text.trim()} = ${formatResult(v)}`;
    view.dispatch({
      changes: { from: line.from, to: line.to, insert: out },
      selection: { anchor: line.from + out.length },
    });
    return true;
  }

  if (cmd === "search") {
    const q = text.trim();
    if (!q) return false;
    // Keep the query in the note, drop the command suffix, open the browser.
    view.dispatch({
      changes: { from: line.from, to: line.to, insert: q },
      selection: { anchor: line.from + q.length },
    });
    invoke("web_search", { query: q })
      .then(() => {
        // The window is always-on-top: without hiding it, the browser tab
        // opens invisibly behind the pad and the search looks like a no-op.
        void getCurrentWindow().hide();
      })
      .catch((err) => {
        view.dispatch({
          changes: {
            from: view.state.selection.main.head,
            insert: ` (search failed: ${String(err)})`,
          },
        });
      });
    return true;
  }

  // Any other --word is an AI skill from SKILLS.md — only while connected.
  // Disconnected, the line is plain text and Enter is untouched (privacy).
  if (aiState.backend && aiState.skills.has(cmd)) {
    const input = text.trim();
    if (!input) return false;
    const marker = `⟳ ${cmd}…`;
    view.dispatch({
      changes: { from: line.from, to: line.to, insert: `${input}\n${marker}` },
      selection: { anchor: line.from + input.length },
    });
    const finish = (replacement: string) => {
      try {
        const doc = view.state.doc.toString();
        const idx = doc.indexOf(marker);
        if (idx >= 0) {
          view.dispatch({
            changes: { from: idx, to: idx + marker.length, insert: replacement },
          });
        } else {
          view.dispatch({
            changes: { from: view.state.doc.length, insert: `\n${replacement}` },
          });
        }
      } catch {
        // the buffer was switched or the view destroyed — nothing to update
      }
    };
    invoke<string>("ai_run", { task: cmd, text: input })
      .then((out) => finish(out.trim() || "(empty AI reply)"))
      .catch((err) => finish(`(${cmd} failed: ${String(err)})`));
    return true;
  }

  return false;
}

export interface EditorHandle {
  focus: () => void;
}

interface Props {
  /** Buffer identity — the editor remounts only when this changes. */
  docId: string;
  initial: string;
  onChange: (content: string) => void;
}

// Markdown rendered as styled text, Medium-style: structure is visible,
// but there is no toolbar and the source stays plain text.
const mdHighlight = HighlightStyle.define([
  { tag: tags.heading1, fontSize: "1.55em", fontWeight: "700", lineHeight: "1.3" },
  { tag: tags.heading2, fontSize: "1.3em", fontWeight: "700", lineHeight: "1.3" },
  { tag: tags.heading3, fontSize: "1.12em", fontWeight: "600" },
  { tag: tags.strong, fontWeight: "700" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  {
    tag: tags.monospace,
    fontFamily: "Consolas, 'Yu Gothic UI', monospace",
    fontSize: "0.92em",
    background: "var(--code-bg)",
    borderRadius: "3px",
  },
  { tag: tags.link, color: "var(--accent)", textDecoration: "underline" },
  { tag: tags.url, color: "var(--accent-dim)" },
  { tag: tags.quote, color: "var(--fg-dim)", fontStyle: "italic" },
  // The markup characters themselves (#, *, >, -) stay dim.
  { tag: tags.processingInstruction, color: "var(--fg-faint)" },
  { tag: tags.meta, color: "var(--fg-faint)" },
]);

// All colors come from the CSS variables in App.css, so the editor follows
// the OS light/dark theme with no reconfiguration — only the `dark` flag
// below is swapped (it controls CodeMirror's built-in fallback styles).
const theme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "15.5px",
    backgroundColor: "transparent",
    color: "var(--fg)",
  },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": {
    fontFamily: "'Segoe UI', 'Yu Gothic UI', system-ui, sans-serif",
    lineHeight: "1.75",
    overflow: "auto",
  },
  ".cm-content": {
    padding: "26px 36px 50vh",
    maxWidth: "760px",
    margin: "0 auto",
    caretColor: "var(--caret)",
  },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--caret)" },
  "&.cm-focused > .cm-scroller .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground":
    { background: "var(--selection)" },
  ".cm-selectionMatch": { background: "var(--fill-hover)" },
  ".cm-searchMatch": {
    background: "var(--selection)",
    outline: "1px solid var(--line-strong)",
  },
  ".cm-searchMatch.cm-searchMatch-selected": {
    background: "var(--selection)",
    outlineWidth: "2px",
  },
  // The Ctrl+F panel, kept as quiet as possible.
  ".cm-panels": {
    background: "var(--panel-bg)",
    color: "var(--fg)",
    borderTop: "1px solid var(--line)",
  },
  ".cm-panel input, .cm-panel button, .cm-panel label": {
    background: "var(--fill)",
    color: "var(--fg)",
    border: "1px solid var(--line-strong)",
    borderRadius: "4px",
    fontSize: "12px",
  },
});

// CodeMirror wants to know light vs dark for its built-in defaults; swap the
// flag live when the OS theme changes.
const darkFlag = new Compartment();
const lightQuery = window.matchMedia("(prefers-color-scheme: light)");
const flagTheme = (light: boolean) => EditorView.theme({}, { dark: !light });

const Editor = forwardRef<EditorHandle, Props>(function Editor(
  { docId, initial, onChange },
  ref,
) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  useImperativeHandle(ref, () => ({
    focus: () => view.current?.focus(),
  }));

  useEffect(() => {
    const v = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: initial,
        extensions: [
          EditorState.allowMultipleSelections.of(true),
          // VS Code-style multi-cursor: Alt+Click adds a cursor,
          // Alt+drag makes a rectangular (column) selection.
          EditorView.clickAddsSelectionRange.of((e) => e.altKey),
          rectangularSelection(),
          crosshairCursor(),
          drawSelection(),
          dropCursor(),
          highlightSelectionMatches(),
          history(),
          EditorView.lineWrapping,
          markdown(),
          syntaxHighlighting(mdHighlight),
          // VS Code-style pairing: (, [, {, quotes and backtick auto-close,
          // wrap a selection, skip over their closing char, and Backspace
          // deletes the empty pair. Fully offline.
          closeBrackets(),
          EditorState.languageData.of(() => [
            { closeBrackets: { brackets: ["(", "[", "{", "'", '"', "`"] } },
          ]),
          keymap.of([
            { key: "Enter", run: runInlineCommand }, // inline --commands, before the normal Enter
            ...closeBracketsKeymap, // Backspace removes an empty pair
            ...defaultKeymap, // includes Ctrl+Shift+K delete line, Alt+↑/↓ move line, Shift+Alt+↑/↓ copy line
            ...historyKeymap,
            ...searchKeymap, // includes Ctrl+D select next occurrence, Ctrl+F find
            indentWithTab,
          ]),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onChangeRef.current(u.state.doc.toString());
          }),
          theme,
          darkFlag.of(flagTheme(lightQuery.matches)),
        ],
      }),
    });
    view.current = v;
    v.focus();
    const onScheme = (e: MediaQueryListEvent) =>
      v.dispatch({ effects: darkFlag.reconfigure(flagTheme(e.matches)) });
    lightQuery.addEventListener("change", onScheme);
    return () => {
      lightQuery.removeEventListener("change", onScheme);
      v.destroy();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [docId]);

  return <div className="editor" ref={host} />;
});

export default Editor;
