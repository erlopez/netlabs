#!/usr/bin/env bash

# History config
export HISTSIZE=10000                    # The maximum number of commands to remember on the history list. -1 is unlimited
export HISTFILESIZE=-1                   # The maximum number of lines contained in the history file. -1 is unlimited
export HISTCONTROL=ignoredups:erasedups  # Avoid duplicates
shopt -s histappend                      # When the shell exits, append to the history file instead of overwriting it


# Prompt
TLINE=$(printf "\x1b(0\x6c\x71\x71\x1b(B" )
BLINE=$(printf "\\[\\e(0\\]\x6d\x71\\[\\e(B\\]" )
BULLET=$(printf '%b' "$(tput setaf 118)" "\u2219" "$(tput sgr0)" )

function myInfo()
{
    local ips=$(ip -brief addr |  grep -E 'UP +[0-9]' | sed -E 's,(eth[^ @]+|br[^ @]+).* ([0-9.]+)/.*,\1:\2  ,' | grep -E '(eth|br)' | tr -d '\n')
    printf "\n\033[1;36m${TLINE}${BULLET} ${HOSTNAME}\033[1;36m %s\033[0m\n"  "$ips"

}

export PROMPT_COMMAND=myInfo
export PS1="\[\e[01;36m\]${BLINE} \[\e[01;35m\]\u\[\e[01;32m\]\$\w>\[\e[00m\] "


# Sugar aliases
alias grep='grep --color=auto'
alias ls='ls --color=auto'
alias ll='ls -lavh --group-directories-first'
alias dir='ll'
alias nano="/bin/nano -S -Y sh "
alias md="mkdir -p"
alias cls=clear
alias relo="source ~/.bashrc"
alias e="nano ~/.bashrc"

# Pretty print constants
N="$( printf "\033[0m" )"     #normal
W="$( printf "\033[1;37m" )"  #white
KWORDS="default|accept|drop|reject|input|output|forward|postrouting|prerouting|eth[0-9]+|[1-9][0-9.]+{6,}"
HILITE="| sed -E 's/(${KWORDS})/${W}\\1${N}/gi'" # highlight keywords
INDENT="| sed -E 's/(^|\n)/\1    /'"
PRETTY="${INDENT} ${HILITE}"


# always sudo commands
alias ip="sudo $(which ip)"
alias iptables="sudo $(which iptables)"
alias reboot="sudo $(which reboot)"
alias tcpdump="sudo $(which tcpdump)"
alias systemctl="sudo $(which systemctl)"
alias networkctl="sudo $(which networkctl)"
alias journalctl="sudo $(which journalctl)"

# opinionated network aliases
alias tcp="tcpdump -i any -ln"
alias ports="sudo netstat -tulpn"
alias a="ip addr ${HILITE}"
alias l="ip link ${HILITE}"
alias r="ip route ${HILITE}"
alias i="echo 'IPs:'; ip -brief addr ${PRETTY}; echo 'Routes:'; ip route ${PRETTY}"
alias m="echo 'MANGLE Rules:'; sudo iptables -t mangle -nvL PREROUTING --line-numbers ${PRETTY}; \
                            sudo iptables -t mangle -nvL POSTROUTING --line-numbers ${PRETTY}"
alias n="echo 'NAT Rules:'; sudo iptables -t nat -nvL PREROUTING --line-numbers ${PRETTY}; \
                            sudo iptables -t nat -nvL POSTROUTING --line-numbers ${PRETTY}"
alias f="echo 'Filter Rules:'; sudo iptables -nvL INPUT --line-numbers ${PRETTY}; \
                               sudo iptables -nvL FORWARD --line-numbers ${PRETTY}; \
                               sudo iptables -nvL OUTPUT --line-numbers ${PRETTY}"
alias t="m; n; f"
alias d="sudo journalctl -f | grep -iE '(dns|dhcp)'"


# apt
alias inst='sudo apt install'
alias uninst='sudo apt remove'
alias list='apt search'


# Show installed apt packages
function sho()
{
   if [[ ! -z "$1" ]]; then
      dpkg  --get-selections | grep  -E "$1"
   else
      dpkg  --get-selections
   fi

}

# Show all history or grep by optional argument
function h()
{
   echo "--> $1"
   if [[ ! -z "$1" ]]; then
      history | grep  -E "$1"
   else
      history
   fi
}

# Show all processes or grep by optional argument
function p()
{
   echo "--> $1"
   if [[ ! -z "$1" ]]; then
      ps -ef | grep  -E "$1"
   else
      ps -ef
   fi
}

function showHelp()
{
    cat <<EOF
    Alias               Description
    --------------------------------------------------------------------------------
    h [string]          Prints history filtered by optional [string]
    p [string]          Prints processes filtered by optional [string]

    sho [string]        Prints installed apt packages filtered by optional [string]
    inst <packages>     'sudo apt install' install packages
    uninst <package>    'sudo apt remove'  uninstall packages
    list [string]       'apt search' packages filtered by optional [string]

    relo                'source ~/.bashrc'  reloads .bashrc changes
    e                   'nano ~/.bashrc'  edits .bashrc

    tcp                 'sudo tcpdump -i any -ln' monitor traffic on all interfaces
    ports               'sudo netstat -tulpn' show ports in use
    a                   Pretty print for 'ip addr'
    l                   Pretty print for 'ip link'
    r                   Pretty print for 'ip route'
    i                   Compact pretty print of IP addresses and routes

    m                   Pretty print for Mangle rules
    n                   Pretty print for NAT rules
    f                   Pretty print for filter rules
    t                   Compact pretty print for Mangle, NAT and filter tables rules
    d                   Show DNS/DHCP log activity 'sudo journalctl -f | grep -iE "(dns|dhcp)"'

    ?                   Show this help
EOF
}

alias ?=showHelp




