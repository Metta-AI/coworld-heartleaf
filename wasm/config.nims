## Build config for the standalone replay viewer. The repo root
## config.nims runs first (paths, outdir); this adds the bitworld root
## so `client/global_client` resolves, and the emscripten target.
import std/[os, strformat, strutils]

const
  WasmDir = thisDir()
  RepoDir = WasmDir / ".."

proc findBitworldRoot(): string =
  ## Returns the bitworld checkout that contains client/dist.
  let sibling = RepoDir / ".." / "bitworld"
  if dirExists(sibling / "client" / "dist"):
    return sibling
  let nimblePkgs = getHomeDir() / ".nimble" / "pkgs2"
  if dirExists(nimblePkgs):
    for kind, path in walkDir(nimblePkgs):
      if kind == pcDir and
          extractFilename(path).startsWith("bitworld-") and
          dirExists(path / "client" / "dist"):
        return path
  echo "bitworld client/dist not found"
  echo "Need ../bitworld or a nimble pkgs2 bitworld package"
  quit 1

let BitworldRoot = findBitworldRoot()
switch("path", BitworldRoot)

when defined(emscripten):
  const OutputDir = WasmDir / "dist"
  if not dirExists(OutputDir):
    mkDir(OutputDir)
  switch("nimcache", OutputDir / "tmp")
  switch("outdir", OutputDir)
  switch("threads", "off")
  --os:linux
  --cpu:wasm32
  --cc:clang
  --clang.exe:emcc
  --clang.linkerexe:emcc
  --clang.cpp.exe:emcc
  --clang.cpp.linkerexe:emcc
  --mm:arc
  --exceptions:goto
  --define:noSignalHandler
  --define:noAutoGLerrorCheck
  --define:release
  # Nim's bundled allocator corrupts the heap under emscripten/wasm32
  # with ALLOW_MEMORY_GROWTH; route allocations through malloc.
  --define:useMalloc

  switch(
    "passL",
    (&"""
    -o {OutputDir / "replay_viewer"}.html
    --preload-file {RepoDir / "data"}@data
    --preload-file {BitworldRoot / "client" / "dist"}@dist
    --shell-file {WasmDir / "shell.html"}
    -O2
    -s ASYNCIFY
    -s FETCH
    -s USE_WEBGL2=1
    -s MAX_WEBGL_VERSION=2
    -s MIN_WEBGL_VERSION=1
    -s FULL_ES3=1
    -s GL_ENABLE_GET_PROC_ADDRESS=1
    -s ALLOW_MEMORY_GROWTH
    -s ABORTING_MALLOC=1
    """).replace("\n", " ")
  )

  if paramStr(1) == "run" or paramStr(1) == "r":
    setCommand("c")
    echo "To run the emscripten build, serve wasm/dist/ over http:"
    echo "  cd wasm/dist && python3 -m http.server 8080"
