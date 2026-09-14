# Pinned Curly transport

This is Curly 1.1.1, copied from upstream revision
`a0f42baacbc48f4e5924b18854c0df9dcc251466`, the revision in `nimby.lock`.
The original `src/curly.nim` SHA-256 is
`c28ee057f4ce5e10a52c1f8b39605e25a84dd9eed476d142d2b25c8a47cca5e4`.
The upstream MIT license is retained in `LICENSE`.

Upstream: https://github.com/guzba/curly

The only behavioral change adds `pipeWait = true` to `newCurly` and stores
that setting before starting its worker. Each transfer uses that value for
`CURLOPT_PIPEWAIT`. The default preserves upstream behavior.

Heartleaf's `bedrock_client.nim` imports this module explicitly and passes
`pipeWait = false`. This prevents a slow first response from delaying other
villagers before their HTTP requests are sent. The existing handle limit and
request timeout are unchanged. Other consumers, including credential fetching
and replay tooling, continue importing the regular Nimby dependency.

A project-owned copy keeps local, CI, and container builds reproducible without
patching a shared Nimby installation. Do not modify the installed dependency.
When upstream exposes an equivalent option, replace this import with the
upstream API, update the lock deliberately, and remove this copy after the
transport regression passes. Do not update the copied source incidentally.

See `eval/docs/recon/heartleaf-eval-startup-investigation-2026-09-08.md` for the
controlled reproduction and the distinction from provider-side latency.
