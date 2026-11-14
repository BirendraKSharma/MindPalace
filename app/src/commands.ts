// Inline editor commands: a line ending in `--calc`, `--search`, or (while
// AI is connected) any `--skill` from SKILLS.md is acted on when Enter is
// pressed (see the Enter keymap in Editor.tsx).

/** Matches "anything --cmd" at the end of a line. */
export const COMMAND_RE = /^(.*?)\s*--([a-z][a-z0-9-]*)\s*$/;

/**
 * AI connection state, set by the titlebar button in App.tsx and read by the
 * editor's Enter handler. While `backend` is null, no `--skill` line is ever
 * intercepted and nothing is ever sent anywhere — the privacy default.
 */
export const aiState = {
  backend: null as string | null,
  skills: new Set<string>(),
};

/**
 * Safe arithmetic evaluator — no eval(). Supports + - * / % ^ and
 * parentheses, unary minus, decimals, thousands separators (1,234),
 * and the unicode operators × ÷ −. Returns null if the input is not
 * a pure arithmetic expression or the result is not finite.
 */
export function evalExpr(src: string): number | null {
  const s = src
    .replace(/[×xｘX]/g, "*")
    .replace(/÷/g, "/")
    .replace(/−/g, "-")
    .replace(/(\d),(?=\d{3}\b)/g, "$1") // 1,234,567 → 1234567
    .replace(/\s+/g, "");
  if (!s || /[^0-9+\-*/%^().]/.test(s)) return null;

  let pos = 0;
  const peek = () => s[pos];
  const eat = (c: string) => (s[pos] === c ? (pos++, true) : false);

  function primary(): number {
    if (eat("(")) {
      const v = expr();
      if (!eat(")")) throw new Error("paren");
      return v;
    }
    const m = /^\d*\.?\d+/.exec(s.slice(pos));
    if (!m) throw new Error("number");
    pos += m[0].length;
    return parseFloat(m[0]);
  }
  function unary(): number {
    if (eat("-")) return -unary();
    if (eat("+")) return unary();
    return power();
  }
  function power(): number {
    const base = primary();
    if (eat("^")) return Math.pow(base, unary()); // right-associative
    return base;
  }
  function term(): number {
    let v = unary();
    for (;;) {
      if (eat("*")) v *= unary();
      else if (eat("/")) v /= unary();
      else if (eat("%")) v %= unary();
      else return v;
    }
  }
  function expr(): number {
    let v = term();
    for (;;) {
      if (eat("+")) v += term();
      else if (peek() === "-" && eat("-")) v -= term();
      else return v;
    }
  }

  try {
    const v = expr();
    if (pos !== s.length || !isFinite(v)) return null;
    return v;
  } catch {
    return null;
  }
}

/** 1288, 12.345 — trimmed of float noise (23.1*3 → 69.3, not 69.30000000000001). */
export function formatResult(v: number): string {
  return Number(v.toPrecision(12)).toString();
}
