// Toolbar click -> run inject.js in the active tab. See docs/architecture.md.

browser.action.onClicked.addListener(async (tab: WebExtension.Tab): Promise<void> => {
  const tabId = tab.id;
  if (tabId === undefined) return;

  try {
    const [frame] = await browser.scripting.executeScript({
      target: { tabId },
      files: ["inject.js"],
    });
    console.log("[sharepoint-video-dl]", frame?.result ?? "no result");
  } catch (error) {
    // Nearly always the extension not being allowed on this host yet.
    console.error("[sharepoint-video-dl] could not inject:", error);
  }
});
