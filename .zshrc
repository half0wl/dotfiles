# Environment
export TERM=xterm-256color
export CLICOLOR=1
export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export GOPATH="${HOME}/Workspace/golang"
export PATH=$PATH:$GOPATH/bin

# Aliases
alias c='clear'
alias cw='cd ~/Workspace'
alias opf='open .'
alias reload='source ~/.zshrc'
alias flushdns='sudo dscacheutil -flushcache;sudo killall -HUP mDNSResponder'
alias sub='sublime'
alias httpserv='python3 -m http.server 8000 --bind 127.0.0.1'
alias psql='/Applications/Postgres.app/Contents/Versions/10/bin/psql'
alias sc='scrapy crawl'

# Docker aliases
alias dcl='docker container logs -f --tail 500'
alias dce='docker container exec'
alias dcps='docker container ps -a'

# Python
alias cv='virtualenv --python=python3 .venv-py3 && av'  # python3 as default
alias av='source .venv-py3/bin/activate'
alias cv2='virtualenv --python=python .venv-py2 && av2'
alias av2='source .venv-py2/bin/activate'
alias dv='deactivate'

# Source Prezto
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

# Disable hostname completion
zstyle ':completion:*' hosts off

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

