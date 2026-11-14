import { addItem, loadItems, updateItem } from "./store.js";
import { ask, enrichItem, organize } from "./agent.js";

// Test CLI for the MindPalace agent. The Tauri app will call the same
// functions (enrichItem / ask / organize) instead of this file.
//
//   npm run palace -- add "some note text"
//   npm run palace -- list
//   npm run palace -- ask "what did I note about fax validation?"
//   npm run palace -- organize

const [command, ...rest] = process.argv.slice(2);
const arg = rest.join(" ").trim();

async function main(): Promise<void> {
  switch (command) {
    case "add": {
      if (!arg) throw new Error('Usage: palace add "text to save"');
      const item = addItem("text", arg);
      console.log(`Saved ${item.id}. Enriching…`);
      try {
        const enrichment = await enrichItem(item);
        updateItem(item.id, enrichment);
        console.log(`[${item.id}] ${enrichment.title}  #${enrichment.tags.join(" #")}`);
      } catch (err) {
        // The capture is already safe on disk — AI enrichment is best-effort.
        console.log(`Saved without AI metadata (${err instanceof Error ? err.message : err})`);
      }
      break;
    }
    case "list": {
      for (const i of loadItems().filter((i) => !i.archived)) {
        console.log(
          `[${i.id}] ${i.title}  ${i.tags.length ? "#" + i.tags.join(" #") : ""}`,
        );
        if (i.summary) console.log(`         ${i.summary}`);
      }
      break;
    }
    case "ask": {
      if (!arg) throw new Error('Usage: palace ask "your question"');
      console.log(await ask(arg));
      break;
    }
    case "organize": {
      console.log(await organize());
      break;
    }
    default:
      console.log("Commands: add <text> | list | ask <question> | organize");
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
