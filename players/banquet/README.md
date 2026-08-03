# banquet

A Heartleaf gnome that farms the dawn, spends the day recruiting, and
hosts the only meal that scores. No model calls: every decision is
local, so it never waits on a network round trip mid-frame.

## What the game actually pays for

A host scores `food carried x guests present`, resolved on the single
tick when dinner is served (6:55pm, not the 6pm the clock announces).
Guests score nothing, and only a host's inventory is spent — a gnome
that never hosts keeps everything it ever picked.

Three consequences drive the whole policy:

- **Guests are the only multiplier.** Hosting reliably with a full
  pantry and no guest scores zero. Measured across versions, score
  moves with guest count and almost nothing else.
- **Food is a fixed pie that is always eaten.** All 39 gardens are
  stripped every single day, 96% of them before 10am. Whatever is not
  taken in the first two hours is taken by somebody else, so the
  morning is the only part of the day worth farming — and every item
  taken is one denied to a rival host.
- **Banking is a mirage.** Hoarding for one huge night and hosting
  every night come to the same `total food x guests`. Only guests
  multiply.

## The day

| time | host seat | twin seat |
|---|---|---|
| 08:00–10:00 | race the gardens | race the gardens |
| 08:30 onward | recruit whoever comes into view | recruit for the host |
| 10:00–16:30 | walk door to door recruiting | walk door to door recruiting |
| 16:30 | stand at own door | head for the host's door |
| 18:15 | go inside | go inside the host's house |
| 18:55 | dinner resolves | counted as a guest |

Two seats of this policy find each other by chat handshake, elect the
lower house as host, and the other spends the game feeding it guests.
The twin's own harvest is never served to anyone, so its real jobs are
being a guaranteed guest and denying food to rivals.

## Talking

Chat reaches only gnomes whose screen you are on, so recruiting means
physically walking to people. The field does not share one language:

- Most gnomes read **plain sentences**. They accept the first
  invitation they can resolve and will not double-book, so the wording
  must name the house by its owner and reach them before rivals speak.
- Some read only a **bot channel** — a short prefixed line that orders
  them to come *now* rather than booking them for six. The league
  leader says nothing else all game, and its listeners obey and then
  keep returning for the rest of the game unprompted.

These two audiences conflict: a sentence-reader that overhears the bot
channel stops accepting our invitations for that evening. Because chat
is screen-scoped, the summons is held until no known sentence-reader is
in view. The leader does not speak until 14:22; we are talking from
08:33, so saying its line first is the opening.

## Choosing who to ask

Ranked, best first:

1. Gnomes that have **actually eaten at our table** — observed
   directly, by seeing who is standing in our house.
2. Gnomes that hold a **real conversation** — several distinct lines,
   which means something is reasoning behind them.
3. Everyone else.
4. **Recordings** — many lines, only ever one of them. There is no
   persuading a template, so they are asked last.

Behaviour outranks speech deliberately: the most reliable guest in the
current field repeats one identical line all game. Ignoring repeaters
outright would cost us our best recruit, so repetition only breaks
ties.

We never walk into anyone else's house. Eating at a rival's table
scores us nothing and multiplies their plate.

## Working on it

Build and ship:

```sh
docker build --platform linux/amd64 -f players/banquet/Dockerfile -t banquet:latest .
uv run coworld upload-policy banquet:latest --name banquet
uv run coworld submit banquet:vN --league <league-id> --auto-champion always
```

Measure with hosted experience requests, never a local game — put many
episodes in **one** request, since episodes run in parallel while
requests queue. Test both seatings: paired, and alone with the rival
doubled, which is the harder half of real rounds.

Read a game back with `tools/expand_replay.nim` against the episode's
replay artifact; its dinner events are the scoring record, and its chat
events with hearer counts are how every claim above was checked.
