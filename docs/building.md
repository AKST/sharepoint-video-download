# Building and installing

```sh
npm install              # once, for the TypeScript compiler
scripts/install.sh       # build, convert, sign, verify, install
```

Then in Safari: Settings > Extensions, tick **SharePoint Video Downloader**. Click
the toolbar button once on a `sharepoint.com` page and allow it on the site.

## The pipeline

```
src/*.ts  --tsc-->  out/extension/*.js
src/manifest.json, src/icons/  --copy-->  out/extension/
out/extension/  --safari-web-extension-converter-->  out/safari/SharePointVideoDL.xcodeproj
                --xcodebuild + codesign-->  SharePointVideoDL.app
                --cp -R-->  ~/Applications/
```

`out/` is generated and gitignored. Everything in it is reproducible from `src/`.

| Command | Does |
| --- | --- |
| `npm run build` | Compile and stage `out/extension` |
| `npm run typecheck` | `tsc --noEmit` |
| `node --test scripts/test.mjs` | Run the compiled `inject.js` against real URL shapes |
| `scripts/install.sh` | All of the above, then sign and install |
| `scripts/install.sh --reconvert` | Regenerate the Xcode project first |
| `scripts/make_icons.py` | Redraw `src/icons/*.png` |

The tests run the **compiled** output rather than the TypeScript, so what is
verified is what ships.

## Versioning

The version lives in **two** files and they have to agree:

| | |
| --- | --- |
| `src/manifest.json` | what Safari shows in Settings > Extensions |
| `package.json` | the npm package |

`install.sh` labels the build from the manifest alone, so a drifted `package.json`
would ship a build wearing the wrong number. `build.sh` refuses when they disagree
rather than letting that through.

Bump it on anything that changes shipped behaviour. The number is also the only way
to tell, from Safari's list, whether it actually picked up the new build: two
different builds both calling themselves v1.0.0 are indistinguishable there, and
`install.sh`'s stale-build check cannot see the difference either.

## Converting once, not every time

The project the converter generates does **not** copy the extension in. It writes
relative path references back to `out/extension`, so the project is a live view of
the build output and converting once is enough forever. Re-running the converter
makes a *second* app, which is how several entries come to sit in Safari's list all
reading the same version. `install.sh` therefore converts only when the project is
missing, or on `--reconvert`.

The flip side of a live view is that it breaks when the thing it is viewing moves.
Renaming or relocating the staged extension directory, or adding and removing files
the manifest names, leaves the project pointing at paths that are no longer there
and the build fails on a missing file rather than on anything to do with the code:

```
error: .../extension/background.js: No such file or directory
```

`--reconvert` is the fix, and the only time it is needed.

## Two traps worth knowing

**Bundle identifiers have to nest.** The converter uses `--bundle-identifier`
verbatim for the extension, appending `.Extension`, but rebuilds the *app's*
identifier from that prefix plus the app name. Pass `io.akst.sharepointvideodl`
with an app named `SharePointVideoDL` and you get:

```
app:       io.akst.SharePointVideoDL
extension: io.akst.sharepointvideodl.Extension
```

which fails the build on *"Embedded binary's bundle identifier is not prefixed with
the parent app's"*. The last component of `BUNDLE_ID` must equal `APP_NAME`
exactly, casing included. `install.sh` checks this and explains it rather than
letting Xcode report it as an embedded-binary problem.

**Stray registrations.** Every copy of the app LaunchServices knows about shows up
in Safari's extension list, each reporting its own version -- which is why Safari
sometimes lists the same extension three times. A copy in the Trash stays
registered until the Trash is emptied; the build directory under `out/` is another.
`install.sh` unregisters everything that is not the installed copy, unless
`--no-prune`.

## Install ordering

The install is `rm -rf` then `cp -R`, because `cp -R` over a live bundle *merges*
and a renamed or deleted file would survive into the new app. That ordering has an
obvious failure mode: anything going wrong between the two steps leaves no app at
all. So the copy happens **last**, after the build, the signature and the version
have all been verified, and the old app is only removed once the new one is known
to be good.
