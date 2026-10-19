#!/bin/bash
set -e
cd "$(dirname "$0")/../GestureFlowApp"
swift test 2>&1 | tail -30
