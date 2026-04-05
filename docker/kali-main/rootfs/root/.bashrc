# ~/.bashrc - kali-main container shell config

# ── History ────────────────────────────────────────────────────────
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%F %T  "
shopt -s histappend

# ── Prompt ─────────────────────────────────────────────────────────
PS1='\u@\h:\w\$ '

# ── PATH ───────────────────────────────────────────────────────────
[[ -d /opt/lab/tools/binaries ]] && PATH="/opt/lab/tools/binaries:${PATH}"
export PATH

# ── Environment ────────────────────────────────────────────────────
export LAB_ROOT="${LAB_ROOT:-/opt/lab}"

# ── Aliases - navigation ──────────────────────────────────────────
alias ll='ls -lhA'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'

# ── Aliases - color ───────────────────────────────────────────────
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# ── Aliases - operator ────────────────────────────────────────────
alias serve='python3 -m http.server 8000'
alias upload='python3 -m uploadserver 9090'
alias listen='rlwrap nc -lvnp'
alias myip='ip -4 addr show | grep -oP "(?<=inet\s)\d+(\.\d+){3}" | grep -v 127.0.0.1'
alias ports='ss -tlnp'
alias nse='ls /usr/share/nmap/scripts/ | grep'
alias wl='ls /usr/share/wordlists/'
