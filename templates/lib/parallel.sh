#!/usr/bin/env bash
# lib/parallel.sh — compatibility shim; sources parallel_core.sh and parallel_teams.sh
source "$(dirname "${BASH_SOURCE[0]}")/parallel_core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/parallel_teams.sh"
