# Models For Heartleaf Souls

What a soul's first line can name, what it costs, how fast it answers, and
how each one actually plays. Everything here was measured on 2026-08-21
through Amazon Bedrock (us-east-1) with the game's own request shapes:
latency is the wall-clock time of one short decision prompt (a few
hundred tokens in, one JSON object out); "in a village" notes come from
real 3-seat games where that model played a gnome for a full day.

Costs are per million tokens. Claude rows are Anthropic list prices, which
Bedrock normally matches; the open-weight and Chinese-lab rows are from the
Bedrock pricing page; rows marked *not published* are models Bedrock
serves but does not price on its public page, so check the AWS console
before fielding them in a league.

How cost adds up in a game: a gnome makes roughly 40 calls per game day,
and every call resends the append-only transcript of chat, events, and
JSON replies. The current state report is live-only and is not kept, so
old bag-and-viewport dumps do not compound. Claude models read most
of that from the prompt cache at a tenth of the price;
the others pay full input price every call, so a cheap-per-token open
model and a cached Claude model can land close to each other.

| Shebang id | Family | Cost in / out ($ per 1M) | Latency | Notes |
|---|---|---|---|---|
| `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Claude | 1 / 5 | 1.3 s | The default. Reliable JSON, fast, cached history. |
| `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Claude | 3 / 15 | 2.2 s | Older Sonnet; works, no reason over 4.6. |
| `us.anthropic.claude-sonnet-4-6` | Claude | 3 / 15 | 2.5 s | Sampling allowed, no thinking unless asked. |
| `us.anthropic.claude-sonnet-5` | Claude | 3 / 15 (2 / 10 intro to 2026-08-31) | 2.3 s | Thinks by default; the game switches it off. |
| `us.anthropic.claude-opus-4-5-20251101-v1:0` | Claude | 5 / 25 | 2.2 s | Older Opus. |
| `us.anthropic.claude-opus-4-6-v1` | Claude | 5 / 25 | 2.2 s | Older Opus; sampling allowed. |
| `us.anthropic.claude-opus-4-7` | Claude | 5 / 25 | ~2 s | No sampling parameters. |
| `us.anthropic.claude-opus-4-8` | Claude | 5 / 25 | 1.9 s | Fastest Opus; no sampling parameters. |
| `us.anthropic.claude-opus-5` | Claude | 5 / 25 | 2.4 s | Thinks by default; the game switches it off. |
| `us.anthropic.claude-fable-5` | Claude | 10 / 50 | 3.5-4.6 s | Thinking cannot be disabled; effort low + 1024-token cap. Needs 30-day data retention. |
| `us.openai.gpt-5.6-luna` / `-sol` / `-terra` | OpenAI | not published | 1.2 s | Excellent in a village (16/16 valid replies). No sampling parameters. |
| `openai.gpt-oss-120b-1:0` | OpenAI open-weight | 0.15 / 0.60 | 4.2 s | Reasons 200+ tokens first; needs the 1024 cap. |
| `openai.gpt-oss-20b-1:0` | OpenAI open-weight | 0.07 / 0.20 | 2.2 s | Same, smaller and cheaper. |
| `us.xai.grok-4.6` | xAI | not published | 2-20+ s | Slow reasoning over a long history; timed out 2 of 5 calls at 20 s, now given 60 s. |
| `us.meta.llama4-maverick-17b-instruct-v1:0` | Meta | not published | 0.8 s | Fast, cheap tier; sometimes invents an action name (retried). |
| `us.meta.llama3-3-70b-instruct-v1:0` | Meta | not published | 0.8 s | Fast, clean JSON. |
| `deepseek.v3.2` | DeepSeek | 0.62 / 1.85 | 4.3 s | Slow for a chat model. |
| `us.deepseek.r1-v1:0` | DeepSeek | not published | 2.6 s | Reasoning model, 200+ tokens of thought per call. |
| `qwen.qwen3-32b-v1:0` | Qwen | 0.15 / 1.20 | 0.7 s | Fastest of all; clean JSON. |
| `qwen.qwen3-next-80b-a3b` | Qwen | 0.15 / 1.20 | 1.4 s | Clean JSON. |
| `qwen.qwen3-vl-235b-a22b` | Qwen | not published | 1.2 s | Vision model; fine as text. |
| `moonshotai.kimi-k2.5` | Moonshot | 0.60 / 3.00 | 0.8 s | Fast, clean JSON. |
| `moonshot.kimi-k2-thinking` | Moonshot | 0.60 / 2.50 | 4.4 s | Reasons ~300 tokens first. |
| `minimax.minimax-m2.5` | MiniMax | 0.30 / 1.20 | 1.8 s | Reasons first, fences its JSON. |
| `zai.glm-5` | Z.AI | 1.00 / 3.20 | 1.4 s | Fences its JSON; fine. |
| `zai.glm-4.7-flash` | Z.AI | 0.07 / 0.40 | 0.8 s | Cheapest listed model. |
| `mistral.mistral-large-3-675b-instruct` | Mistral | 0.50 / 1.50 | 1.0 s | Fences its JSON, verbose reasons. |
| `us.amazon.nova-pro-v1:0` | Amazon | not published | 1.6 s | Verbose; fine. |

Not usable: `anthropic.claude-3-5-haiku-*` (end of life on Bedrock), and any
`anthropic.claude-*-5` / `xai.*` / `openai.gpt-5.6-*` id without the `us.`
inference-profile prefix (on-demand invocation is refused).

How the game shapes requests: Claude ids use the Anthropic InvokeModel body
with prompt caching on the system prompt and the history tail; Opus 5 and
Sonnet 5 get `thinking: disabled`; Opus 4.7+ and the 5 family get no
`temperature`; Fable 5 gets `effort: low` and a 1024-token output cap. Every
other id goes through Bedrock Converse; reasoning families (xai, openai,
deepseek, zai, minimax, anything with "thinking") get no sampling
parameters, a 1024-token cap and a 60-second timeout; plain chat models keep
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

The best value above Haiku. It is roughly as fast as Opus 4.8, noticeably
more thoughtful than Haiku about hosting versus visiting, and until the
end of August it is priced below list. It thinks by default, which would
eat the output budget and slow the village, so the game switches thinking
off for it; the replies stay good. If you want a strong, affordable host
seat, this is the pick.

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

## Claude Fable 5

Works, but it is the hardest model to field. Thinking cannot be switched
off, so every reply pays for reasoning first and takes three to five
seconds; at twice the price of Opus that adds up fast over two million
input tokens. It also tends to keep writing after its JSON, inventing the
next turn of the conversation, which the parser now tolerates by taking
the first complete object. Its play is excellent when it lands, but for a
game whose clock waits on replies I would keep Fable to a single seat, and
only when you want to see what it does.

## OpenAI GPT-5.6 (luna / sol / terra)

The strongest non-Claude result. In a real village it answered every call
with valid JSON, greeted, traded food news, invited and committed, and
Bedrock even reported cache writes for it. It needs no sampling parameters
and about a second per call. Its price is not on Bedrock's public page, so
confirm it in the console before fielding several of them. If you want a
credible rival to the Claude seats, this is it.

## OpenAI gpt-oss (120b / 20b)

Open-weight reasoning models. They spend two to three hundred tokens
thinking before each reply, so they need the larger output cap and take a
few seconds, but the replies themselves are sound. At $0.15 / $0.60 and
$0.07 / $0.20 they are close to free per token; the hidden cost is the
uncached history resent on every call. Good for a budget seat that still
reasons about the day.

## xAI Grok 4.6

It plays, and its replies are fine, but it is the slowest thing here once
the history grows: two of five calls in a real game passed the old
twenty-second timeout while it reasoned. The game now allows it sixty
seconds, which keeps it in the game but means the village waits on it
more than on anyone else. Its price is not published on Bedrock. Worth a
seat if you want Grok in the mix; not a model to give to five gnomes.

## Meta Llama 4 Maverick and Llama 3.3 70B

Fast and cheap, under a second per call. Llama 4 Maverick played a full
day well, with one quirk: a few times it answered with an action name that
does not exist (`commitParty` as the action), which the game treats as an
unusable reply and retries. Llama 3.3 70B produced clean JSON in probes.
Neither is published on Bedrock's pricing page in this region. These are
the natural "cheap but competent" seats alongside Qwen.

## DeepSeek V3.2 and R1

V3.2 is a capable chat model but was the slowest non-reasoning model in
our probes at over four seconds. R1 is the reasoning model: a couple of
seconds plus a few hundred tokens of thought per call. Both answered
correctly. V3.2 is priced at $0.62 / $1.85; R1's Bedrock price is not
published. Fine as a mid-priced seat if you want DeepSeek represented, but
Qwen and Kimi are faster for the money.

## Qwen3 (32B, Next 80B, VL 235B)

The surprise of the probes: Qwen3 32B was the fastest model of all at
under a second, and all three Qwen variants returned clean JSON. At $0.15 /
$1.20 for the text models they are among the cheapest per token. How well
they persuade over a seven-day history is the open question; they are the
first models I would try for a whole cheap village.

## Moonshot Kimi K2.5 and K2-thinking

There is no "K3" on Bedrock; K2.5 is the current chat model and
K2-thinking the reasoning one. K2.5 is fast and clean at $0.60 / $3.00.
K2-thinking reasons about three hundred tokens per call and takes four
seconds, for a slightly lower output price; unless you specifically want
its deliberation, K2.5 is the better gnome.

## MiniMax M2.5

A reasoning model at $0.30 / $1.20: it thinks briefly, then answers with a
fenced JSON block. About two seconds per call and correct in probes. A
reasonable budget reasoning seat; it has not yet played a full village.

## Z.AI GLM-5 and GLM-4.7 Flash

GLM-5 is a solid mid-priced chat model ($1.00 / $3.20) that fences its JSON;
GLM-4.7 Flash is the cheapest model on the list at $0.07 / $0.40 and under a
second per call. Both answered correctly. Flash is the obvious pick for a
throwaway filler seat where cost is all that matters.

## Mistral Large 3

Fast (about a second), $0.50 / $1.50, and it likes to explain itself at
length inside the reason field, wrapped in a code fence. Works fine; no
particular reason to prefer it over Qwen or Kimi at similar cost.

## Amazon Nova Pro

Works through Converse, about 1.6 seconds, and tends to write long
reasons. Its price is not on the public page in this region. Included for
completeness; it has no special strengths for this game.
