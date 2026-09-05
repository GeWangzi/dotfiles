// Reads the running totals written by the content script and keeps the popup
// in sync while it is open.

const api = globalThis.browser ?? globalThis.chrome;
const STATS_KEY = "stats";

const countElement = document.getElementById("count");
const savedElement = document.getElementById("saved");
const resetButton = document.getElementById("reset");

function formatDuration(totalSeconds) {
  const seconds = Math.max(0, Math.round(totalSeconds));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
  return `${seconds}s`;
}

function render(stats) {
  const value = stats || {};
  countElement.textContent = (value.adsSkipped || 0).toLocaleString();
  savedElement.textContent = formatDuration(value.secondsSaved || 0);
}

async function refresh() {
  const stored = await api.storage.local.get(STATS_KEY);
  render(stored[STATS_KEY]);
}

// The content script writes every few seconds, so an open popup ticks up live.
api.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes[STATS_KEY]) {
    render(changes[STATS_KEY].newValue);
  }
});

resetButton.addEventListener("click", async () => {
  const empty = { adsSkipped: 0, secondsSaved: 0 };
  await api.storage.local.set({ [STATS_KEY]: empty });
  render(empty);
});

refresh();
