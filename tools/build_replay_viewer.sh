#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/static-replay-viewer" >&2
  exit 1
fi

requested_output="$1"

if [[ "${requested_output}" != /* || "$(basename "${requested_output}")" != "static-replay-viewer" ]]; then
  echo "unsafe bundle output: ${requested_output}" >&2
  exit 1
fi

mkdir -p "$(dirname "${requested_output}")"
output_parent="$(cd "$(dirname "${requested_output}")" && pwd -P)"
output_dir="${output_parent}/static-replay-viewer"
if [[ "${output_dir}" != "${repo_dir}"/* || -L "${output_dir}" ]]; then
  echo "unsafe bundle output: ${requested_output}" >&2
  exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

copy_bundle() {
  local source_dir="$1"
  cp "${source_dir}/replay_viewer.html" "${output_dir}/index.html"
  cp "${source_dir}/replay_viewer.js" "${output_dir}/"
  cp "${source_dir}/replay_viewer.wasm" "${output_dir}/"
  cp "${source_dir}/replay_viewer.data" "${output_dir}/"
  test -s "${output_dir}/index.html"
  test -s "${output_dir}/replay_viewer.js"
  test -s "${output_dir}/replay_viewer.wasm"
  test -s "${output_dir}/replay_viewer.data"
  grep -q 'replay_viewer.js' "${output_dir}/index.html"
}

if [[ -z "${CI:-}" ]] && command -v emcc >/dev/null && command -v nim >/dev/null; then
  echo "Building replay viewer with local emcc"
  (cd "${repo_dir}" && nim c -d:emscripten wasm/replay_viewer.nim)
  copy_bundle "${repo_dir}/wasm/dist"
  exit 0
fi

image_tag="coworld-heartleaf-replay-viewer-build:$$"
container_id=""
cleanup() {
  if [[ -n "${container_id}" ]]; then
    docker rm "${container_id}" >/dev/null 2>&1 || true
  fi
  docker image rm "${image_tag}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

build_args=(
  --platform linux/amd64
  --file "${repo_dir}/Dockerfile.replay-viewer"
  --target replay-viewer-builder
  --tag "${image_tag}"
  "${repo_dir}"
)
if docker buildx version >/dev/null 2>&1; then
  docker buildx build --load "${build_args[@]}"
else
  docker build "${build_args[@]}"
fi
container_id="$(docker create --platform linux/amd64 "${image_tag}")"
docker cp \
  "${container_id}:/workspace/heartleaf/wasm/dist/bundle/." \
  "${output_dir}"

test -f "${output_dir}/index.html"
test -f "${output_dir}/replay_viewer.js"
test -f "${output_dir}/replay_viewer.wasm"
test -f "${output_dir}/replay_viewer.data"
