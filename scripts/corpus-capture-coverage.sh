#!/bin/zsh
set -euo pipefail

package_root=$1
coverage_output=$2
test_product=$3
test_log=$4
artifact_directory=${coverage_output:h}

cd "$artifact_directory"
swift test --package-path "$package_root" --enable-code-coverage > "$test_log" 2>&1
build_path=$(swift build --package-path "$package_root" --show-bin-path)
test_binary="$build_path/$test_product.xctest/Contents/MacOS/$test_product"
xcrun llvm-cov export "$test_binary" -instr-profile="$build_path/codecov/default.profdata" > "$coverage_output"
