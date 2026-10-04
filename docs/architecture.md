# How it works

SharePoint will stream a course video at you and offer no way to keep a copy. But
every SharePoint web also publishes `download.aspx`, which takes a file path and
answers with the bytes and a `Content-Disposition: attachment`. The player page
already carries the path it is playing, in its own query string. So the whole
extension is moving the path out of one URL and into the other.

The page, as Safari shows it:

```
https://unsw-my.sharepoint.com/personal/z3522766_ad_unsw_edu_au/_layouts/15/stream.aspx
  ?id=%2Fpersonal%2Fz3522766%5Fad%5Funsw%5Fedu%5Fau%2FDocuments%2FECON2112%20Videos%2FLecture%20Video%20%2D%20September%2023%2Emov
  &nav=...&ga=1&referrer=StreamWebApp.Web
```

and what it is turned into:

```
https://unsw-my.sharepoint.com/personal/z3522766_ad_unsw_edu_au/_layouts/15/download.aspx
  ?SourceUrl=https%3A%2F%2Funsw-my.sharepoint.com%2Fpersonal%2Fz3522766_ad_unsw_edu_au%2FDocuments%2FECON2112%20Videos%2FLecture%20Video%20-%20September%2023.mov
```

Nothing is scraped and nothing is bypassed. The request goes to the same site with
the same cookies, and SharePoint applies the permissions it always applies: a file
you cannot watch is a file this cannot download. The player's own tracking
parameters (`nav`, `ga`, `referrer`, `referrerScenario`) are dropped rather than
carried over, because `download.aspx` has no use for them.

## Which web's download.aspx

`download.aspx` has to be asked of the web that holds the file, so the path has to
be cut back from the file to the site. There are two ways to work that out and only
one of them is reliable.

**Reading the file path** is the tempting one, and the obvious cut -- split on
`/Documents/` -- is wrong for most document libraries. SharePoint's default library
is called **Shared Documents**, where the character before `Documents` is a space,
so nothing splits, the site path comes out as the entire file path, and the
resulting URL is nonsense. It happens to work on OneDrive for Business, whose
library really is called `Documents`, which is how the mistake survives testing.

**Reading the page path** is what `inject.ts` actually does. The page is already
being served out of the right web's `_layouts` folder:

```
/personal/z3522766_ad_unsw_edu_au/_layouts/15/stream.aspx
└────────── the web ────────────┘
```

So everything before `/_layouts/` is the answer, whatever the library is called,
and it stays correct for subsites (`/sites/Faculty/ECON`) and for the root site
collection (where the answer is the empty string) without either being a special
case. Pattern-matching `/sites/`, `/teams/` or `/personal/` off the file path
remains as a fallback for pages not served from `_layouts`.

## Encoding

`filePath` must be fully decoded before it goes into `SourceUrl`, because
`searchParams.set` encodes it once on the way out. The two sources of a path
disagree about this and the disagreement is easy to miss:

- `searchParams.get("id")` **decodes**, so `%20` arrives as a space.
- `new URL(id).pathname` **does not**, so `%20` arrives as `%20`.

Left alone, the second path would be encoded twice and go out as `%2520`, which
SharePoint reads as a literal `%20` in a file name and cannot find. So the absolute
form is decoded explicitly.

For the same reason the display name is the last path segment **as-is**, not
`decodeURIComponent` of it. The path is already decoded; decoding a second time
throws `URIError` on any file with a `%` in its name -- `100% exam.mp4` -- and
because that throw happens before the navigation, it would take the download with
it. `scripts/test.mjs` covers both of these.

## The extension around it

Three files, no framework and no bundler, because there is nothing here that needs
one.

| File | Job |
| --- | --- |
| `manifest.json` | MV3. `activeTab` + `scripting`, `host_permissions` on `*://*.sharepoint.com/*` |
| `background.ts` | Toolbar click, or Cmd+Shift+Y, runs `inject.js` in the active tab |
| `inject.ts` | Everything above, plus a toast saying what happened |

The click is what grants `activeTab`. `host_permissions` is there so the site can
be allowed once rather than re-prompting on every course page.

`executeScript` failures are invisible and the player page swallows a thrown error,
so `inject.ts` reports on the page itself: green naming the file as the download
starts, red saying what was wrong. Its return value reaches `background.ts` and the
extension's console, which is for debugging rather than for the user.

## Limits

- One video per page. It reads the page you are on, not a folder listing.
- Pages identifying a file by `sourcedoc={GUID}` instead of `?id=` are not handled.
  The toast says so rather than failing silently.
