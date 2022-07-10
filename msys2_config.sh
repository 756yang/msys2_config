#!/bin/bash

function exec_function ()
{
  printf "execute command: $* (n to skip) "
  read ans
  if ! [ "$ans" = n -o "$ans" = N ]; then
    $@
  fi
}

function check_info ()
{
  printf "check $* (n to discard): "
  $@
  read ans
}

old_ALL_PROXY=$ALL_PROXY
old_http_proxy=$http_proxy
old_https_proxy=$https_proxy

function modify_mirrors ()
{
  mv /etc/pacman.d/mirrorlist.mingw32 /etc/pacman.d/mirrorlist.mingw32.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/mingw/i686' > /etc/pacman.d/mirrorlist.mingw32
  cat /etc/pacman.d/mirrorlist.mingw32.bak >> /etc/pacman.d/mirrorlist.mingw32

  mv /etc/pacman.d/mirrorlist.mingw64 /etc/pacman.d/mirrorlist.mingw64.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/mingw/x86_64' > /etc/pacman.d/mirrorlist.mingw64
  cat /etc/pacman.d/mirrorlist.mingw64.bak >> /etc/pacman.d/mirrorlist.mingw64

  mv /etc/pacman.d/mirrorlist.msys /etc/pacman.d/mirrorlist.msys.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/msys/$arch' > /etc/pacman.d/mirrorlist.msys
  cat /etc/pacman.d/mirrorlist.msys.bak >> /etc/pacman.d/mirrorlist.msys

  mv /etc/pacman.d/mirrorlist.ucrt64 /etc/pacman.d/mirrorlist.ucrt64.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/mingw/ucrt64' > /etc/pacman.d/mirrorlist.ucrt64
  cat /etc/pacman.d/mirrorlist.ucrt64.bak >> /etc/pacman.d/mirrorlist.ucrt64

  mv /etc/pacman.d/mirrorlist.mingw /etc/pacman.d/mirrorlist.mingw.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/mingw/$repo/' > /etc/pacman.d/mirrorlist.mingw
  cat /etc/pacman.d/mirrorlist.mingw.bak >> /etc/pacman.d/mirrorlist.mingw

  mv /etc/pacman.d/mirrorlist.clang32 /etc/pacman.d/mirrorlist.clang32.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/mingw/clang32' > /etc/pacman.d/mirrorlist.clang32
  cat /etc/pacman.d/mirrorlist.clang32.bak >> /etc/pacman.d/mirrorlist.clang32

  mv /etc/pacman.d/mirrorlist.clang64 /etc/pacman.d/mirrorlist.clang64.bak
  echo 'Server = http://mirrors.ustc.edu.cn/msys2/mingw/clang64' > /etc/pacman.d/mirrorlist.clang64
  cat /etc/pacman.d/mirrorlist.clang64.bak >> /etc/pacman.d/mirrorlist.clang64
  pacman -Syyu
}

function config_sshd ()
{
  pacman -S openssh cygrunsrv mingw-w64-x86_64-editrights
  cat << EOF > /msys2-sshd-setup.sh
#!/bin/sh
#  https://www.msys2.org/wiki/Setting-up-SSHd/
#  msys2-sshd-setup.sh — configure sshd on MSYS2 and run it as a Windows service
#
#  Replaces ssh-host-config <https://github.com/openssh/openssh-portable/blob/master/contrib/cygwin/ssh-host-config>
#  Adapted from <https://ghc.haskell.org/trac/ghc/wiki/Building/Windows/SSHD> by Sam Hocevar <sam@hocevar.net>
#  Adapted from <https://gist.github.com/samhocevar/00eec26d9e9988d080ac> by David Macek
#
#  Prerequisites:
#    — a 64-bit installation of MSYS2 itself: https://msys2.org
#    — some packages: pacman -S openssh cygrunsrv mingw-w64-x86_64-editrights
#
#  Gotchas:
#    — the log file will be /var/log/msys2_sshd.log
#    — if you get error “sshd: fatal: seteuid XXX : No such device or address”
#      in the logs, try “passwd -R” (with admin privileges)
#    — if you get error “chown(/dev/pty1, XXX, YYY) failed: Invalid argument”
#      in the logs, make sure your account and group names are detectable (see
#      `id`); issues are often caused by having /etc/{passwd,group} or having
#      a modified /etc/nsswitch.conf
#
#  Changelog:
#   09 May 2020 — completely remove additional privileged user
#   16 Apr 2020 — remove additional privileged user
#               — only touch /etc/{passwd,group} if they exist
#   27 Jun 2019 — rename service to msys2_sshd to avoid conflicts with Windows OpenSSH
#               — use mkgroup.exe as suggested in the comments
#               — fix a problem with CRLF and grep
#   24 Aug 2015 — run server with -e to redirect logs to /var/log/sshd.log
#

set -e

#
# Configuration
#

UNPRIV_USER=sshd # DO NOT CHANGE; this username is hardcoded in the openssh code
UNPRIV_NAME="Privilege separation user for sshd"

EMPTY_DIR=/var/empty


#
# Check installation sanity
#

if ! /mingw64/bin/editrights -h >/dev/null; then
    echo "ERROR: Missing 'editrights'. Try: pacman -S mingw-w64-x86_64-editrights."
    exit 1
fi

if ! cygrunsrv -v >/dev/null; then
    echo "ERROR: Missing 'cygrunsrv'. Try: pacman -S cygrunsrv."
    exit 1
fi

if ! ssh-keygen -A; then
    echo "ERROR: Missing 'ssh-keygen'. Try: pacman -S openssh."
    exit 1
fi


#
# The unprivileged sshd user (for privilege separation)
#

add="$(if ! net user "${UNPRIV_USER}" >/dev/null; then echo "//add"; fi)"
if ! net user "${UNPRIV_USER}" ${add} //fullname:"${UNPRIV_NAME}" \
              //homedir:"$(cygpath -w ${EMPTY_DIR})" //active:no; then
    echo "ERROR: Unable to create Windows user ${UNPRIV_USER}"
    exit 1
fi


#
# Add or update /etc/passwd entries
#

if test -f /etc/passwd; then
    sed -i -e '/^'"${UNPRIV_USER}"':/d' /etc/passwd
    SED='/^'"${UNPRIV_USER}"':/s?^\(\([^:]*:\)\{5\}\).*?\1'"${EMPTY_DIR}"':/bin/false?p'
    mkpasswd -l -u "${UNPRIV_USER}" | sed -e 's/^[^:]*+//' | sed -ne "${SED}" \
             >> /etc/passwd
    mkgroup.exe -l > /etc/group
fi


#
# Finally, register service with cygrunsrv and start it
#

cygrunsrv -R msys2_sshd || true
cygrunsrv -I msys2_sshd -d "MSYS2 sshd" -p /usr/bin/sshd.exe -a "-D -e" -y tcpip

# The SSH service should start automatically when Windows is rebooted. You can
# manually restart the service by running `net stop msys2_sshd` + `net start msys2_sshd`
if ! net start msys2_sshd; then
    echo "ERROR: Unable to start msys2_sshd service"
    exit 1
fi
EOF
  echo "please run /msys2-sshd-setup.sh as administrator to start a sshd."
}

function config_proxy ()
{
  cp $HOME/.bashrc $HOME/.bashrc.bak
  if [ `tail -n 1 /home/${USER}/.bashrc | wc -l` == 0 ]; then
    echo >> $HOME/.bashrc
  fi
  echo "alias envproxy='export ALL_PROXY=socks5://127.0.0.1:1089 all_proxy=socks5://127.0.0.1:1089 http_proxy=127.0.0.1:8889 https_proxy=127.0.0.1:8889 HTTP_PROXY=127.0.0.1:8889 HTTPS_PROXY=127.0.0.1:8889'" >> $HOME/.bashrc
  echo "alias unproxy='unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY'" >> $HOME/.bashrc
  export http_proxy=127.0.0.1:8889
  export all_proxy=socks5://127.0.0.1:1089
  export ALL_PROXY=$all_proxy \
       https_proxy=$http_proxy \
       ftp_proxy=$http_proxy \
       rsync_proxy=$http_proxy \
       HTTP_PROXY=$http_proxy \
       HTTPS_PROXY=$http_proxy \
       FTP_PROXY=$http_proxy \
       RSYNC_PROXY=$http_proxy
}

function install_sudo ()
{
  curl -s https://raw.githubusercontent.com/imachug/win-sudo/master/install.sh | sh
}

function install_mingw_toolchain ()
{
  pacman -S mingw-w64-x86_64-toolchain mingw-w64-i686-toolchain
}

function install_qt6 ()
{
  pacman -S mingw-w64-x86_64-qt6 mingw-w64-x86_64-qt-creator mingw-w64-x86_64-cmake
}

exec_function modify_mirrors
exec_function pacman -S base-devel
exec_function pacman -S cmake
exec_function pacman -S python
exec_function pacman -S subversion
exec_function pacman -S git
exec_function pacman -S vim
exec_function pacman -S openssh
exec_function config_proxy
exec_function install_sudo
exec_function install_mingw_toolchain
exec_function install_qt6









unset http_proxy https_proxy ftp_proxy rsync_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY RSYNC_PROXY ALL_PROXY
export ALL_PROXY=$old_ALL_PROXY http_proxy=$old_http_proxy https_proxy=$old_https_proxy
unset  old_ALL_PROXY old_http_proxy old_https_proxy