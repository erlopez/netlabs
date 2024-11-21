# Linux Networking Labs

`netlabs.sh` is a command-line tool designed to quickly create flexible network setups 
using Ubuntu servers. It helps students practice and enhance their Linux networking 
skills with tools like `iproute2` (`ip`), `iptables`, `dnsmasq`, and others.

This page provides tutorials on basic Linux networking problems and their solutions.

It's recommended to use this tool inside a virtual machine (VM) or on a 
spare machine dedicated to experimentation.

So far, `netlabs.sh` has been tested on 
[Linux Mint 22 Mate Edition](https://www.linuxmint.com/edition.php?id=318) and 
[Linux Mint Debian Edition](https://www.linuxmint.com/edition.php?id=308) (LMDE 6), 
but it is likely to run in other Debian distros such as Ubuntu.

 
# Install Dependencies

Install _git_ and _tmux_:
```bash            
sudo apt -y install git tmux

```

              
# Configuring netlabs
      
Clone the _netlabs_ project:
    
```bash
git clone https://github.com/erlopez/netlabs.git

```
    
Change into the `netlabs/` directory and run the following commands:
       
- Set up rules to give lxd containers Internet access:
    
    ```bash
    ./netlabs.sh gwsetup   
   
    ```

- Install LXD: 
    
    ```bash
    ./netlabs.sh install

    ```
   
    > **Before you continue:**
    Log out and log back in to refresh your group permissions. 
    Once you are back in, open a terminal type the `id` command; if the group 
    `lxd` is not listed, reboot your system or VM before moving to the next step.
  

- Initialize LXD for first time use:
    
    ```bash
    ./netlabs.sh init   
   
    ```

- Set up the base Ubuntu image:
    
    ```bash
    ./netlabs.sh setup   
   
    ```
- Optional, create a _tmux_ config (recommended if you don't have a tmux config of your own):
    
    ```bash
    ./netlabs.sh conf   
   
    ```    
   The _netlabs_ _tmux_ config does the following:

    - Replaces the default _CTRL-B_ command prefix with **CTRL-A**
    - Enables mouse interaction
    - **CTRL-A + A** sets select-layout tiled
    - **CTRL-A + H** splits window horizontally
    - **CTRL-A + V** splits window Vertically
    - **ALT-ARROW**<UP, LEFT, DOWN, RIGHT> moves cursor across panels
  
              

# Usage
                        
The main job of `netlabs.sh` is building custom computer networks
and opening the terminal shells into each of the created computers.
This is done by managing _lxd_ containers and network bridges in the
host system.

To build a network playground, use the _build_ command as follows:

```bash
  ./netlabs.sh   build  router,0,1,7  bob,1  jim,1  ws,7
```
        
This creates a network as follows:

```
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
```

The _build_ command takes arguments formatted as follows:
          
```
    hostname,0,1,2,3[,n...]
    |        | | | |
    |        | | | +--> network segment eth3 is connected to
    |        | | +--> network segment eth2 is connected to
    |        | +--> network segment eth1 is connected to
    |        +--> network segment eth0 is connected to
    +--> name of a host in the network
```

There should not be any space between the _hostname_ and
its comma-separated network identifiers. Network identifiers
don't need to be sequential, for example, this is a valid 
host declaration `foobar,0,4,7,1`.

Hosts with matching network identifiers are connected
as if a network switch exists between them.

Except for the _Gateway_, all network interfaces in all machines
are not initialized. Is your job to assign IP address, routes
and firewalls as desired. The _Gateway_ (net0) always has the
IP _192.168.200.1_ and works as your "Internet Gateway" if
internet access is necessary.

Network ID numbers are arbitrary. Network 0 is always present
and connected to _Gateway_.

Running the build command destroys the previous network before
creating a new one.

**If you reboot your system, you need to build your network again.**

All the machines have the account '_user_' (id 1000). The home
folder for this _user_ is mapped to the external folder `user/` thus all
machines share the same .ssh, .bashrc, .bash_history and any
other file created in the user's home folder. When the network is
destroyed and created, files in the `/home/user` folder persist.

The password for the "user" and "root" accounts is `'`,
(a single quote) however, because all machines share the same .ssh
files, it is possible ssh between them without a password.

The default _user_ account is sugar-coated for network learning
purposes. If you need a bare user account to experiment with ssh 
public/private keys or automating things with ansible, it is 
better you create a new user account in the container and manage 
it as you see fit.

All machines have a basic web server on port 80 which can be used
for testing with _curl_.

To open terminals to all hosts run either:

- `./netlabs.sh terms` to open a graphical desktop terminal window 
with the tmux layout connected to all machines. To exit, close the 
window, or run `./netlabs.sh tkill` from another terminal.
              
                                  
- `./netlabs.sh attach` to attach to the tmux session right in the 
current terminal. This is useful if you are using _ssh_ to connect 
to your test VM or a remote cloud instance. To exit, press 
**<ctrl-a> + d**, or run `./netlabs.sh tkill` from another terminal.
                                
While in the terminal, type `?` to see a list of commonly used 
command aliases that save time when troubleshooting network
configurations. 

To show this help in the command line, run `./netlabs.sh` without 
arguments. 



# Linux Networking Tutorials

  - **Lab 1** - [The Everyday Essentials](lab1.md)
  - **Lab 2** - [The Out-of-the-box Problem](lab2.md)
  - **Lab 3** - [Setting Up DHCP and Bridges](lab3.md)
           



# References

- **ip** manual: https://man7.org/linux/man-pages/man8/ip.8.html
- **iptables** manual: https://linux.die.net/man/8/iptables
- **netplan** manual: https://netplan.readthedocs.io/en/stable/netplan-yaml/
- **systemd-resolved** manual: https://www.man7.org/linux/man-pages/man5/resolved.conf.5.html
- **dnsmasq** manual: https://dnsmasq.org/docs/dnsmasq-man.html
- **tmux** manual: https://www.man7.org/linux/man-pages/man1/tmux.1.html
- **Books**: [Designing and Implementing Linux Firewalls and QoS using netfilter, iproute2, NAT and l7-filter](https://www.packtpub.com/en-us/product/designing-and-implementing-linux-firewalls-and-qos-using-netfilter-iproute2-nat-and-l7-filter-9781904811657)
             by Lucian Gheorghe, Packt Publishing, chapters 3 and 4
- **Icons**: Icon Experience V-Collection set https://www.iconexperience.com/v_collection/
        

    
                 
# Related YouTube Videos

- [Getting started with LXD Containerization](https://youtu.be/aIwgPKkVj8s?si=PB8BU9DJ_-Fw8Isq) - Learn Linux TV
- [Network Namespaces Basics Explained in 15 Minutes](https://youtu.be/j_UUnlVC2Ss?si=PzElUZ3shOhvYYuJ) - KodeKloud
 



    
# Apendix

### List of Private IP Addresses
  
Private IP addresses are those in these ranges:

- 10.0.0.0 - 10.255.255.255
- 172.16.0.0 - 172.31.255.255
- 192.168.0.0 - 192.168.255.255


