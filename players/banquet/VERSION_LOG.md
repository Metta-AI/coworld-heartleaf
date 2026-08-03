# banquet — version log

Every entry is a hosted experience request against the real league
field, 12 episodes, exact league seating. **twin** = two banquet seats
(3 and 7), **solo** = one seat with the rival doubled, which is the
harder half of real rounds. Local games are never used: they are far
too slow to learn from.

| ver | change | twin | solo |
|---|---|---|---|
| v1 | first coordinated twin policy | — | — |
| **v2** | fixed hosted timing; **the bar to beat** | **135.4** | **115.5** |
| v3 | invite on the bot channel, abbreviated house | 88.9 | — |
| v4 | farm the morning, split twin roles, tour doors | 93.3 | 30.8 |
| v5 | bot channel with full names | 97.4 | 37.7 |
| v6 | recruit through the empty afternoon | 87.8 | 33.6 |
| v7 | recruiting no longer gated on the handshake | 85.6 | — |
| v8 | plain line first, channel line as follow-up | 88.0 | 33.2 |
| v9 | follow-up only to gnomes that never speak | — | 65.0 |
| v10 | **champion + name our own house, nothing else** | — | **38.3** |
| v11–v14 | summons work, target ranking (inherit v10 wording) | — | — |
| v15 | v2 wording restored + morning summons + ranking | pending | pending |

## What the numbers taught us

**The invitation wording is load-bearing, and not the way you would
guess.** v10 is the champion with one string changed and nothing else.
A host asking in its own voice — "Dinner at my house at 6! All
welcome!" — recruits about three times better than the same host
naming itself in the third person. In paired games both wordings go
out at once, one from each twin, which hides the effect completely;
only a lone seat speaks with a single voice and separates them. Do not
"clarify" this line.

**Recruiting must never wait on anything.** v4–v6 gated invitations
behind the twin handshake, so a seat that never found a twin called for
one all morning and made its first invitation at exactly noon, after
the only window in which no rival is allowed to be recruiting. That one
gate is most of the difference between 115 and 33.

**The bot channel cuts both ways.** Some gnomes read only a short
prefixed order and obey it; the gnome that reliably eats with us stops
accepting invitations for the evening if it overhears that same order.
Emitting it broadly scored 33.2, selectively 65.0, never 115.5. Chat
reaches only gnomes on our screen, so the order is held until no
sentence-reader is in view rather than dropped.

**Two claims that looked solid and were wrong.** The rival's two
regular guests were read as clock-driven and unwinnable because they
arrive at the same tick daily with nothing said beforehand; the better
reading is that its opening-day order captured them and every later
arrival only looks unprompted. And the twins were suspected of failing
to pair once the meetup walk was removed — they paired nine nights out
of nine.

## Method

Change one thing per version. Measure both seatings before promoting,
because paired and lone games fail in different ways and the champion's
own worst bug was invisible in paired games. Read games back with
`tools/expand_replay.nim`: dinner events are the scoring record, chat
events carry hearer counts, and between them every claim above was
checked against a real game rather than argued.
