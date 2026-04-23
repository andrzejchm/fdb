#!/usr/bin/env zsh
# Wrapper used by the VHS tape — strips pub/dart noise from fdb output
export PATH="/Users/andrzejchm/fvm/versions/3.41.6/bin:/Users/andrzejchm/.pub-cache/bin:$PATH"
fdb "$@" 2>&1 | grep -v "^Can't load\|^FINE:\|^IO  :\|^MSG :\|^SLVR:\|^WARN:"
