#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

swiftc -O -framework AppKit -framework Carbon -framework ApplicationServices \
  ClipHistory.swift -o cliphistory

echo "Built: $(pwd)/cliphistory"
