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
| v15 | v2 wording restored + morning summons + ranking | 147.2 | 117.8 |
| v16 | v15 without the summons | 129.8 | 114.3 |
| v17 | faithful replica of the league leader, at our seat | — | 18.9 |
| **v18** | v15 + farm the first morning instead of meeting up | 143.4 | **155.9** |

| v19 | summon the channel reader from 3pm, ungated | — | — |
| v20 | summon from 1pm, ahead of the rival's 2:22pm | — | — |

| **v24** | **skip plots a nearer gnome reaches first** | **151.9, 17/22 wins** | — |

## What the numbers taught us

**Food is the half of the score we can still move.** Score is food times
guests; the rival's guests arrive on a timer we cannot touch, but its food
comes from the same thirty-nine plots we are walking to. Passing over a plot
a visibly-nearer gnome will reach first — keeping it only as a fallback —
raised us from 140.4 to 151.9 and dropped the rival from 150.6 to 136.0 on
an identical roster, taking round wins from 3/22 to 17/22. A trip you lose
is worse than no trip: you spend the walk and they get the food anyway.

**A lone round is lost by exactly one guest.** Decoding a losing round:
we recruited our usual guest all eight nights and scored 81, which is
nine food times one guest; the rival scored 124, seven food times two.
Its two arrive on a timer because of its seat and cannot be taken. The
only guest still winnable is the gnome that reads nothing but the bot
channel — it does attend dinners, just other people's. The rival asks
it at 2:22pm; asking later than that loses it every game, and asking
before mid-morning costs the guest we already had, because ours has not
committed yet and a bot-channel line overheard takes its one acceptance.

**Test rosters must fill the spare chairs the way real rounds do.**
Seating a known-recruitable gnome in the empty seat made lone-seat
numbers look like 155 where live rounds gave 69–82. Fill spare chairs
at random instead, or the ranking between versions is measured against
a kinder field than the one being played.

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

**The leader's advantage is its seat, not its play.** Swapping two
entrants and changing no code, the same policy scored 187.8 in the
leader's seat and 84.4 in ours; a faithful replica of the leader's
behaviour, played from our seat, scored 18.9 — the worst result
recorded here. Two gnomes walk into house index 6 at the same tick
every day whatever anyone says, and that house also has nearly twice
our garden within reach. Copying a winner without its position is not
a strategy.

**Careful with test rosters.** The solo figures above seat a known
recruitable gnome in the empty chair, which is kinder than a real
round, where the remaining chairs are filled at random. Read them as an
upper bound and confirm against league rounds.

**The player ships the map with it.** `data/` is copied into the image and
the bot reads `data/map.resource` at runtime to know where the gardens are,
so a build made against an edited map sends the bot to plots the server does
not have. Four gardens displaced by an average of 507px cost a rebuild of
otherwise identical code a steady slide down the table, and it read exactly
like bad luck. Build the player from a clean tree, and when a version that
should behave like its predecessor does not, compare what the two images
contain before re-explaining the scores.

**Controlled A/B, identical fixed rosters both arms:** asking each gnome
every ninety village-minutes instead of twice a day scored 84.5 against
88.1 over 21 and 22 episodes. That is noise, not an improvement — invite
cadence is not where the remaining points are. Note both arms carried the
edited-map build, so the comparison is valid between them and says nothing
about the map.

**A batch is only comparable to another with the same roster.** Filling
spare chairs at random swings the result far harder than any policy change:
the same code scored 143.5 with seven wins in one batch and 117.2 with one
win in another. Fix the spare chairs to a stated mix and change one thing
between arms, or the numbers measure the draw.

## Method

Change one thing per version. Measure both seatings before promoting,
because paired and lone games fail in different ways and the champion's
own worst bug was invisible in paired games. Read games back with
`tools/expand_replay.nim`: dinner events are the scoring record, chat
events carry hearer counts, and between them every claim above was
checked against a real game rather than argued.
