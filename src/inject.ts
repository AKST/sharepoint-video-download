// Reads the file out of the page's ?id= and sends the browser to that site's
// download.aspx. See docs/architecture.md for how the URL is derived.

type Outcome =
  | { readonly ok: true; readonly name: string; readonly href: string }
  | { readonly ok: false; readonly reason: string };

(((): Outcome => {
  const TOAST_ID = "sharepoint-video-dl-toast";
  const LAYOUTS = "/_layouts/";

  /** The web that owns the file, preferring the page's own path over the file's. */
  function webRoot(pagePath: string, filePath: string): string {
    const layouts = pagePath.toLowerCase().indexOf(LAYOUTS);
    if (layouts !== -1) return pagePath.slice(0, layouts);
    const match = /^\/(?:sites|teams|personal)\/[^/]+/i.exec(filePath);
    return match?.[0] ?? "";
  }

  function toast(message: string, ok: boolean): void {
    document.getElementById(TOAST_ID)?.remove();
    const element = document.createElement("div");
    element.id = TOAST_ID;
    element.textContent = message;
    element.style.cssText = [
      "position:fixed", "top:16px", "right:16px", "z-index:2147483647",
      "max-width:min(420px,calc(100vw - 32px))",
      "padding:12px 16px", "border-radius:10px",
      "font:500 13px/1.45 -apple-system,BlinkMacSystemFont,system-ui,sans-serif",
      "color:#fff", "box-shadow:0 6px 24px rgba(0,0,0,.28)",
      "word-break:break-word", "pointer-events:none",
      `background:${ok ? "#1d6f42" : "#a3242b"}`,
    ].join(";");
    document.documentElement.append(element);
    setTimeout((): void => element.remove(), 6000);
  }

  try {
    const page = new URL(location.href);
    const id = page.searchParams.get("id");
    if (id === null || id === "") {
      toast("No ?id= on this page. Open the video itself, not the folder listing.", false);
      return { ok: false, reason: "no-id" };
    }

    // Usually a server relative path, but some views hand over a whole URL.
    // searchParams already decoded the first kind, and pathname does not decode
    // the second, so decode it too: SourceUrl is encoded once on the way out and
    // a path still holding %20 would go out as %2520.
    const absolute = /^https?:\/\//i.test(id);
    const origin = absolute ? new URL(id).origin : page.origin;
    const filePath = absolute ? decodeURIComponent(new URL(id).pathname) : id;

    const download = new URL(`${origin}${webRoot(page.pathname, filePath)}${LAYOUTS}15/download.aspx`);
    download.searchParams.set("SourceUrl", `${origin}${filePath}`);

    const name = filePath.split("/").pop() || "the file";
    console.log("[sharepoint-video-dl] downloading", name, download.href);
    toast(`Downloading ${name}`, true);

    // download.aspx answers with an attachment, so the page stays put.
    location.assign(download.href);
    return { ok: true, name, href: download.href };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    toast(`Could not work out a download URL: ${message}`, false);
    return { ok: false, reason: message };
  }
})());
