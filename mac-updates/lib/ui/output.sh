#!/usr/bin/env bash
# output.sh — helpers de impresión. Se hace source en todos los scripts.

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_RESET='\033[0m'

print_header()  { printf "\n${_BLUE}==>%s${_RESET}\n" " $1"; }
print_success() { printf "${_GREEN}[OK]${_RESET} %s\n" "$1"; }
print_warning() { printf "${_YELLOW}[WARN]${_RESET} %s\n" "$1" >&2; }
print_error()   { printf "${_RED}[ERR]${_RESET} %s\n" "$1" >&2; }
print_info()    { printf "  -> %s\n" "$1"; }
