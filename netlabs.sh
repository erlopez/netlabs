#!/bin/bash
# -------------------------------------------------------------------------------
#  netlabs.sh - a tool for building virtual networks on a Linux VM.
#
#  MIT License
#
#  Copyright (c) 2024 Edwin R. Lopez, https://lopezworks.info
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in all
#  copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#  SOFTWARE.
# -------------------------------------------------------------------------------

# cd into this script's folder
cd $(dirname $0) || exit

THIS_SCRIPT="$(pwd)/$(basename $0)"                          # absolute path to this script

IMAGE_NAME=netlabs                                           # base image name (template container)
IMAGE_USER=user                                              # default account created in the container (id=1000)
BRIDGE_PREFIX="netlabs-br"                                   # prefix used for all net bridges
TMUX_SESSION_NAME=NETLABS                                    # prefix used for netlabs-generated tmux sessions
IPTABLES_RULES_FILE=/etc/netlabs.iptables.rules.v4           # store masquerading rule for netlabs bridge after host vm reboots
HOSTVM_IP=192.168.200.1                                      # IP given to the HOST side of the network (aka the internet gateway)

TMP_DIR=/tmp/netlabs                                         # hold temp files to support network builds
OPEN_TERMINAL_TABS_SCRIPT=${TMP_DIR}/open-terminal-tabs.sh   # temp generated script to launch terminal with host shells tabs
HOSTS_FILE=${TMP_DIR}/netlabs.hosts                          # temp holds the list of hostnames created after build


# map variable: keys hold unique list IDs created bridges to avoid creating duplicate bridges
# used by mkbridges()
declare -A CREATED_BRIDGE_IDS


# -------------------------------------------------------------------------------
# Pretty print functions
# -------------------------------------------------------------------------------
function out() { printf "\033[1;32m$*\033[0m\n" 1>&2; }
function err() { printf "\033[1;31m$*\033[0m\n" 1>&2; }


# -------------------------------------------------------------------------------
#  Make this host system behave like a gateway by adding  masquerade on default
#  network interface and enable IPv4 forwarding
# -------------------------------------------------------------------------------
function gwsetup()
{
    # 1. Enable Ipv4 forwarding
    #    This sets net.ipv4.ip_forward=1 permanently in /etc/sysctl.conf and reloads the config
    out "Enabling IPv4 forwarding ..."
    sudo sh -c "sed -E 's/^#?(net.ipv4.ip_forward)=[01]/\\1=1/' -i /etc/sysctl.conf && sysctl -p"

    if [[ "$(cat /proc/sys/net/ipv4/ip_forward)" = "0" ]]; then
        err "Could not enable IPv4 forwarding."
        exit
    fi

    # 2. Add masquerading on default route's network interface
    #    to allow VMs in this host to go to the internet using the host's IP
    out "Setting netlabs iptables rules ..."

    # Determine if the NETLABS_RULE rule exist already, if so, skip operation and bail
    local ruleExist=$(sudo iptables -t nat -nvL | grep NETLABS_RULE | wc -l)

    if [[ ${ruleExist} != "0" ]]; then
        echo "    Already setup, skipping"
        return
    fi

    # Do we need to install iptables-persistent?
    out "Installing iptables-persistent ..."

    if ! (which iptables-save > /dev/null) ; then
        # These instructions are to prevent the "install iptables-persistent" below
        # from interactively asking if we want to save the current iptable rules
        echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
        sudo debconf-show iptables-persistent

        sudo apt update && sudo apt install -y iptables-persistent

    else
        echo "    Already installed, continuing."

    fi


    # Determine the default route network interface name
    local defaultIface=$(ip route show default | grep -oP 'dev \K[^ ]+')

    if [[ -z ${defaultIface} ]]; then
        err "Could not determine default network interface route."
        exit
    fi

    # Add our rule
    sudo iptables -t nat -A POSTROUTING  -o ${defaultIface} -j MASQUERADE -m comment --comment NETLABS_RULE

    sudo sh -c "iptables-save > ${IPTABLES_RULES_FILE}"  # save rules

    # debugging
      sudo iptables -t nat -F                      # flush
    #   sudo iptables -t nat -nvL  --line-numbers    # list


    # Create or append (tee -a) to /etc/rc.local iptables-restore
    cat <<EOF | sudo tee -a /etc/rc.local; sudo chmod +x /etc/rc.local
#!/bin/sh
# Restore IP tables
$(which iptables-restore) < ${IPTABLES_RULES_FILE}

EOF

    # Sanity check
    # Ensure the rc-local service is enabled, which is for most distros
    local rcLocalEnabled
    local rcLocalRunning
    sudo systemctl enable rc-local.service &> /dev/null && rcLocalEnabled=1
    sudo systemctl start rc-local.service &> /dev/null
    sudo systemctl status rc-local.service &> /dev/null && rcLocalRunning=1

    [[ -z ${rcLocalEnabled} ]] && err "WARNING: rc-local.service failed to enable, please make sure it is enabled"
    [[ -z ${rcLocalRunning} ]] && err "WARNING: rc-local.service is not running, please make sure it is started"

}


# -------------------------------------------------------------------------------
#  Install lxd package
# -------------------------------------------------------------------------------
function install()
{
    # if lxd already installed, bail
    if which lxc ; then
        out "lxd already installed."
        return
    fi


    # update and instal lxd
    out "Updating repos"
    sudo apt update

    local id=$(cat /etc/os-release | grep -oP '^ID=\K.+')
    local idlike=$(cat /etc/os-release | grep -oP '^ID_LIKE=\K.+')

    if [[ $id = "linuxmint" && $idlike = "debian" ]]; then
        #LMDE
        out "Installing LXD for LinuxMint Debian edition"

        sudo apt -y install lxd

    elif [[ $id = "debian" ]]; then
        #debian
        out "Installing LXD for Debian"
        sudo apt -y install lxd

    elif [[ $id = "linuxmint" ]]; then
        #linux mint
        out "Installing Snap & LXD for LinuxMint"
        sudo rm /etc/apt/preferences.d/nosnap.pref
        sudo apt -y install snapd  # ubuntu
        sudo snap install lxd

    elif [[ $id = "ubuntu" ]]; then
        #ubuntu
        out "Installing LXD for Ubuntu"
        sudo snap install lxd
    else
        err "I don't know how to install lxd on your OS: $os"
        exit
    fi

    # allow used to manage containers w/o sudo
    out "Adding user to lxd group"
    if [[ -n "${SUDO_USER}" ]]; then
         sudo usermod -aG lxd $SUDO_USER
    elif [[ "$(id -u)" != "0" ]]; then
         sudo usermod -aG lxd $USER
    else
        err "install() Cannot determine real user"
        exit
    fi

    # to enable rw volumes on containers
    out "Remaping root to user ID 1000"
    echo 'root:1000:1' | sudo tee -a /etc/subuid /etc/subgid

    echo
    out "NOTE: You need to logout and log back in to refresh your groups."
    out "      After login run 'id' and if your user doesn't have the 'lxd'"
    out "      group, you need to reboot your system before running the init"
    out "      step."
}


# -------------------------------------------------------------------------------
#  Init lxd
# -------------------------------------------------------------------------------
function init()
{
    # if already inited, bail
    if sudo lxd init --dump | grep lxdbr0 &> /dev/null ; then
        out "lxd already initialized."
        return
    fi

    # init
    out "Initializing lxd for first time ..."
    cat <<EOF | sudo lxd init --preseed
config: {}
networks:
- config:
    ipv4.address: auto
    ipv6.address: auto
  description: ""
  name: lxdbr0
  type: ""
  project: default
storage_pools:
- config: {}
  description: ""
  name: default
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
projects: []
cluster: null

EOF


}


# -------------------------------------------------------------------------------
#  Setup lxd base image
# -------------------------------------------------------------------------------
function setup()
{
    # demote back to user if running with sudo
    if [[ "$(id -u)" = "0" ]]; then
        if [[ -n "${SUDO_USER}" ]]; then
            sudo -u ${SUDO_USER} "./$(basename $0)" setup  # run this function w/o sudo
            return
        else
            err "setup() Cannot determine real user"
            exit
        fi
    fi


    # delete previous image
    out "Deleting old image ${IMAGE_NAME} ..."
    clean
    lxc delete "${IMAGE_NAME}" --force

    # create new image
    out "Creating base image ${IMAGE_NAME} ..."
    lxc init ubuntu:24.04 "${IMAGE_NAME}"
    lxc config set "${IMAGE_NAME}" raw.idmap "both 1000 1000"  # for rw share folders
    lxc config set "${IMAGE_NAME}" raw.lxc "lxc.sysctl.net.ipv4.ip_forward=0" # set ip_forward to normal, disabled


    lxc start "${IMAGE_NAME}"
    #lxc exec "${IMAGE_NAME}" --  userdel -f ubuntu
    lxc exec "${IMAGE_NAME}" --  useradd --uid $(id -u) --create-home --shell /bin/bash ${IMAGE_USER}
    lxc exec "${IMAGE_NAME}" --  usermod -aG sudo ${IMAGE_USER}
    lxc exec "${IMAGE_NAME}" --  sh -c "echo \"root:'\" | chpasswd"
    lxc exec "${IMAGE_NAME}" --  sh -c "echo \"${IMAGE_USER}:'\" | chpasswd"
    lxc exec "${IMAGE_NAME}" --  sh -c "echo '%sudo ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/nopasswd"


    # disable networkd-wait-online service prevent slow boot due to uninitialized network interfaces
    lxc exec "${IMAGE_NAME}" -- systemctl disable systemd-networkd-wait-online.service
    lxc exec "${IMAGE_NAME}" -- systemctl mask systemd-networkd-wait-online.service

    # install other tools
    lxc exec "${IMAGE_NAME}" -- sh -c "apt update && apt install -y lighttpd net-tools socat tree"

    # mount external user folder
    lxc config device add "${IMAGE_NAME}" mystorage disk source="$(pwd)/user"  path="/home/${IMAGE_USER}"

    # close base image
    lxc stop "${IMAGE_NAME}"

    # lxc delete  "${IMAGE_NAME}"  --force

    # lxc exec "${IMAGE_NAME}" -- su --login ${IMAGE_USER}

    # init .ssh folder
    local sshDir=./user/.ssh
    out "Initializing ${sshDir} files ..."
    if [[ ! -d ${sshDir} ]]; then
        mkdir -p ${sshDir}
        chmod 700 ${sshDir}
        ssh-keygen -t ecdsa -f ${sshDir}/id_ecdsa -P '' -C "${IMAGE_USER}@${IMAGE_NAME}"
        cp ${sshDir}/id_ecdsa.pub ${sshDir}/authorized_keys
        chmod 600 ${sshDir}/authorized_keys
        out "  OK"
    else
        out "  ${sshDir} already exists, skipping."
    fi

}


# -------------------------------------------------------------------------------
#  Create necessary network bridges
# -------------------------------------------------------------------------------
function mkbridges()
{
    local id

    # Split into network IDs
    local bridgeIds=( ${1//,/ })   # // --> replace all, ';' for ' '
    unset bridgeIds[0]             # delete first element in array, the hostname element

    # Sanity check, make sure we are not creating a host w/o network
    if [[  ${#bridgeIds[@]} = 0 ]]; then
        err "At least one network is required for: $1"
        exit
    fi

    # Create network bridges for all IDs, if not done already
    for id in ${bridgeIds[@]}; do

        # Make sure network id is a number
        if [[  ! ${id} =~ ^[0-9]+$  ]]; then
            err "Invalid network ID in: $1"
            exit
        fi

        # Create bridge, only if not done already
        if [[ -z ${CREATED_BRIDGE_IDS[$id]} ]]; then
            out "Creating network ${BRIDGE_PREFIX}${id} ..."
            sudo ip link add name "${BRIDGE_PREFIX}${id}" type bridge || exit

            # Add host IP for bridge 0
            if [[ ${id} = "0" ]]; then
                out "Setting network ${BRIDGE_PREFIX}${id} host IP to ${HOSTVM_IP} ..."
                sudo ip address add ${HOSTVM_IP}/24 dev "${BRIDGE_PREFIX}${id}" || exit
            fi

            # Bring bridge up
            sudo ip link set "${BRIDGE_PREFIX}${id}" up

            CREATED_BRIDGE_IDS[$id]=true # remember we already created this bridge
        fi

    done

}

# -------------------------------------------------------------------------------
#  Create instance
# -------------------------------------------------------------------------------
function mkinstance()
{
    local n=0
    local hostname=$( echo ${1} | cut -f1 -d, )
    local bridgeIds=( ${1//,/ })   # // --> replace all, ';' for ' '
    unset bridgeIds[0]             # delete hostname element, first in array


    # create instance
    out "Creating instance ${hostname} ..."
    lxc copy netlabs "${hostname}"
    lxc config set "${hostname}" user.netlabs true      # tag the container, so we know it was built by us
    lxc config set "${hostname}" security.nesting true  # allows running 'ip netns exec' inside container otherwise you get: mount /sys: Operation not permitted

    # Create network bridges for all IDs, if not done already
    for id in ${bridgeIds[@]}; do
        local br="${BRIDGE_PREFIX}${id}"
        out "  Attaching eth${n} to network ${br} ..."
        lxc config device add "${hostname}" "eth${n}" nic nictype=bridged parent="${br}" name="eth${n}"
          # ^^ see https://documentation.ubuntu.com/lxd/en/stable-5.0/reference/devices_nic/#devices-nic

        n=$((n+1))
    done

    # start instance
    lxc start ${hostname}

    # update hosts
    lxc exec "${hostname}" -- sh -c "echo '127.0.0.1 ${hostname}' >> /etc/hosts"

    # configure web page
    lxc exec "${hostname}" -- sh -c "echo 'hello from ${hostname}' > /var/www/html/index.html"


    # Save hostname to list so tmux can open terminal to host later
    mkdir -p "${TMP_DIR}"
    echo "${hostname}" >> "${HOSTS_FILE}"

}


# -------------------------------------------------------------------------------
#  Remove previous containers and network bridges
# -------------------------------------------------------------------------------
function clean()
{
    # Kill tmux terminals and erase temp files
    tkill
    rm -rf ${TMP_DIR}

    # Remove existing netlabs instances (if any)
    local instance
    local instances=( $(lxc ls "user.netlabs=true" -c n --format csv) )

    for instance in ${instances[@]}; do
        out "Deleting instance ${instance} ..."
        lxc stop ${instance}
        lxc delete ${instance} --force 2> /dev/null
    done

    # Remove existing host netlab bridges (if any)
    local bridge
    local bridges=( $(ip link | grep -oP "${BRIDGE_PREFIX}\\d+") )

    for bridge in ${bridges[@]}; do
        out "Deleting network ${bridge} ..."
        sudo ip link del ${bridge}
    done

    local sshDir=./user/.ssh
    if [[ -d ${sshDir} ]]; then
        out "Removing old known_hosts ..."
        rm -f "${sshDir}/known_hosts"*
    fi

}


# ---------------------------------------------------------------
#  Builds a virtual network
# ---------------------------------------------------------------
function build()
{
    # delete previous network setup
    clean

    # parse network arguments
    local host

    for host in $*; do
        echo "Building $host .."
        mkbridges "$host"
        mkinstance "$host"
    done

    out "Done."
}


# ---------------------------------------------------------------
#  Kill tmux netlab session
# ---------------------------------------------------------------
function tkill()
{
    local session
    local sessions=( $(tmux ls -F '#{session_name}' | grep -oE "${TMUX_SESSION_NAME}.*" ) )

    out "Killing ${TMUX_SESSION_NAME} tmux sessions ..."
    for session in ${sessions[@]}; do
        echo "    ${session}"
        tmux kill-session -t "${session}"  2> /dev/null
    done

    echo "    Done."
}



# ---------------------------------------------------------------
#  Start tmux sessions for hosts in the background
# ---------------------------------------------------------------
function tmuxStartSessions()
{
    # If the tmux session does not exist, create it
    if ! tmux has-session -t ${TMUX_SESSION_NAME} 2> /dev/null; then

        if [[ ! -f "${HOSTS_FILE}" ]]; then
            err "No ${HOSTS_FILE} file found. Have you run the build command yet?"
            exit
        fi

        # Build tmux command string layouts
        local host
        local hosts=( $(cat "${HOSTS_FILE}" ) )
        local thisScript="./$(basename ${THIS_SCRIPT})"
        local cmd="tmux new-session -s ${TMUX_SESSION_NAME} -d ${thisScript} shell mux"
        local tileLayout="select-layout tiled \\; set-hook -g client-resized 'select-layout tiled'"

        for host in ${hosts[@]}; do
             # append to full tile tmux command
             cmd="${cmd} \\; splitw -h ${thisScript} shell ${host}"

             # start standalone dual-term tmux session for host
             eval "tmux new-session -s ${TMUX_SESSION_NAME}_${host^^} -d ${thisScript} shell ${host} \\; \
                   splitw -v ${thisScript} shell ${host} \\; ${tileLayout}"

        done

        # add auto tile layout directives
        cmd="${cmd} \\;  ${tileLayout}"

        #echo "====>  ${cmd}"

        # start tmux tile session with all host terminals in it
        eval "${cmd}"

    fi

}

# ---------------------------------------------------------------
#  Create default tmux config
# ---------------------------------------------------------------
function conf()
{
    # Config tmux key bindings
    # see https://hamvocke.com/blog/a-guide-to-customizing-your-tmux-conf/
    local configFile=~/.tmux.conf
    local answer

    if [[ -f ${configFile} ]]; then
        read -p "Overwrite ${configFile}? [y/N] " answer
        [[ ${answer^^} != "Y" ]] && echo "Aborted" && return
    fi

    cat <<'EOF' > ${configFile}
        # remap prefix from 'C-b' to 'C-a'
        unbind C-b
        set-option -g prefix C-a
        bind-key C-a send-prefix

        # split panes h and v
        bind a select-layout tiled
        bind h split-window -h
        bind v split-window -v
        unbind '"'
        unbind %

        # switch panes using Alt-arrow without prefix
        bind -n M-Left select-pane -L
        bind -n M-Right select-pane -R
        bind -n M-Up select-pane -U
        bind -n M-Down select-pane -D

        # Enable mouse control (clickable windows, panes, resizable panes)
        set -g mouse on

        # Make middle-mouse-click paste from the primary selection (without having to hold down Shift).
        #bind-key -n MouseDown2Pane run "tmux set-buffer -b primary_selection \"$(xsel -o)\"; tmux paste-buffer -b primary_selection; tmux delete-buffer -b primary_selection"

EOF
        out "${configFile} saved."

}

# ---------------------------------------------------------------
#  Open console terminal to container
#  $1  hostname to connect to
# ---------------------------------------------------------------
function console()
{
    shell $1 true
}

# ---------------------------------------------------------------
#  Open direct terminal to container
#  $1  hostname to connect to
#  $2  if "true" connect as console, otherwise use regular shell
# ---------------------------------------------------------------
function shell()
{
    if [[ ! -f "${HOSTS_FILE}" ]]; then
        err "No ${HOSTS_FILE} file found. Have you run the build command yet?"
        exit
    fi

    # Sanity check: validate host name
    local hostname=( $(cat "${HOSTS_FILE}" | grep -m1 "$1") )

    if [[ -z "${hostname}" ]]; then
        err "Hostname '$1' not found. "
        err "Try one of these: $( echo $(cat "${HOSTS_FILE}") ) "
        exit
    fi

    # Determine if we are connecting to a console of a normal shell
    local lxcCommand="$(which lxc) exec "${hostname}" -- su --login ${IMAGE_USER}"
    [[ $2 = "true" ]] && lxcCommand="$(which lxc) console ${hostname}"


    # Continue to reconnect until user presses ctrl-c
    while true;  do
        ${lxcCommand}
        sleep 2
    done

}


# ---------------------------------------------------------------
#  Attach to tmux sessions in the current terminal. To detach
#  use ctrl-a + d
# ---------------------------------------------------------------
function attach()
{
    terms attach
}


# ---------------------------------------------------------------
#  Open tabbed terminal window
#  $1  Optional: When set to "attach" tmux is attached on the
#      current terminal instead of opening a terminal window
# ---------------------------------------------------------------
function terms()
{
    # Start tmux sessions if not already done
    tmuxStartSessions

    if [[ $1 = "attach" ]]; then
        tmux "attach" -t "${TMUX_SESSION_NAME}"
        return
    fi

    # Determine terminal program
    local terminal

    which gnome-terminal &> /dev/null && terminal=gnome-terminal
    which mate-terminal &> /dev/null && terminal=mate-terminal

    if [[ -z ${terminal} ]]; then
        err "Cannot determine terminal application."
        exit
    fi


    # Save tabs spawning script
    local host
    local hosts=( $(cat "${HOSTS_FILE}") )

    echo "#!/bin/sh" > "${OPEN_TERMINAL_TABS_SCRIPT}"

    for host in ${hosts[@]}; do
        echo "${terminal} --tab -t '${host}' -- tmux attach -t '${TMUX_SESSION_NAME}_${host^^}' " >> "${OPEN_TERMINAL_TABS_SCRIPT}"
    done

    echo "${terminal} --tab -t '${TMUX_SESSION_NAME}' -- tmux attach -t '${TMUX_SESSION_NAME}' " >> "${OPEN_TERMINAL_TABS_SCRIPT}"

    chmod +x "${OPEN_TERMINAL_TABS_SCRIPT}"

    #cat "${OPEN_TERMINAL_TABS_SCRIPT}"

    # run script and open terminals
    ${terminal} --hide-menubar  --  "${OPEN_TERMINAL_TABS_SCRIPT}"

}



# -------------------------------------------------------------------------------
#  Copy netlabs folder to a VM for testing; crutch to assist during development;
#  not a functional part of this tool.
# -------------------------------------------------------------------------------
function test()
{
    local target
    target=monas
    target=debian
    target=mints
    target=menta
    target=mates

    rsync -av -e ssh ../netlabs/ ${target}:netlabs
}


# -------------------------------------------------------------------------------
#  Main
# -------------------------------------------------------------------------------

# Call function matching argument
if [[ $(type -t $1) = "function" ]]; then
    cmd=$1
    shift
    ${cmd} "$@"
else
    [[ -n $1 ]] && err "Invalid command: '$1' \n"

    cat <<EOF
    Netlabs v0.1
    (c) 2024 Edwin R. Lopez

    A tool to create virtual networks and learn Linux networking skills.

    It is recommended you use this tool inside a VM or a spare machine you use
    for experimenting with things. This tool was tested on Linux Mint 22 Mate edition
    and Linux Mint Debian 6 edition, but it is likely to run in other Debian distros
    such as Ubuntu.

    Requirements:

      - To facilitate working with terminals, this tool needs the following packages:

        sudo sh -c "apt update && apt -y install tmux"


      - Optional: To avoid entering the sudo password over and over, grant
        yourself sudo ALL by running:

        f=/etc/sudoers.d/\$USER-sudo-nopasswd; sudo sh -c "echo '\$USER ALL=(ALL) NOPASSWD: ALL' | tee \$f && chmod 640 \$f"


    General usage:

        $0  <command>

    Commands:

        gwsetup                          Configure host as internet gateway.
        install                          Install LXD package.
        init                             Initialize LXD environment.
        setup                            Create LXD base ubuntu image.
        build  host,net[,net,..]  ...    Build/re-build a lab network.
        clean                            Deletes current lab network (if any).
        conf                             Create tmux default config (optional).
        terms                            Open tmux windows to all lab network hosts
                                         in a separate desktop graphical window.
        attach                           Attach to tmux windows to all lab network hosts in
                                         the current terminal; use <ctrl-a> + d to detach.
        shell <host>                     Connect to a given host shell, exit by
                                         pressing <ctrl-d> + <ctrl-c>.
        tkill                            Kill all tmux sessions.


    To initialize your LXD environment for the first time run:

        $0 gwsetup   # give VMs internet access

        $0 install   # after this logout and login to refresh groups
                     # if after login typing 'id' doesn't show the group 'lxd'
                     # you need to reboot your system
        $0 init
        $0 setup
        $0 conf      # optional, create default tmux config if you have none


    To build a lab network, use the build command as follows:

        $0 build  router,0,1,7  bob,1  jim,1  ws,7

        This creates a network as follows:

        +---------+             +--------+ eth1       eth0 +-----+
        | Gateway |----net0-----| router |------net1--+----| bob |
        +---------+        eth0 +----+---+            |    +-----+
                                     | eth2           |
                                     |                |
                                    net7              |    +-----+
                                     | eth0           +----| jim |
                                   +----+             eth0 +-----+
                                   | ws |
                                   +----+

        The build command takes arguments formatted as follows:

            hostname,0,1,2,3[,n...]
            |        | | | |
            |        | | | +--> network segment eth3 is connected to
            |        | | +--> network segment eth2 is connected to
            |        | +--> network segment eth1 is connected to
            |        +--> network segment eth0 is connected to
            +--> name of a host in the network

        There should not be any space between the hostname and
        its comma-separated network identifiers. Network identifiers
        don't need to be sequential; this is a valid host definition

            foobar,0,4,7,1

        Hosts with matching network identifiers are connected
        as if a network switch exists between them.

        Except for the Gateway, all network interfaces in all machines
        are not initialized. Is your job to assign IP address, routes
        and firewalls as desired. The Gateway (net0) always has the
        IP 192.168.200.1 and works as your "Internet Gateway" if
        internet access is necessary.

        Network ID numbers are arbitrary. Network 0 is always present
        and connected to Gateway.

        Running the build command destroys the previous network before
        creating a new one.

        If you reboot your system, you need to build your network again.

        All the machines have the account '${IMAGE_USER}' (id 1000). The home
        folder for this user is mapped to the external folder user/ thus all
        machines share the same .ssh, .bashrc, .bash_history and any
        other file created in the user's home folder. When the network is
        destroyed and created, files in the /home/${IMAGE_USER} folder persist.

        The password for the "${IMAGE_USER}" and "root" accounts is "'",
        (a single quote) however, because all machines share the same .ssh
        files, it is possible ssh between them without a password.

        All machines have a basic web server on port 80 which can be used
        for testing with curl.

        The default 'user' account is sugar-coated for network learning
        purposes. If you need a bare user account to experiment with ssh
        public/private keys or automating things with ansible, it is
        better you create a new user account in the container and manage
        it as you see fit.


    To open terminals to all hosts run either:

        $0 terms

        To open a graphical desktop terminal window with the tmux layout
        connected to all machines. To exit, simply close the window, or
        run '$0 tkill' from another terminal.

        $0 attach

        To attach to the tmux session right in the current terminal.
        This is useful if you are using ssh to connect to your VM
        or a remote cloud instance. To exit, press <ctrl-a> + d, or run
        '$0 tkill' from another terminal.

        While in the terminal, type '?' to see a list of commonly used
        command aliases that save time when troubleshooting network
        configurations.


    The netlabs tmux config does the following:

        - Replace the default CTRL-B command prefix with CTRL-A
        - Enable mouse interaction
        - CTRL-A + A sets select-layout tiled
        - CTRL-A + H splits window horizontally
        - CTRL-A + V splits window Vertically
        - ALT-<ARROW UP, LEFT, DOWN, RIGHT> move cursor across panels


EOF

fi

