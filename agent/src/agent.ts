import Anthropic from "@anthropic-ai/sdk";
import { betaZodTool } from "@anthropic-ai/sdk/helpers/beta/zod";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import {
  getItem,
  loadItems,
  searchItems,
  updateItem,
  type Item,
} from "./store.js";

const client = new Anthropic();

const MODEL = process.env.MINDPALACE_MODEL ?? "claude-opus-5-5";

// ---------------------------------------------------------------------------
// Enrich: give a freshly captured item a title, tags, and a one-line summary.
// Runs once per capture, async, never blocks the UI.
// ---------------------------------------------------------------------------

const EnrichmentSchema = z.object({
  title: z.string().describe("Short descriptive title, max 60 chars, in the item's own language"),
  tags: z.array(z.string()).describe("2-5 lowercase topic tags"),
  summary: z.string().describe("One sentence: what this item is and why it was likely saved"),
});

export type Enrichment = z.infer<typeof EnrichmentSchema>;

export async function enrichItem(item: Item): Promise<Enrichment> {
  const response = await client.messages.parse({
    model: MODEL,
    max_tokens: 2000,
    output_config: { effort: "low", format: zodOutputFormat(EnrichmentSchema) },
    system:
      "You enrich items in MindPalace, a personal scratchpad. Items are work notes " +
      "(often software development, Japanese and English mixed), snippets, file references. " +
      "Produce metadata that makes the item findable later. Keep the item's language for the title.",
    messages: [
      {
        role: "user",
        content: `Item type: ${item.type}\nContent:\n${item.content.slice(0, 8000)}`,
      },
    ],
  });
  if (response.stop_reason === "refusal" || !response.parsed_output) {
    // Fall back to the mechanical defaults already on the item.
    return { title: item.title, tags: item.tags, summary: item.summary };
  }
  return response.parsed_output;
}

// ---------------------------------------------------------------------------
// Agent tools: the palace exposed to Claude. Read + metadata-only writes.
// No delete tool on purpose — the agent can never destroy a capture.
// ---------------------------------------------------------------------------

function itemBrief(i: Item): object {
  return {
    id: i.id,
    type: i.type,
    title: i.title,
    tags: i.tags,
    summary: i.summary,
    createdAt: i.createdAt,
    snippet: i.content.slice(0, 200),
  };
}

const searchTool = betaZodTool({
  name: "search_items",
  description:
    "Keyword-search the palace. Returns the best-matching items (id, title, tags, summary, snippet). " +
    "Search in the language the content was likely written in; try both Japanese and English terms if unsure.",
  inputSchema: z.object({
    query: z.string().describe("Keywords to search for"),
  }),
  run: async (input) => JSON.stringify(searchItems(input.query).map(itemBrief)),
});

const listTool = betaZodTool({
  name: "list_items",
  description: "List every non-archived item in the palace (id, title, tags, summary, snippet), newest first.",
  inputSchema: z.object({}),
  run: async () =>
    JSON.stringify(
      loadItems()
        .filter((i) => !i.archived)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .map(itemBrief),
    ),
});

const readTool = betaZodTool({
  name: "read_item",
  description: "Read one item's full content by id.",
  inputSchema: z.object({ id: z.string() }),
  run: async (input) => {
    const item = getItem(input.id);
    return item ? JSON.stringify(item) : `No item with id ${input.id}`;
  },
});

const updateTool = betaZodTool({
  name: "update_item",
  description:
    "Update an item's metadata: title, tags, and/or summary. Content is immutable through this tool.",
  inputSchema: z.object({
    id: z.string(),
    title: z.string().optional(),
    tags: z.array(z.string()).optional(),
    summary: z.string().optional(),
  }),
  run: async (input) => {
    const { id, ...patch } = input;
    const item = updateItem(id, patch);
    return item ? `Updated ${id}` : `No item with id ${id}`;
  },
});

// ---------------------------------------------------------------------------
// Agent entry points
// ---------------------------------------------------------------------------

const SYSTEM = `You are the librarian of MindPalace, the user's personal scratchpad.
Items are quick captures: work notes (software development at a Japanese company,
Japanese and English mixed), snippets, screenshots, file references. Be concise.
When you cite an item, cite it as [id] so the user can open it.`;

async function runAgent(task: string): Promise<string> {
  const finalMessage = await client.beta.messages.toolRunner({
    model: MODEL,
    max_tokens: 16000,
    output_config: { effort: "medium" },
    system: [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }],
    tools: [searchTool, listTool, readTool, updateTool],
    messages: [{ role: "user", content: task }],
    max_iterations: 20,
  });
  if (finalMessage.stop_reason === "refusal") {
    return "(The model declined this request.)";
  }
  return finalMessage.content
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("\n");
}

/** Answer a question from the palace, citing item ids. */
export function ask(question: string): Promise<string> {
  return runAgent(
    `Answer this question using the palace. Search first; read items you need in full. ` +
      `Cite item ids. If nothing relevant exists, say so.\n\nQuestion: ${question}`,
  );
}

/** Tidy the palace: fill in missing metadata, normalize tags, flag duplicates. */
export function organize(): Promise<string> {
  return runAgent(
    `Tidy the palace. Steps:
1. List all items.
2. For items with missing/poor titles, empty tags, or empty summaries: read them and update their metadata.
3. Normalize tags across items (same concept = same tag, lowercase).
4. Do NOT archive or change any content. For likely duplicates, only report them.
Finish with a short report: what you updated, suspected duplicates [id]/[id], and any suggestions.`,
  );
}
