# ========================================================================== #
# Environment                                                                #
# ========================================================================== #

ROOTDIR="/Users/rc"
WORKSPACEDIR="$ROOTDIR/Workspace"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TERM=xterm-256color
export CLICOLOR=1
export EDITOR='nvim'
export HOMEBREW_NO_AUTO_UPDATE=1
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/usr/sbin/:/sbin/:/bin:/opt/homebrew/sbin
export PATH=/Applications/Sublime\ Text.app/Contents/SharedSupport/bin:$PATH # sublime text
export PATH=/usr/local/go/bin:$PATH # go
export PATH=/Users/rc/go/bin:$PATH # go
export PATH=$WORKSPACEDIR/.cargo/bin:$PATH # rust
export PATH="$PATH"
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

# ========================================================================== #
# Functions                                                                  #
# ========================================================================== #

# Inject current kube context into PS1
__kube_ps1()
{
    KUBECTL_CONTEXT=$(kubectl config current-context)
    if [ -n "$KUBECTL_CONTEXT" ]; then
        export PS1="(kubectl: ${KUBECTL_CONTEXT}) "
    fi
}

# ========================================================================== #
# Aliases                                                                    #
# ========================================================================== #

# General
alias c='clear'
alias cw="cd $WORKSPACEDIR"
alias cww="cd $WORKSPACEDIR/rw/mono"
alias opf='open .'
alias reload='source ~/.zshrc'

# Docker
alias dcl='docker container logs -f --tail 500'
alias dce='docker container exec'
alias dcps='docker container ps -a'
alias dcbr='docker run -it $(docker build -q .)'
alias dcbrm='docker run --rm -it $(docker build -q .)'

# Tools
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
alias pport=lsof -ti:$1
alias flushdns='sudo dscacheutil -flushcache;sudo killall -HUP mDNSResponder'
alias httpserv='python3 -m http.server 8000 --bind 127.0.0.1'
alias randname='python -c "
from haikunator import Haikunator
print(Haikunator().haikunate())
"'
alias killport=__kill_port
__kill_port() {
  kill -9 $(lsof -ti:$1)
}

# k8s
alias kubectx=__kube_ps1
alias kc='kubectl -n'

# pyenv
alias av='pyenv activate'
alias dv='pyenv deactivate'

# ========================================================================== #
# Runtime                                                                    #
# ========================================================================== #

# Disable hostname completion
zstyle ':completion:*' hosts off 

# Enable pyenv & pyenv-virtualenv
eval "$(pyenv init --path)"
eval "$(pyenv init -)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# kubectl
[[ $commands[kubectl] ]] && source <(kubectl completion zsh)

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \
  \. "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \
  \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# gcloud sdk
if [ -f '/Users/rc/google-cloud-sdk/path.zsh.inc' ]; \
  then . '/Users/rc/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/rc/google-cloud-sdk/completion.zsh.inc' ]; \
  then . '/Users/rc/google-cloud-sdk/completion.zsh.inc'; fi

# direnv
eval "$(direnv hook zsh)"
