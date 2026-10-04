# Signing

This is the part that decides whether the extension is pleasant to live with.

## Why it matters

An ad-hoc signature (`CODE_SIGN_IDENTITY=-`) builds and installs perfectly well,
and then Safari treats the extension as unsigned. It stays invisible until
**Develop > Allow Unsigned Extensions** is ticked, and Safari forgets that tick
every time it quits. So the extension works, and costs a small ritual every single
day.

Signing with a real Apple-issued certificate removes the ritual entirely. The
extension appears in Settings > Extensions like any other, and the tick survives
restarts. There is no Develop menu step at all.

## What the script picks

`scripts/install.sh` chooses an identity from the keychain, in this order:

1. **Developer ID Application** -- accepted on any Mac, and the only one worth
   having if the app is ever going to leave this machine. Needs a paid Apple
   Developer account, and really wants notarisation as well.
2. **Apple Development** -- valid on the machine that owns the certificate, which
   is all this needs. A free Apple ID can create one: Xcode > Settings > Accounts.

If neither exists the script refuses rather than quietly falling back to ad-hoc,
because an unsigned build is the one outcome not worth installing.

Override the choice when the guess is wrong:

```sh
IDENTITY='Apple Development: Someone Else (XXXXXXXXXX)' scripts/install.sh
TEAM=LJSS9VN32Z scripts/install.sh      # if the certificate OU cannot be read
```

The team is read from the certificate's `OU` field, which is what `xcodebuild`
wants for `DEVELOPMENT_TEAM`. Signing is `CODE_SIGN_STYLE=Manual` with no
provisioning profile, which is enough for a locally installed Mac app.

## Verifying, rather than trusting

A green build is not a signed one, so the script checks afterwards and refuses to
install if what came out was ad-hoc after all. The check is that `codesign` reports
an `Authority`, which an ad-hoc signature has none of.

To confirm by hand:

```sh
codesign -dvv ~/Applications/SharePointVideoDL.app
codesign --verify --deep --strict --verbose=2 ~/Applications/SharePointVideoDL.app
```

A properly signed build shows the full chain and a team, on both the app and the
extension inside it:

```
Identifier=io.akst.SharePointVideoDL
Authority=Apple Development: Angus Thomsen (2EP92V462Z)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=LJSS9VN32Z
```

`Signature=adhoc`, or no `Authority` line, means Safari will call it unsigned.

## Moving it to another Mac

An Apple Development certificate is valid on the machine that owns it. Installing
this somewhere else means a Developer ID Application certificate and notarisation
(`xcrun notarytool submit`, then `xcrun stapler staple`). The script already
prefers Developer ID when the keychain has one, so that path needs no change here
beyond getting the certificate.
