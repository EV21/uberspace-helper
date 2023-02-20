#!/usr/bin/env bash

# This script installs syntax highlighting only for shell scripts
# It is ment to be used on fresh Uberspaces

mkdir ~/.nano
cat << 'end_of_content' > ~/.nano/sh.nanorc
## Syntax highlighting for Bourne shell scripts.
## UBERSPACE EDITION (compatible with nano 2.3.1)

syntax "sh" "(\.sh|(\.|/)(a|ba|c|da|k|mk|pdk|tc|z)sh(rc|_profile)?|/(etc/|\.)profile)$"
header "^#!.*/((env\s+)?((a|ba|c|da|k|mk|pdk|tc|z)?sh)|busybox\s+sh|openrc-run|runscript)\>"
header "-\*-.*shell-script.*-\*-"
magic "(POSIX|Bourne-Again) shell script.*text"
#comment "#"

#linter dash -n

# Function declarations.
color brightgreen "^[A-Za-z0-9_-]+\(\)"

# Keywords, symbols, and comparisons.
color green "\<(break|case|continue|do|done|elif|else|esac|exit|fi|for|function|if|in|read|return|select|shift|then|time|until|while)\>"
color green "\<(declare|eval|exec|export|let|local)\>"
color green "[{}():;|`$<>!=&\\]" "(\]|\[)"
color green "-(eq|ne|gt|lt|ge|le|ef|ot|nt)\>"

# Short and long options.
color brightmagenta "[[:blank:]]-[A-Za-z]\>" "[[:blank:]]--[A-Za-z-]+\>"

# Common commands.
color brightblue "\<(awk|cat|cd|ch(grp|mod|own)|cp|cut|echo|env|grep|head|install|ln|make|mkdir|mv|popd|printf|pushd|rm|rmdir|sed|set|sort|tail|tar|touch|umask|unset)\>"
#color normal "[.-]tar\>"

# Basic variable names (no braces).
color brightred "\$[-0-9@*#?$!]" "\$[[:alpha:]_][[:alnum:]_]*"
# More complicated variable names; handles braces and replacements and arrays.
color brightred "\$\{[#!]?([-@*#?$!]|[0-9]+|[[:alpha:]_][[:alnum:]_]*)(\[([[:space:]]*[[:alnum:]_]+[[:space:]]*|@)\])?(([#%/]|:?[-=?+])[^}]*\}|\[|\})"

# Comments.
color cyan "(^|[[:space:]])#.*"

# Strings.
color brightyellow ""(\\.|[^"])*"" "'(\\.|[^'])*'"

# Trailing whitespace.
color ,green "[[:space:]]+$"
end_of_content

cat << end_of_content >> ~/.nanorc
include "~/.nano/sh.nanorc"
end_of_content