# Setting up the Physlib build cache bucket

Physlib publishes its compiled artifacts so contributors do not have to build
the library from source. This uses Lean's `lake cache`, which is used within get_cache.lean
to fetch the artifacts from a Cloudfare R2 bucket. R2 is the best choice for a small amount of
storage, with lots of people downloading it.

## 1. Create the bucket

Call it `physlib-cache`. Add its S3 API endpoint into `lake-cache.toml` as the write path.

## 2. Allow anonymous reads — outstanding

Contributors fetch without credentials, so the bucket needs a Public Development URL.
We can use the provided '.......r2.dev' domain for testing, but it is better to have a
custom domain which is not rate limited.

Note the resulting hostname; it goes into `lake-cache.toml` at step 5.

Only reads become public. Writes stay behind the key from step 3.

## 3. Create an API token for CI

Create a token with write access, limited to
`physlib-cache`. Keep the Access Key ID and Secret Access Key.

Lake expects them as a single SigV4 credential, colon-separated:

```
<ACCESS_KEY_ID>:<SECRET_ACCESS_KEY>
```

## 4. Add the GitHub secret

Add the keys as a GitHub secret called `LAKE_CACHE_KEY`, set to the colon-joined pair above.

## 5. Fill in the read endpoint

Edit `lake-cache.toml` in the repo root and replace `<R2_PUBLIC_HOST>` with the
hostname from step 2 — hostname only, no scheme, no trailing slash. The write
endpoint is already set.

Filling this in is what makes `lake exe get_cache` actually reach the
bucket -- with a placeholder still in place it points nowhere, the fetch
fails, and the script falls back to its "could not fetch" message rather
than compiling from source silently succeeding.

## 6. Verify

Test these commands work within the Physlib repo:

```bash
lake exe get_cache
lake build
```

## Notes

- Costs to watch as the project grows: storage past 10GB, and Class A
  (write) operations. Egress, the usual scaling problem, is free on R2.
