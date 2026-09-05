#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift package resolve
