# efzf.zsh -- Zsh widgets for efzf
#
# Copyright (C) 2026 Yoshinari Nomura
#
# Author: Yoshinari Nomura <nom@quickhack.net>
# URL: https://github.com/yoshinari-nomura/efzf
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

efzf-select-widget() {
  zle -I

  local selection=$(efzf -a select) || return
  if [[ -n "$selection" ]]; then
    LBUFFER+="${(q)selection}"
  fi

  zle reset-prompt
}

zle -N efzf-select-widget
# bindkey '^O' efzf-select-widget

efzf-history-incremental-search-backward() {
  # man zshbuiltins
  # -l list on standard output
  # -n suppresses event numbers
  # -r reverse the order
  # awk ... remove duplicated entries

  zle -I
  local selection=$(fc -nlr 1 | awk '!a[$0]++' | efzf) || return

  BUFFER="$selection"
  CURSOR=$#BUFFER
  zle reset-prompt
}

zle -N efzf-history-incremental-search-backward
# bindkey '^R' efzf-history-incremental-search-backward
