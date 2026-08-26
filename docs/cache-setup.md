# Setting up the Physlib build cache bucket

Physlib publishes its compiled artifacts so contributors do not have to build
the library from source. There are two delivery paths:

1. **Lake's own cache**, backed by a Cloudflare R2 bucket. Content-addressed
   and per-file, so a contributor on any branch gets hits for whatever they
   have not changed. This is the path we want long term.
2. **A release tarball** attached to the rolling `cache-master` prerelease.
   A whole-snapshot fallback that needs no infrastructure, used automatically
   whenever path 1 is unavailable.

`scripts/get-cache.sh` tries 1 and falls back to 2, so contributors need not
care which is live.

Path 1 is dormant until the bucket exists. These are the steps to enable it.

## Why R2

For a build cache the dominant cost is **egress** -- every contributor pulls
hundreds of megabytes -- not storage. R2 charges nothing for egress at any
volume, so contributor downloads stay free however far the project grows.
Storage is free to 10GB, which comfortably fits Physlib's artifacts, then
$0.015/GB-month. R2 speaks the S3 API with SigV4, which is exactly what
`lake cache put-staged` uses, so no adapter is needed.

## 1. Create the bucket — done

`physlib-cache`, in Western Europe (WEUR). Its S3 API endpoint is already
filled into `lake-cache.toml` as the write path.

## 2. Allow anonymous reads — outstanding

Contributors fetch without credentials, so the bucket needs public reads. It
currently has none: no custom domain, and the Public Development URL is
disabled. Pick one, in bucket → Settings:

- **Custom Domains** (recommended). Cloudflare rate-limits the `r2.dev`
  development URL and says it is not intended for production traffic — which
  a cache served to every contributor is. A custom domain has no such limit.
- **Public Development URL**. One toggle, and enough to trial the setup. Gives
  a `https://pub-<hash>.r2.dev` hostname. Expect throttling under real load.

Note the resulting hostname; it goes into `lake-cache.toml` at step 5.

Only reads become public. Writes stay behind the key from step 3.

## 3. Create an API token for CI

R2 → Manage API tokens → Create token, with **Object Read & Write** limited to
`physlib-cache`. Keep the Access Key ID and Secret Access Key.

Lake expects them as a single SigV4 credential, colon-separated:

```
<ACCESS_KEY_ID>:<SECRET_ACCESS_KEY>
```

## 4. Add the GitHub secret

Repository → Settings → Secrets and variables → Actions → New repository
secret, named `LAKE_CACHE_KEY`, set to the colon-joined pair above.

The workflows check for this secret and skip the cache steps entirely when it
is absent, so CI keeps working before this point and starts publishing after.

## 5. Fill in the read endpoint

Edit `lake-cache.toml` in the repo root and replace `<R2_PUBLIC_HOST>` with the
hostname from step 2 — hostname only, no scheme, no trailing slash. The write
endpoint is already set.

`scripts/get-cache.sh` treats the presence of `<R2_` as "not provisioned yet",
so filling this in is what switches contributors onto the Lake cache path.

## 6. Verify

Merge to `master` and check the `publish to R2 cache` step ran. Then, from a
clean checkout:

```bash
lake exe cache get       # Mathlib's artifacts
./scripts/get-cache.sh   # Physlib's -- should now report using Lake's cache
lake build               # should be close to a no-op
```

## Notes

- The credential is never committed. Endpoints are public information, which
  is why `lake-cache.toml` is in the repo -- so local contributors get the
  cache without hand-configuring anything.
- `lake-cache.toml` defines two services deliberately: `physlib-r2` for
  anonymous reads and `physlib-r2-upload` for authenticated writes. A
  contributor cannot write to the cache even by accident.
- Lake's cache stores generated C alongside oleans, so the bucket will hold
  more than the ~160MB release tarball. Still well inside the free tier.
- Costs to watch as the project grows: storage past 10GB, and Class A
  (write) operations. Egress, the usual scaling problem, is free on R2.
