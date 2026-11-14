import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

// Minimal JSON-file store standing in for the future SQLite database of the
// Tauri app. Same shape as the planned `items` table, so swapping the backend
// later only touches this file.

export type ItemType = "text" | "image" | "file";

export interface Item {
  id: string;
  type: ItemType;
  /** Text body for text items; path into the vault for image/file items. */
  content: string;
  title: string;
  tags: string[];
  summary: string;
  createdAt: string;
  pinned: boolean;
  archived: boolean;
}

const DATA_FILE =
  process.env.MINDPALACE_DATA ??
  path.resolve(process.cwd(), "data", "palace.json");

export function loadItems(): Item[] {
  if (!fs.existsSync(DATA_FILE)) return [];
  return JSON.parse(fs.readFileSync(DATA_FILE, "utf8")) as Item[];
}

export function saveItems(items: Item[]): void {
  fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
  fs.writeFileSync(DATA_FILE, JSON.stringify(items, null, 2), "utf8");
}

export function addItem(type: ItemType, content: string): Item {
  const items = loadItems();
  const item: Item = {
    id: crypto.randomUUID().slice(0, 8),
    type,
    content,
    title: content.split("\n")[0].slice(0, 60) || "(untitled)",
    tags: [],
    summary: "",
    createdAt: new Date().toISOString(),
    pinned: false,
    archived: false,
  };
  items.push(item);
  saveItems(items);
  return item;
}

export function getItem(id: string): Item | undefined {
  return loadItems().find((i) => i.id === id);
}

export function updateItem(
  id: string,
  patch: Partial<Pick<Item, "title" | "tags" | "summary" | "archived" | "pinned">>,
): Item | undefined {
  const items = loadItems();
  const item = items.find((i) => i.id === id);
  if (!item) return undefined;
  Object.assign(item, patch);
  saveItems(items);
  return item;
}

/** Simple keyword scoring over title/tags/summary/content — the local half of
 *  "lazy search". The agent calls this through its search tool; the future UI
 *  calls it directly on every keystroke. */
export function searchItems(query: string, limit = 10): Item[] {
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  const scored = loadItems()
    .filter((i) => !i.archived)
    .map((item) => {
      const haystacks: Array<[string, number]> = [
        [item.title.toLowerCase(), 5],
        [item.tags.join(" ").toLowerCase(), 4],
        [item.summary.toLowerCase(), 3],
        [item.content.toLowerCase(), 1],
      ];
      let score = 0;
      for (const term of terms) {
        for (const [text, weight] of haystacks) {
          if (text.includes(term)) score += weight;
        }
      }
      return { item, score };
    })
    .filter((s) => s.score > 0)
    .sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((s) => s.item);
}
