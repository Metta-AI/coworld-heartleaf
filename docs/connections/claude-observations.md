# Claude connection observations

This report describes one two-day Heartleaf game with nine autonomous Claude Haiku 4.5 gnomes. The run used Claude subscription calls through the first-party provider, a 180-game-minute planning interval, 60-minute conversation gap, 120-second conversation wait, and 300-second bedtime interview deadline. The replay completed 9,120 ticks with matching hashes. The authored `two-day.replay` regression fixture is excluded.

[Portable replay](claude/two-day.bitreplay) · [Run manifest](claude/manifest.json) · [Validation](claude/validation.txt)

## What happened

### 1. Invitations and warm interaction changed Connections before anyone earned food points

On Day 1, the replay recorded no completed dinners and every gnome ended with zero food/game points. The gnomes still formed six conversation groups, made dinner invitations, apologized for missed plans, and held two evening parties. All nine bedtime interviews were valid.

Those rankings produced large Connection differences. Yura and Sasha rose from 0.50 to 1.00 after a sustained gardening conversation. Vova and Dima also rose from 0.50 to 1.00 after an invitation, a missed dinner, an apology, and later party attendance. At Day 1 tick 4320, Dima ranked Vova first because Vova was the only gnome Dima spoke with; Vova ranked Dima first because Dima came after the missed dinner and invited Vova for Day 2.

Observation: the Connection system represented social interaction while food/game points remained separate. Some interview wording overstated the game outcome. Maxim said Vova “Hosted dinner/party,” but the replay contains no Day 1 dinner event. The party claim is supported; the dinner claim is not.

### 2. Updated Connections appeared in accepted Day 2 choices

At Day 2 tick 5639, Dima sent Vova a successful `happy` reaction. The accepted reason says Vova “confirmed she's coming to dinner tonight” and was Dima's “strongest connection (1.00).” At tick 8759, Vova sent Dima `very_happy` after the meal. These were the run's two intentional emoji deliveries; neither changed food/game points or Connection strength directly.

At Day 2 tick 5640, Egor chose `talk_to Ivan`. The accepted reason says: “Ivan is Egor's strongest connection (0.86).” Egor then asked Ivan for lettuce at tick 5999 and invited Ivan to dinner at tick 6719. At tick 8040, Egor again chose Ivan and cited the same 0.86 Connection while apologizing for a broken dinner promise.

Observation: the model read the updated values and referred to them in accepted choices. Interpretation: this is evidence that Connections can affect deliberation. One uncontrolled run cannot show that the values caused those choices.

### 3. The strongest Day 1 pair completed the only Day 2 dinner

Vova and Dima began Day 2 at Connection 1.00. Dima invited Vova, and Vova accepted. At Day 2 tick 7800, the replay recorded the only completed dinner: Vova was Dima's one guest and received 9 food/game points. Dima ate with Vova and received 15 points: 9 for eating plus 6 for hosting one guest. The other seven gnomes remained at zero points.

At the Day 2 interview, Dima ranked Vova first: “Only dinner guest; kept promise, I kept mine, served her (+6 score).” Vova's interview timed out, so only Dima's ranking contributed that night. Their Connection stayed at the 1.00 maximum.

Observation: a previously strong pair kept a mutual dinner plan and produced the game's only food rewards. Interpretation: this is the clearest example of social coordination and game score aligning, but it does not establish an overall score/Connection correlation.

## Main limitation

The interview requires every gnome to rank all eight others. Ordinal position therefore changes Connections even when both reasons say there was no interaction. On Day 1, Sasha–Vova and Dima–Egor fell from 0.50 to 0.00 despite no direct encounter. The total of all 36 pair strengths stayed 18.00 after Day 1, which reflects the zero-sum rank contributions rather than earned social value. Day 2 rankings were also zero-sum before bounds were applied; clamping at 0 and 1 changed the recorded total to 17.82.

The run had 107 accepted model actions, no rejected actions, no malformed replies, and 15 valid interviews out of 18. Vova, Yura, and Nikita timed out on Day 2; each missing interview contributed zero. Some Day 1 party encounter IDs also remained active into Day 2 and generated silent conversation ticks. These rows indicate stale encounter bookkeeping, not continued speech.

The evidence supports three narrow conclusions: social interaction changes Connections without food points; models can use prior Connections in later choices; and one high-Connection pair completed a useful plan. More seeds and a comparison run without Connection values are needed for causal claims.
