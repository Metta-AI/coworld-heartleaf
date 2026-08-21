## The poet villager: the soul_player uploader with this persona's
## soul.md baked in.

import players/soul_player/soul_player

const SoulMarkdown = staticRead("soul.md")

when isMainModule:
  soulPlayerMain(SoulMarkdown)
