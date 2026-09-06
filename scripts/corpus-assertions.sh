#!/bin/zsh
set -euo pipefail

artifacts=$1

require_status() {
  local id=$1
  local scope=$2
  local missing=$3
  local expected=$4

  [[ $(<"$artifacts/$id.$scope.$missing.status.txt") == "$expected" ]]
}

require_error() {
  local id=$1
  local scope=$2
  local missing=$3
  local expected=$4

  [[ $(<"$artifacts/$id.$scope.$missing.stderr.txt") == *"$expected"* ]]
}

require_summary() {
  local id=$1
  local scope=$2
  local missing=$3
  local total=$4
  local measured=$5
  local assumed=$6

  jq -e \
    --argjson total "$total" \
    --argjson measured "$measured" \
    --argjson assumed "$assumed" \
    '.verification == "captured"
      and .summary.totalFunctions == $total
      and .summary.measuredFunctions == $measured
      and .summary.assumedFunctions == $assumed' \
    "$artifacts/$id.$scope.$missing.json" > /dev/null
}

require_sample() {
  local id=$1
  local file=$2
  local line=$3
  local kind=$4
  local complexity=$5
  local covered=$6
  local executable=$7
  local expected_crap=$8

  jq -e \
    --arg file "$file" \
    --arg kind "$kind" \
    --argjson line "$line" \
    --argjson complexity "$complexity" \
    --argjson covered "$covered" \
    --argjson executable "$executable" \
    --argjson expectedCrap "$expected_crap" \
    '[.functions[] | select(
        .callable.file == $file
        and .callable.span.start.line == $line
        and .callable.kind == $kind
      )] as $matches
      | ($matches | length) == 1
        and $matches[0].callable.complexity == $complexity
        and $matches[0].coveredLines == $covered
        and $matches[0].executableLines == $executable
        and (($matches[0].crap - $expectedCrap) | fabs) < 0.000000000001
        and $matches[0].coverageStatus == "measured"' \
    "$artifacts/$id.target.zero.json" > /dev/null
}

require_status swift-algorithms target error 0
require_status swift-algorithms target zero 0
require_status swift-algorithms package error 0
require_status swift-algorithms package zero 0
require_summary swift-algorithms target zero 534 534 0
require_summary swift-algorithms package zero 534 534 0

require_status swift-collections target error 0
require_status swift-collections target zero 0
require_status swift-collections package error 1
require_status swift-collections package zero 0
require_error swift-collections package error 'Sources/BasicContainers/HashTable/_HTable.swift::deinitializer::_HTable.deinit'
require_summary swift-collections target zero 80 80 0
require_summary swift-collections package zero 5003 4992 11

require_status swift-argument-parser target error 1
require_status swift-argument-parser target zero 0
require_status swift-argument-parser package error 1
require_status swift-argument-parser package zero 0
require_error swift-argument-parser target error 'Sources/ArgumentParser/Parsable Properties/Argument.swift::initializer::Argument.init()'
require_error swift-argument-parser package error 'Examples/color/Color.swift::function::Color.run()'
require_summary swift-argument-parser target zero 914 910 4
require_summary swift-argument-parser package zero 1162 943 219

require_sample swift-algorithms Sources/Algorithms/Grouped.swift 21 function 1 3 3 1
require_sample swift-algorithms Sources/Algorithms/FirstNonNil.swift 33 function 3 8 8 3
require_sample swift-algorithms Sources/Algorithms/MinMax.swift 14 function 5 21 21 5
require_sample swift-algorithms Sources/Algorithms/MinMax.swift 33 closure 1 1 1 1
require_sample swift-algorithms Sources/Algorithms/Partition.swift 238 function 3 0 14 12

require_sample swift-collections Sources/HeapModule/Heap.swift 68 initializer 1 3 3 1
require_sample swift-collections Sources/HeapModule/Heap.swift 205 function 2 20 20 2
require_sample swift-collections Sources/HeapModule/Heap.swift 211 closure 3 11 11 3
require_sample swift-collections Sources/HeapModule/Heap+UnsafeHandle.swift 102 function 11 26 26 11
require_sample swift-collections Sources/HeapModule/Heap+UnsafeHandle.swift 215 function 5 31 31 5

require_sample swift-argument-parser Sources/ArgumentParser/Utilities/StringExtensions.swift 145 function 16 92 92 16
require_sample swift-argument-parser Sources/ArgumentParser/Parsing/SplitArguments.swift 629 function 10 46 52 10.153618570778335
require_sample swift-argument-parser Sources/ArgumentParser/Parsing/SplitArguments.swift 633 closure 1 1 1 1
require_sample swift-argument-parser 'Sources/ArgumentParser/Parsable Properties/NameSpecification.swift' 252 function 8 16 22 9.298271975957926
require_sample swift-argument-parser Sources/ArgumentParser/Utilities/Mutex.swift 46 function 1 3 3 1
