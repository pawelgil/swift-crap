#!/bin/zsh
set -euo pipefail

script_root=${0:A:h}
project_root=${script_root:h}
swift_crap=${1:-"$project_root/.build/debug/swift-crap"}
swift_crap=${swift_crap:A}
workspace=${2:-$(mktemp -d /private/tmp/swift-crap-corpus.XXXXXX)}
artifacts="$workspace/artifacts"
manifest="$project_root/Tests/Compatibility/corpus.json"

[[ $(uname -s) == Darwin ]]
for command_name in git jq shasum swift xcodebuild xcrun; do
  command -v "$command_name" > /dev/null
done
if [[ -e "$artifacts" ]]; then
  print -u2 -r -- "corpus artifacts already exist; use a fresh workspace: $artifacts"
  exit 1
fi
mkdir -p "$artifacts"
cp "$swift_crap" "$artifacts/swift-crap"
chmod +x "$artifacts/swift-crap"
swift_crap="$artifacts/swift-crap"
shasum -a 256 "$swift_crap" > "$artifacts/swift-crap.sha256"
swift --version > "$artifacts/toolchain.txt"
xcodebuild -version >> "$artifacts/toolchain.txt"
xcrun llvm-cov --version >> "$artifacts/toolchain.txt"
xcrun llvm-profdata --version >> "$artifacts/toolchain.txt"

clone_pinned() {
  local id=$1
  local url=$2
  local release=$3
  local commit=$4
  local destination="$workspace/$id"

  git clone --branch "$release" --depth 1 "$url" "$destination"
  [[ $(git -C "$destination" rev-parse HEAD) == "$commit" ]]
}

prepare_package() {
  local package_root=$1

  cd "$package_root"
  swift build --build-tests --enable-code-coverage
}

capture_package() {
  local id=$1
  local test_product=$2
  local package_coverage=${3:-}
  local package_root="$workspace/$id"
  local build_path
  local coverage_arguments=(--coverage "$artifacts/$id.coverage.json")
  build_path=$(cd "$package_root" && swift build --show-bin-path)

  if [[ -n "$package_coverage" ]]; then
    coverage_arguments+=(--coverage "$package_root/$package_coverage")
  fi

  "$swift_crap" capture \
    --root "$package_root" \
    --output "$artifacts/$id.receipt.json" \
    "${coverage_arguments[@]}" \
    --build-description "$build_path/description.json" \
    -- zsh "$script_root/corpus-capture-coverage.sh" "$package_root" "$artifacts/$id.coverage.json" "$test_product" "$artifacts/$id.tests.log"
}

record_analysis() {
  local id=$1
  local scope=$2
  local missing=$3
  local target=${4:-}
  local package_root="$workspace/$id"
  local output="$artifacts/$id.$scope.$missing.json"
  local error_output="$artifacts/$id.$scope.$missing.stderr.txt"
  local status_output="$artifacts/$id.$scope.$missing.status.txt"
  local arguments=(
    analyze
    --package "$package_root"
    --coverage "$artifacts/$id.coverage.json"
    --provenance "$artifacts/$id.receipt.json"
    --missing "$missing"
    --threshold 100000
    --format json
  )

  if [[ -n "$target" ]]; then
    arguments+=(--target "$target")
  fi

  if "$swift_crap" "${arguments[@]}" > "$output" 2> "$error_output"; then
    print -r -- 0 > "$status_output"
  else
    print -r -- $? > "$status_output"
  fi
}

record_native_oracles() {
  local id=$1
  local test_product=$2
  shift 2
  local package_root="$workspace/$id"
  local build_path
  build_path=$(cd "$package_root" && swift build --show-bin-path)
  local test_binary="$build_path/$test_product.xctest/Contents/MacOS/$test_product"
  local profile="$build_path/codecov/default.profdata"
  local source_file
  local source_paths=()

  for source_file in "$@"; do
    source_paths+=("$package_root/$source_file")
  done

  xcrun llvm-cov report "$test_binary" -instr-profile="$profile" -ignore-filename-regex='(/Tests/|/.build/|/Benchmarks/)' > "$artifacts/$id.native-report.txt"
  xcrun llvm-cov report "$test_binary" -instr-profile="$profile" --show-functions "${source_paths[@]}" > "$artifacts/$id.native-functions.txt"
  : > "$artifacts/$id.native-show.txt"
  for source_file in "$@"; do
    print -r -- "$source_file" >> "$artifacts/$id.native-show.txt"
    xcrun llvm-cov show "$test_binary" -instr-profile="$profile" "$package_root/$source_file" >> "$artifacts/$id.native-show.txt"
  done
}

while IFS=$'\t' read -r id url release commit; do
  clone_pinned "$id" "$url" "$release" "$commit"
done < <(jq -r '.repositories[] | [.id, .url, .release, .commit] | @tsv' "$manifest")

cd "$workspace/swift-algorithms"
numerics_release=$(jq -r '.repositories[] | select(.id == "swift-algorithms") | .dependencyPins[0].release' "$manifest")
numerics_commit=$(jq -r '.repositories[] | select(.id == "swift-algorithms") | .dependencyPins[0].commit' "$manifest")
swift package resolve
swift package resolve swift-numerics --version "$numerics_release"
[[ $(git -C .build/checkouts/swift-numerics rev-parse HEAD) == "$numerics_commit" ]]

while IFS= read -r id; do
  prepare_package "$workspace/$id"
done < <(jq -r '.repositories[].id' "$manifest")

while IFS=$'\t' read -r id test_product target; do
  if [[ "$id" == swift-argument-parser ]]; then
    capture_package "$id" "$test_product" default.profraw
  else
    capture_package "$id" "$test_product"
  fi

  record_analysis "$id" target error "$target"
  record_analysis "$id" target zero "$target"
  record_analysis "$id" package error
  record_analysis "$id" package zero
done < <(jq -r '.repositories[] | [.id, .testProduct, .auditTarget] | @tsv' "$manifest")

record_native_oracles swift-algorithms swift-algorithmsPackageTests \
  Sources/Algorithms/FirstNonNil.swift \
  Sources/Algorithms/Grouped.swift \
  Sources/Algorithms/MinMax.swift \
  Sources/Algorithms/Partition.swift
record_native_oracles swift-collections swift-collectionsPackageTests \
  Sources/HeapModule/Heap.swift \
  Sources/HeapModule/Heap+UnsafeHandle.swift
record_native_oracles swift-argument-parser swift-argument-parserPackageTests \
  Sources/ArgumentParser/Utilities/StringExtensions.swift \
  Sources/ArgumentParser/Parsing/SplitArguments.swift \
  'Sources/ArgumentParser/Parsable Properties/NameSpecification.swift' \
  Sources/ArgumentParser/Utilities/Mutex.swift

zsh "$script_root/corpus-assertions.sh" "$artifacts"
print -r -- "$workspace"
