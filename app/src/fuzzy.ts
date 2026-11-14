// fzf-style matching: a term matches if its characters appear in order.
// Exact substrings score far above scattered subsequences, word-boundary and
// consecutive-run hits score above lucky spread-out ones. Works per character,
// so Japanese text matches the same way as English.

const BOUNDARY = /[\s\-_/#.·、。（(]/;

/** Score one term against one string. 0 = no match. */
export function fuzzyMatch(term: string, hay: string): number {
  if (!term || !hay) return 0;
  const n = term.toLowerCase();
  const h = hay.toLowerCase();

  const idx = h.indexOf(n);
  if (idx >= 0) {
    let s = 100 - Math.min(idx, 30);
    if (idx === 0 || BOUNDARY.test(h[idx - 1])) s += 15;
    return s;
  }

  let score = 0;
  let pos = 0;
  let streak = 0;
  for (let k = 0; k < n.length; k++) {
    const found = h.indexOf(n[k], pos);
    if (found < 0) return 0;
    if (found === pos && k > 0) {
      streak++;
      score += 5 + streak;
    } else {
      streak = 0;
      score += 1;
      if (found === 0 || BOUNDARY.test(h[found - 1])) score += 8;
      score -= Math.min(found - pos, 10) * 0.5;
    }
    pos = found + 1;
  }
  return Math.max(score, 1);
}

export interface Searchable {
  title: string;
  tags: string[];
  summary: string;
  content: string;
}

/** Every term must match some field; fields weigh title > tags > summary > content. */
export function itemScore(item: Searchable, terms: string[]): number {
  const fields: Array<[string, number]> = [
    [item.title, 3],
    [item.tags.join(" "), 2.5],
    [item.summary, 2],
    [item.content, 1],
  ];
  let total = 0;
  for (const t of terms) {
    let best = 0;
    for (const [f, w] of fields) {
      const s = fuzzyMatch(t, f) * w;
      if (s > best) best = s;
    }
    if (best === 0) return 0;
    total += best;
  }
  return total;
}
