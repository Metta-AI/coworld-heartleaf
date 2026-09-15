# Dialogue at dinner and bedtime

The September 14 review reproduced two viewer faults in the historical two-day
Claude recording. These were separate from the stale action plan after a gnome
left a conversation.

- A final chat was captured on the same simulation step that sent its speaker
  home. The viewer then waited for that line's reading time with no visible card.
- Dinner-room cuts reset dialogue reading history. Returning outdoors could
  replay old lines, while the room tour hid new speech from another map. The
  longest observed blank interval was roughly 50 seconds near the second curfew.

The viewer now captures final-tick dialogue before crossing the conversation's
end, without capturing it twice on the eventual simulation step. It retains each
line's reading progress when changing rooms, separately from the cards visible in
that shot. Unread speech from the committed conversation temporarily directs the
camera to its actual map; the dinner tour resumes afterward. A seek rebuilds the
feed, making previously watched dialogue available again.

No recorded game decisions, coordinates, rewards or simulation hashes change.
The old recording remains a regression fixture, including its sparse model
planning and missing overnight conversation exits.

## Verification

`tests/replay_dialogue_boundaries.nim` checks the final farewell before curfew,
one capture per playback pass, replay after a backward seek, the three lines
previously hidden by dinner-room cuts, and no repeated reading across room cuts.
It verifies the speaker and camera are on the recorded line's map.

`tests/real_replay_director.nim` checks all 12 conversations, both nights of
rankings and updates, at least the previous 49 distinct dialogue lines, every
recorded simulation hash, and no invisible backlog at a conversation's end. All
eight playback speeds finish in increasing speed order. The repaired historical
recording takes 12,220 presentation frames (about 8 minutes 29 seconds at 1X),
including the bedtime ranking pages.

The fresh normal-timing game is documented separately in this review directory.
