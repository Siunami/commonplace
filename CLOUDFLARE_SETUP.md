# Publishing Collections to Cloudflare R2

This guide walks through everything needed to host your collections online using Cloudflare R2 (S3-compatible object storage).

When set up, right-clicking a collection in the browse sidebar gives you a **Publish** option that pushes the collection to your bucket. The result is two things per collection:

1. **A JSON API endpoint** — a URL you can `fetch()` or `curl` that returns the collection as JSON (items, metadata, notes, source URLs). Other tools and integrations can hit this directly.
2. **A public web page** — a nicely formatted masonry grid that visually mirrors the in-app browse view. Anyone with the URL can open it in any browser.

---

## Target architecture — one shared template, per-collection JSON

The mental model this guide is aimed at:

```
bucket/
├── viewer.html              ← single shared frontend (uploaded once)
├── viewer.css               ← single shared stylesheet (optional)
├── toread/
│   ├── manifest.json        ← per-collection API endpoint
│   └── files/
│       ├── screenshot-1.png
│       ├── paper.pdf
│       └── …
├── interface/
│   ├── manifest.json
│   └── files/…
└── client-x-refs/
    ├── manifest.json
    └── files/…
```

The viewer page is a single statically hosted file. It takes the collection slug from its URL (e.g. `?c=toread` or a hash fragment), fetches the matching `manifest.json` at a relative path, and renders the masonry grid client-side. The same HTML/CSS/JS powers every collection — you only ever upload the styling once. Per-collection publishes only write the JSON + any new artifact files.

**Two public surfaces per collection:**

- **JSON API**: `https://pub-xxxxx.r2.dev/<slug>/manifest.json` — machine-readable, stable schema, used by the viewer and any external tooling.
- **Webpage**: `https://pub-xxxxx.r2.dev/viewer.html?c=<slug>` — human-readable masonry rendering, styled to match the app's in-window browse grid.

The slug is derived from the collection name (lowercased, spaces → dashes). `toread` stays `toread`. `Client X refs` becomes `client-x-refs`.

---

## Prerequisites

- A Cloudflare account (free tier is fine)
- A credit card on file (R2 free tier has a generous allowance: 10 GB storage, 1M Class A ops/month, 10M Class B ops/month — you won't pay anything for normal personal use, but Cloudflare requires the card anyway)

---

## Step 1 — Create an R2 bucket

1. Log in to the Cloudflare dashboard → **R2 Object Storage**
2. If R2 isn't enabled yet, click **Enable R2** and accept the terms.
3. Click **Create bucket**.
4. Bucket name: pick something like `my-captures` or `yourname-collections`. This is global-ish within your account; pick a name you'll recognize.
5. Location: leave on **Automatic** (or pick the region closest to you).
6. Click **Create bucket**.

## Step 2 — Enable public access on the bucket

By default R2 buckets are private. For the HTML + manifest to be readable by browsers, you need to make the bucket public.

1. Open the bucket you just created.
2. Go to **Settings**.
3. Scroll to **Public Access**.
4. Click **Allow Access** on the "R2.dev subdomain" row. Accept the confirmation.
5. Copy the **Public R2.dev Bucket URL** — it looks like `https://pub-<long-hash>.r2.dev`. Save this, you'll paste it into the app settings.

(Optional: if you want a prettier URL like `https://collections.yourdomain.com`, scroll to **Custom Domains** in the same Settings page and point a domain at the bucket. Use that URL instead of the `pub-xxx.r2.dev` URL in the app settings.)

## Step 3 — Create an R2 API token

The app needs credentials to upload to the bucket. These are separate from your Cloudflare login.

1. From the R2 page (not the bucket), click **Manage API Tokens** (top-right).
2. Click **Create User API Token** (or "Create API token" — wording varies).
3. Token name: `ubicomp-mini-publisher` or similar.
4. Permissions: **Object Read & Write**.
5. Specify bucket: **Apply to specific buckets only** → select the bucket you created in step 1. (Scoping to just this bucket is safer than account-wide.)
6. TTL: **Forever** is fine for personal use.
7. Click **Create API Token**.
8. **Copy both values immediately** — they are only shown once:
   - **Access Key ID** (short string like `abc123def456...`)
   - **Secret Access Key** (longer string)

If you lose them, delete the token and create a new one.

## Step 4 — Find your S3 endpoint

From the same R2 → Manage API Tokens page (or the bucket's settings page), look for the **S3 API** endpoint. It looks like:

```
https://<your-account-id>.r2.cloudflarestorage.com
```

Copy this. You'll paste it as the **Endpoint** in the app settings.

---

## Step 5 — Configure the app

1. Open **Capture → Settings** (or use the app's settings menu).
2. Scroll to the **Publishing (Cloudflare R2)** section.
3. Fill in:
   - **Endpoint**: `https://<account-id>.r2.cloudflarestorage.com` (from step 4)
   - **Bucket**: the bucket name from step 1 (e.g. `my-captures`)
   - **Access Key ID**: from step 3
   - **Secret Access Key**: from step 3
   - **Public URL**: the `https://pub-xxx.r2.dev` URL from step 2 (or your custom domain)
4. Click **Test Connection**. A green checkmark means the credentials work and the bucket is reachable.

---

## Step 6 — Publish a collection

1. Open the **Browse** window (`Ctrl+Cmd+B`).
2. In the sidebar, right-click a collection (or tag — see caveat below about the current state).
3. Click **Publish**. The upload runs in the background.
4. Once done, right-click again and choose **Copy Web URL** to get the shareable link. It'll look like `https://pub-xxx.r2.dev/my-collection/index.html`.
5. Open the URL in a browser to verify.

To take a collection offline, right-click → **Unpublish**. (Note: this currently only flips the local flag — the remote files are **not** deleted. See "Known issues" below.)

---

## Current implementation status

This section is the honest picture of what works and what doesn't. Read this before you commit to publishing anything you care about.

### ✅ What's built

- **`CollectionPublisher.swift`** — complete S3-compatible upload client with manual AWS Signature V4 signing (no SDK dependency).
- **Settings UI** for endpoint / bucket / keys / public URL with a working Test Connection button.
- **Right-click menu** in the browse sidebar: Publish / Unpublish / Copy Web URL / Copy API URL.
- **Manifest generation** — each item's metadata, notes, source app, source URL, and uploaded file URL. This is the JSON API endpoint, exactly the shape described in the target architecture above.
- **HTML generation** — self-contained dark-theme masonry grid that fetches the manifest client-side and renders cards. No build step, no JS framework, no external CSS dependency. Works in any browser. Architecturally the HTML is already a "shared template" in spirit — the same bytes are written for every collection.
- **Thumbnail upload** for files with cached thumbnails.
- **Per-highlight data**: screenshots, recordings, files, clipboard text, URLs — all supported capture types publish correctly.

### ⚠️ What doesn't match the target architecture yet

The current code writes the HTML file **inside each collection's folder** (as `{slug}/index.html`) rather than uploading a single shared viewer at the bucket root. Functionally this works — you get a per-collection URL like `https://pub-xxx.r2.dev/{slug}/index.html` — but it's wasteful and makes styling updates a pain:

- Every publish re-uploads the same HTML bytes to that collection's folder. 30 collections = 30 copies of the same file.
- Updating the viewer styling (to match a new masonry card design, for example) requires re-publishing every collection individually. There's no "push the new viewer and every collection immediately uses it".
- There's no bucket-root landing page listing all your published collections.

The target architecture fixes this by separating the three concerns:

1. **One shared viewer** at `viewer.html` (and optionally `viewer.css`, `viewer.js`) at the bucket root — uploaded once, or only when you change the styling.
2. **Per-collection JSON** at `{slug}/manifest.json` — the only thing that needs to be uploaded on each publish.
3. **Per-collection asset folder** at `{slug}/files/` — only touched when artifacts are added/removed.

The code changes required:

1. Split `generateWebView()` in `CollectionPublisher.swift` into: (a) a one-shot `uploadViewerAssets()` that uploads `viewer.html` (+ CSS/JS if extracted) to the bucket root, and (b) a per-publish `syncCollection()` that only writes the JSON + files.
2. Have `uploadViewerAssets()` run on every `publishCollection()` call but skip the upload if the local viewer hasn't changed (check a content hash in UserDefaults).
3. Rewrite the viewer HTML so it reads the collection slug from `location.search` (e.g. `?c=toread`) or `location.hash` (e.g. `#toread`) and fetches `./<slug>/manifest.json` relative to its own URL.
4. Update the "Copy Web URL" menu item to copy the new `/viewer.html?c=<slug>` URL instead of `/<slug>/index.html`.
5. Keep a redirect at `{slug}/index.html` so old shared links still work (optional — the old URL format could simply be deprecated).

### 🎨 Viewer styling: match the in-app masonry grid

The user-facing webpage should feel like you're looking at the same masonry grid the app shows, just in a browser. The current viewer HTML is close but not matching:

| Element | App masonry | Current viewer | Target |
|---|---|---|---|
| Background | `Color(.windowBackgroundColor)` (dark chrome) | `#1a1a1a` | Match app |
| Card background | `Color(.windowBackgroundColor)` with shadow | `#252525` with border | Match app (no visible border, subtle shadow) |
| Card corner radius | 12pt | 12px | ✓ Same |
| Note typography | `.system(.title3, design: .serif)` — serif pull quote | Sans-serif | **Change to serif** (e.g. Charter, Georgia, or system serif) |
| Note accent bar | Orange `RoundedRectangle` width 2.5, opacity 0.85 | Left border 3px solid orange | Match app styling exactly |
| Grid layout | CSS-grid-masonry-equivalent via `MasonryLayout` | CSS `columns: 280px` | ✓ Close enough |
| Card title | `.callout.weight(.semibold)` | `0.85rem`, weight 500 | Match app's font hierarchy |
| Metadata row | Caption2, tertiary color | Small gray | ✓ Close enough |

The `generateWebView()` function in `CollectionPublisher.swift` (around line 206) is where this lives. Updating it to match the app exactly is a one-time styling pass, but it gets rolled out to every viewer instantly *once* the shared-viewer architecture above is in place.

### ⚠️ What's wired to the OLD tag system, not collections yet

The publishing code currently operates on `Tag` objects, not `Collection` objects. This matters because the main reaction-first curation work in progress replaces tags with collections as the primary grouping concept. Until that work lands:

- Publishing still works **if you're publishing tagged content** (right-click a tag in the sidebar).
- The `isPublished` flag lives on the `tag` table, not on `collection`.
- When the tag → collection migration runs, the publishing hooks will need to be rewired to the new `collection` table. Until then, **publishing collections specifically is not functional** — only publishing the legacy tag-groupings is.

Work that needs to happen to make publishing work for collections:

1. Add `collection.isPublished BOOLEAN DEFAULT 0` as a column in migration v13 (or a follow-up).
2. Port the `isPublished` value from `tag` → `collection` during the tag → collection data migration.
3. Add a `Collection.slug` computed property (mirroring `Tag.slug`).
4. Add `DatabaseManager.setCollectionPublished(id:published:)`, `publishedCollections()`, and use `highlightsInCollection(id:)`.
5. Rewrite `CollectionPublisher` to take a `Collection` instead of a `Tag` — mostly a mechanical rename; the upload/sign/manifest/HTML logic stays identical.
6. Move the Publish/Unpublish right-click menu from the tag sidebar rows to the new collection sidebar rows.

### ❌ Known issues / missing pieces

These apply regardless of whether you're on the old tag system or the new collection system:

1. **Shared viewer isn't implemented yet** (see section above). The HTML is re-uploaded per collection. Works, but redundant.

2. **Auto-resync is dead wiring.** `CollectionPublisher.queueSync(tagId:)` exists and has a 30-second debounce timer, but **nothing calls it**. When you add a new highlight to a published collection, or edit a note, the remote manifest and HTML go stale immediately. You have to manually right-click → **Publish** again to re-push. No change tracking.

3. **Unpublish is half-done.** Right-click → **Unpublish** flips the local `isPublished` flag to false, but it **does not delete the remote files**. Every previously-uploaded file, the manifest, and the HTML stay in the bucket forever. If you publish a private collection by mistake, unpublishing won't remove it from the public URL — you have to go into the Cloudflare dashboard and delete the `{slug}/` prefix manually. The URL will still be reachable until you do.

4. **No cache-busting on `manifest.json` and `index.html`.** They're uploaded without any `Cache-Control` header, so Cloudflare's edge + user browsers will cache them. Updates can take several minutes to propagate unless you append a query string or bust the cache manually. For aggressive iteration, do a hard reload or add `?v=<timestamp>` to the URL.

5. **No Cloudflare Worker, no Pages, no custom pipeline.** The "hosted web page" is literally the raw object in the R2 bucket, served by the bucket's public URL. There's no Worker sitting in front for access control, password protection, request logging, or URL rewrites. If you want any of that, you'll need to add it yourself (set up a Worker route at a custom domain).

6. **No CORS configuration guidance.** The HTML does `fetch('manifest.json')` from the same origin, which works under R2's default CORS. If you ever want to fetch a manifest from a different origin (e.g. embedding in another site), you'll need to configure CORS on the bucket's settings page.

7. **No pagination.** All items in a collection are uploaded in one batch and rendered in one big grid. For collections with hundreds of items, the initial `manifest.json` download will be slow and the HTML page will take a while to render everything. Fine for personal-scale collections (< 100 items); not great beyond that.

8. **No encryption / privacy layer.** Anything you publish is publicly readable by anyone who has the URL. Cloudflare R2's public URLs aren't secret — they're just obscure. If you publish a collection, treat every URL you share as effectively public indefinitely.

---

## Quick checklist

If you want to try publishing today with the legacy tag-based system, this is the punch list:

- [ ] Cloudflare account created
- [ ] R2 enabled
- [ ] Bucket created
- [ ] Public access enabled on the bucket
- [ ] Public R2.dev URL copied
- [ ] API token created (scoped to the bucket, Object Read & Write)
- [ ] Access Key ID + Secret Access Key saved
- [ ] S3 endpoint URL copied
- [ ] All five fields entered in Capture → Settings → Publishing
- [ ] Test Connection passes
- [ ] Right-click a tag in the sidebar → Publish
- [ ] Web URL opens in a browser and shows your collection

If you want to wait until the new collection-based system supports publishing, the work described in the "wired to the OLD tag system" section above needs to happen first. Until then, publishing will only work for the legacy tag surface, and any tags you publish today will carry over automatically when the tag → collection migration runs (the `isPublished` flag migrates with the data).
