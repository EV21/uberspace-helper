#!/usr/bin/env bash

mkdir --parents ~/.zsh/antigen
curl -L# git.io/antigen > ~/.zsh/antigen/antigen.zsh

cat << 'end_of_content' >> ~/.zshrc
source ~/.zsh/antigen/antigen.zsh

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle heroku
antigen bundle pip
antigen bundle lein
antigen bundle command-not-found

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle zsh-users/zsh-completions

# Load the theme.
antigen theme robbyrussell

# Tell Antigen that you're done.
antigen apply
end_of_content

chsh --shell /bin/zsh
exec /usr/bin/env zsh