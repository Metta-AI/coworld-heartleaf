# Models For Heartleaf Souls

What a soul's first line can name, what it costs, how fast it answers, and
how each one actually plays. Every id listed here was verified end-to-end
on 2026-09-01 against the hosted platform (heartleaf 0.2.3): a private
league-targeted episode where nine gnomes ran on that model completed a
full game day. An id that is not on this list is not supported — a soul
that names one fails its seat on the first decision call, the failure is
charged to the entrant, and repeated failures disqualify the soul. Stick
to this list.

Latency notes are the wall-clock time of one short decision prompt (a few
hundred tokens in, one JSON object out), measured 2026-08-21; "in a
village" notes come from real games where that model played a gnome for a
full day.

Costs are per million tokens. Claude rows are Anthropic list prices, which
the platform normally matches; the Nova Pro row is not priced on the
public page, so check the AWS console before fielding several of them.

How cost adds up in a game: a gnome makes roughly 40 calls per game day,
and every call resends the append-only transcript of chat, events, and
JSON replies. The current state report is live-only and is not kept, so
old bag-and-viewport dumps do not compound. Claude models read most of
that from the prompt cache at a tenth of the price; Nova Pro pays full
input price every call.

| Shebang id | Family | Cost in / out ($ per 1M) | Latency | Notes |
|---|---|---|---|---|
| `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Claude | 1 / 5 | 1.3 s | The default. Reliable JSON, fast, cached history. |
| `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Claude | 3 / 15 | 2.2 s | Older Sonnet; works, no reason over 4.6. |
| `us.anthropic.claude-sonnet-4-6` | Claude | 3 / 15 | 2.5 s | Sampling allowed, no thinking unless asked. |
| `us.anthropic.claude-sonnet-5` | Claude | 3 / 15 | 2.3 s | Thinks by default; the game switches it off. |
| `us.anthropic.claude-opus-4-5-20251101-v1:0` | Claude | 5 / 25 | 2.2 s | Older Opus. |
| `us.anthropic.claude-opus-4-6-v1` | Claude | 5 / 25 | 2.2 s | Older Opus; sampling allowed. |
| `us.anthropic.claude-opus-4-7` | Claude | 5 / 25 | ~2 s | No sampling parameters. |
| `us.anthropic.claude-opus-4-8` | Claude | 5 / 25 | 1.9 s | Fastest Opus; no sampling parameters. |
| `us.anthropic.claude-opus-5` | Claude | 5 / 25 | 2.4 s | Thinks by default; the game switches it off. |
| `us.amazon.nova-pro-v1:0` | Amazon | not published | 1.6 s | The one non-Claude option. Verbose; fine. |

How the game shapes requests: Claude ids use the Anthropic InvokeModel
body with prompt caching on the system prompt and the history tail; Opus 5
and Sonnet 5 get `thinking: disabled`; Opus 4.7+ and the 5 family get no
`temperature`. Nova Pro goes through the Converse API with
`temperature 0.2`. Any model can still drop a turn: an unusable reply is
simply retried, the gnome keeps doing what it was doing, and nobody is
penalised.

## Claude Haiku 4.5

The workhorse, and the right default. It answers in about a second, never
fails the JSON format in practice, and because the whole history is cached
it is the cheapest Claude by a wide margin in a long game. Its play is
competent rather than clever: it gathers diligently, greets, invites, and
keeps promises, but it rarely builds a plan across days and its chat stays
close to the soul's example phrases. For most seats, and for anything you
run often, start here. With nine gnomes calling at once its speed
matters less than its price.

## Claude Sonnet 4.5 and 4.6

Both work without any special handling and sit between Haiku and Opus on
price and latency. 4.6 is the one to use if you want this tier: sampling
parameters are accepted, it does not think unless asked, and its replies
are a touch more varied than Haiku's. 4.5 is only here because its id is
known to work; there is no reason to pick it over 4.6.

## Claude Sonnet 5

The best value above Haiku. It is roughly as fast as Opus 4.8 and
noticeably more thoughtful than Haiku about hosting versus visiting. It
thinks by default, which would eat the output budget and slow the village,
so the game switches thinking off for it; the replies stay good. If you
want a strong, affordable host seat, this is the pick.

## Claude Opus 4.5, 4.6, 4.7

Older Opus generations. They play well, and 4.5 / 4.6 accept sampling
parameters while 4.7 does not, but every one of them is the same price as
4.8 and slower or no better. They are listed so a soul that names them
still works; for a new soul pick 4.8 or 5.

## Claude Opus 4.8

The fastest Opus in our probes at under two seconds, and the one I would
give to a seat that needs to be persuasive: it reads the conversation
carefully, answers questions it was asked, and times its departures well.
No sampling parameters are sent. Same price as Opus 5 and a little quicker,
so it is a sensible "strong host" choice when you do not need the newest
model.

## Claude Opus 5

Top-tier reasoning at the Opus price. In the village it was the most
deliberate planner: it committed to a table early, pitched its pantry by
name, and kept its promise. It thinks by default; the game disables that,
which keeps replies quick and cheap, and the quality held up without it.
Use it for a champion seat or when you are studying what the ceiling of
social play looks like.

## Amazon Nova Pro

The one non-Claude model on the list. It goes through Converse, answers in
about 1.6 seconds, and tends to write long reasons, but its JSON is
usable. Its history is not cached, so it resends the full transcript at
full input price every call, and its price is not on the public page in
this region — check before fielding several. Pick it when you want a seat
that is not a Claude; otherwise Haiku does the same job for a known price.
