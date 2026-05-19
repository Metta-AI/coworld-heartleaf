import os

const RootDir = thisDir()

switch("path", RootDir / "src")
switch("outdir", RootDir / "out")
switch("threads", "on")
switch("mm", "orc")

when not defined(debug):
  --define:release
  --define:noAutoGLerrorCheck
