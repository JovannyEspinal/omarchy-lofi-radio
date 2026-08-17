#!/usr/bin/env bash

set -u

readonly plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fps=${1:-60}

if [[ ! $fps =~ ^[0-9]+$ ]]; then
  fps=60
fi
((fps < 15)) && fps=15
((fps > 120)) && fps=120

exec cava -p <(sed "s/^framerate = .*/framerate = $fps/" "$plugin_dir/cava.conf")
