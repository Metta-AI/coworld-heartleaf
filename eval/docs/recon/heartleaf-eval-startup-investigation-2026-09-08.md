# Heartleaf eval: reproduced client-side startup delay

Investigation date: September 8, 2026, America/Los_Angeles.

Implementation follow-up: after this investigation, the eval client was changed
to disable PIPEWAIT through a project-owned pinned Curly module. The original
investigation below remains the evidence record; see the final section for the
actual-client regression and its red/green results. Hosted verification is a
separate gate.

## Answer

**The pinned Curly transport can make fast requests miss the 20-second deadline while waiting behind an unrelated slow request.** A controlled local reproduction isolates the cause to its unconditional `CURLOPT_PIPEWAIT=1` setting. Disabling only that setting removes the delay. This is a game-client dependency issue, not a required backend change.

With one fake response taking 18 seconds and eight taking 3 seconds, the current transport timed out all eight fast calls at approximately 20 seconds. With PIPEWAIT disabled, all nine succeeded: fast calls took approximately 3 seconds and the slow call 18 seconds. Both tests retained nine handles and the same 20-second deadline. Evidence: `tmp/heartleaf-eval/startup-investigation/deadline-on.client.jsonl:1` and `deadline-off.client.jsonl:1`; test setup in `probe.nim:5` and `run_cases.py:14` in that directory.

This establishes the local mechanism and strongly explains the historical startup pattern. It does not prove that every historical pre-proxy delay had the same cause: the hosted run did not record curl connection diagnostics.

## Mission and boundaries

Test whether connection scheduling explains the approximately 19-second gap between initial game enqueue and upstream inference. Compare cold and reused clients, vary response-header timing, and change only PIPEWAIT in the treatment. No hosted requests, inference spend, backend edits, runtime source edits, dependency pin changes, or published images were made. All experimental code and logs are under the ignored `tmp/heartleaf-eval/startup-investigation/` directory.

## Results

Six controlled cases, each containing two consecutive nine-request waves: **108 fake calls total**. The first request in each wave is deliberately slow; the other eight are fast. Numbers below describe those eight fast requests. The two transport binaries differ only in PIPEWAIT; both also enable identical curl diagnostic logging. `curly_transport.nim:292` contains the experimental switch, and `results.json` contains every request result.

| Fake response behavior | PIPEWAIT | First-wave fast-call median | First-wave timeouts | Second-wave fast-call median | Second-wave timeouts |
| --- | --- | ---: | ---: | ---: | ---: |
| 4 s slow / 0.1 s fast, delayed headers | on | 4.130 s | 0 / 8 | 0.105 s | 0 / 8 |
| Same | off | 0.152 s | 0 / 8 | 0.109 s | 0 / 8 |
| 4 s slow / 0.1 s fast, immediate headers | on | 4.126 s | 0 / 8 | 0.102 s | 0 / 8 |
| Same | off | 0.135 s | 0 / 8 | 0.106 s | 0 / 8 |
| 18 s slow / 3 s fast, delayed headers | on | 20.006 s | 8 / 8 | 20.003 s | 8 / 8 |
| Same | off | 3.035 s | 0 / 8 | 3.012 s | 0 / 8 |

The second wave reuses the same Curly client, but is **not necessarily a healthy warm connection pool**: timeouts close transfers/connections. The repeated failure in the deadline case shows that the problem can recur after timeouts; it is not safely dismissed as a one-time startup cost. In the four short-response cases, healthy second waves have no material added delay. Source: each case's `.client.jsonl`, `.server.jsonl`, and the corresponding `results.json` entry. The summary field `fast_completed` counts returned results, including errors; it is not a success count.

### Where the waiting happens

In the delayed-header 4-second case, the eight fast requests reached the fake server **4.028–4.029 seconds after enqueue** with PIPEWAIT enabled, versus **46–48 milliseconds** with it disabled. Server processing remains 100 milliseconds in both. There is no provider or translation layer in this experiment. The missing seconds occur before server receipt, inside client transport scheduling. Source: `delayed-headers-on.server.jsonl`, `delayed-headers-off.server.jsonl`, and joined receipt delays in `results.json`.

Curl's diagnostic output explicitly reports `Server doesn't support multiplex yet, wait` and `No connections available.` After the initial transfer finishes, it reports `Transfer was pending, now try another` and opens the other connections. Source: `delayed-headers-on.curl.log:1`. Curly already has nine easy handles and a nonblocking multi-transfer loop; this is not evidence that its one I/O thread serializes all requests. Its PIPEWAIT choice overrides the default of opening another connection rather than waiting. [Official curl option documentation](https://curl.se/libcurl/c/CURLOPT_PIPEWAIT.html).

The early-header control is important: the fake server flushes HTTP/1.1 headers immediately, then waits four seconds before its body. **The waiting calls still are not sent until the body finishes** in this tested libcurl version. Streaming headers alone therefore does not repair the reproduced transport behavior. `early-headers-on.server.jsonl:2` records first receipt, immediate headers, body completion four seconds later, and only then other receipts. The HTTP header/body split is implemented at `server.py:30`.

## Connection to the hosted failure

The original job used a plain local URL such as `http://127.0.0.1:9100/model/.../converse`, and all initial calls were enqueued within approximately 1.5 seconds. The first Qwen request reached upstream promptly but took approximately 51 seconds. Other calls reached upstream around the first 20-second timeout boundary, including a Haiku call whose own provider execution was only 1.366 seconds. This ordering is consistent with a slow first connection holding other requests until timeout releases transport capacity. Sources: `tmp/heartleaf-eval/20260908-retry1/live/job-fd3557f1-gdqwz.game.log:45`, `:57`, `:68`, and the earlier [latency breakdown](heartleaf-eval-latency-breakdown-2026-09-08.md).

The real Converse route waits for forwarding before returning its response; no early response is required to match the delayed-header fake-server case. Source: Metta commit `712af9f8713f08e6a083a36a704abad06974cdbd`, `app_backend/src/metta/app_backend/job_runner/bedrock_sidecar.py:1706` through its return at `:1717`. Those sidecar files were previously verified unchanged through the recorded later backend commit, as documented in the latency breakdown.

**Observed:** the option causes false timeouts locally on the same Linux libcurl package used by the frozen eval runtime. **Inferred:** this is the principal historical startup-delay mechanism. **Not established:** a packet-for-packet reconstruction of the old hosted run, or that this explains upstream generation durations above 20 seconds. Fixing transport cannot make a provider's 25-second completion fit a 20-second deadline.

## Recommended next change, not implemented

Disable PIPEWAIT for Heartleaf's local HTTP sidecar transport while retaining the nine-request cap and 20-second deadline. Prefer a small supported Curly configuration option or upstream fix over replacing the HTTP client, creating one client per seat, or adding an artificial warm-up call. The installed Curly API does not expose this setting: `newCurly` takes only `maxInFlight` at pinned `src/curly.nim:442`, and the option is hardcoded at `:292`.

Checked current upstream Curly HEAD `9fd2c2607bf114563433d770f577e4424a921047`; it still hardcodes PIPEWAIT, so merely updating Curly is not an evidenced fix. [Current upstream source](https://github.com/guzba/curly/blob/9fd2c2607bf114563433d770f577e4424a921047/src/curly.nim#L274). Changing this transport policy may use more TCP connections, bounded here by the existing nine handles. It should be scoped to this client rather than silently changing multiplexing behavior for unrelated consumers.

Verification should preserve this local regression case, then rebuild only the eval game image and run a labeled hosted nine-player comparison. Require all initial requests to reach the sidecar promptly and all actions to arrive before the unchanged deadline. Keep provider/routing changes separate so an improved provider does not hide a still-present transport defect. No backend changes are needed for that experiment.

## Toolchain, directory map, and reproduction

Heartleaf was fetched/pruned and HEAD remained `ad3c13860431cf29f7f8ac5e04ffe6b632928ad9`, equal to `origin/master`; existing changes were preserved. This track did not invoke the Coworld or Softmax CLI, so no CLI-version-dependent conclusion was made.

Used the already-built frozen test image `heartleaf-eval-qwen-frozen-test:20260908`, image ID `sha256:a79daae13da5d460bf657bcfa6b925ea1d76ffc4fed0339a9f537026e90e3baf`, with Nim **2.2.4**, ORC, threads enabled, release mode, Linux amd64, and Debian libcurl **7.88.1-10+deb12u15**. Independently read `dpkg-query -W libcurl4` in `heartleaf-eval-qwen-frozen:20260908`; it reports the same package version. The image was run under local arm64 emulation, using a host-side Python 3.13.5 threaded fake HTTP/1.1 server. This is a local network hop, not the production loopback interface; the tens-of-milliseconds control baseline measures its modest overhead.

The first compile attempt put the probe outside the project tree and could not locate `webby/httpheaders`. Moving the mount under the image's actual project directory loaded its existing Nimby-generated `nim.cfg` and project settings; both binaries then compiled successfully. No dependency was installed or toolchain guard bypassed.

```text
tmp/heartleaf-eval/startup-investigation/
  curly_transport.nim   Copy of pinned Curly, diagnostic option toggle only
  probe.nim             Nine simultaneous calls, two waves, fixed 20 s timeout
  server.py             Threaded local fake server, configurable header/body delay
  run_cases.py          Starts six isolated cases and terminates its servers
  results.json          All 108 results and aggregate timing/error counts
  *.client.jsonl        Enqueue/completion timestamps and errors
  *.server.jsonl        Receipt/body-read/header/completion timestamps
  *.curl.log            libcurl connection scheduling diagnostics
```

Build and run from the Heartleaf root:

```sh
docker run --rm --platform linux/amd64 \
  -v "$PWD/tmp/heartleaf-eval/startup-investigation:/workspace/heartleaf/probe" \
  --entrypoint sh heartleaf-eval-qwen-frozen-test:20260908 -c \
  'nim c -d:probeVerbose --out:/workspace/heartleaf/probe/probe-pipewait /workspace/heartleaf/probe/probe.nim && nim c -d:probeVerbose -d:probeNoPipewait --out:/workspace/heartleaf/probe/probe-no-pipewait /workspace/heartleaf/probe/probe.nim'

tmp/heartleaf-eval-venv/bin/python \
  tmp/heartleaf-eval/startup-investigation/run_cases.py
```

The pinned Curly original SHA-256 is `c28ee057f4ce5e10a52c1f8b39605e25a84dd9eed476d142d2b25c8a47cca5e4`, revision `a0f42baacbc48f4e5924b18854c0df9dcc251466` from `nimby.lock:12`. The probe binaries are `3d2427060c8b69e3d2e33620893d016e4163683b3b3170498dfa69dc82951cd0` (on) and `bc8e8dfc67bad3a6921b705d9bc6155a8108e9ce4fe528aa6deb1c8b4e5b235a` (off). All test servers and containers were stopped after collection.

## Unresolved

The controlled transport cause is resolved. Exact historical attribution remains an inference until a hosted run captures connection timings or validates the isolated transport change. Newer libcurl versions were not benchmarked; no claim is made that upgrading libcurl alone fixes this behavior. Provider-side generation tails remain a separate workstream.

## Implementation follow-up: actual-client regression

The project-owned `vendor/curly/curly.nim` exposes a `pipeWait` constructor option
while retaining the previous default for other consumers. Only
`src/heartleaf/bedrock_client.nim` selects `pipeWait = false`; unrelated upstream
Curly consumers are unchanged. This is a client/dependency change, not a backend
change.

Added `tests/bedrock_transport.nim` and `tests/test_bedrock_transport.py`, invoked
by `.github/workflows/tests.yml`. The Nim program uses the actual Bedrock client.
The local Python server holds seat 0's response, then permits the other eight
requests to start. The test requires all nine requests to reach the server and
all eight fast replies to become usable **before** releasing seat 0. It repeats
on the same client. The safety timeouts bound failures; success depends on the
causal ordering, not a tight stopwatch threshold.

Validation in the existing frozen Linux amd64 build image, Nim 2.2.4 and
libcurl 7.88.1:

- **Green:** current client passed both waves, with 18 usable replies.
- **Red:** an isolated copy of the client with only `pipeWait = true` failed
  at the expected barrier: `wave 0: requests waited behind the held first
  response; received seats [0]`. No shared source was edited for this control.
- `ruff check`, `ruff format --check`, and `git diff --check` passed for the
  regression work. Evidence: `regression-green.log` and `regression-red.log`
  in the investigation artifact directory.

Normal project-toolchain invocation:

```sh
nim c tests/bedrock_transport.nim
python3 tests/test_bedrock_transport.py --probe out/bedrock_transport
```

These checks prove the implemented client change repairs the reproduced
concurrency defect. They do not establish a complete hosted episode or remove
provider-side generation tails.
