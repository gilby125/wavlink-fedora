#!/bin/bash
export LC_ALL=C
readonly SELF=$0/binaries
readonly COREDIR=/opt/siliconmotion
readonly OTHERPDDIR=/opt/displaylink
readonly LOGPATH=/var/log/SMIUSBDisplay
readonly PRODUCT="Silicon Motion Linux USB Display Software"
VERSION=2.22.1.0
ACTION=install

#FEDORA41_DISPLAYLINK_RPM=https://github.com/displaylink-rpm/displaylink-rpm/releases/download/v6.1.0-2/fedora-41-displaylink-1.14.7-4.github_evdi.x86_64.rpm
FEDORA41_DISPLAYLINK_RPM=https://github.com/displaylink-rpm/displaylink-rpm/releases/download/v6.1.0-3/fedora-41-displaylink-1.14.9-1.github_evdi.x86_64.rpm 

add_upstart_script()
{
  cat > /etc/init/smiusbdisplay.conf <<'EOF'
description "SiliconMotion Driver Service"


start on login-session-start
stop on desktop-shutdown

# Restart if process crashes
respawn

# Only attempt to respawn 10 times in 5 seconds
respawn limit 10 5

chdir /opt/siliconmotion

pre-start script
    . /opt/siliconmotion/smi-udev.sh

    if [ "\$(get_siliconmotion_dev_count)" = "0" ]; then
        stop
        exit 0
    fi
end script
script
    [ -r /etc/default/siliconmotion ] && . /etc/default/siliconmotion
    modprobe evdi
    if [ $? != 0 ]; then
	local v=$(awk -F '=' '/PACKAGE_VERSION/{print $2}' /opt/siliconmotion/module/dkms.conf)
	dkms remove -m evdi -v $v --all
	if [ $? != 0 ]; then
    		rm –rf /var/lib/dkms/$v
	fi
	dkms install /opt/siliconmotion/module/
	if [ $? == 0 ]; then
		cp /opt/siliconmotion/evdi.conf /etc/modprobe.d 
		modprobe evdi
	fi
    fi
    exec LD_LIBRARY_PATH=/opt/siliconmotion /opt/siliconmotion/SMIUSBDisplayManager
end script
EOF

  chmod 0644 /etc/init/smiusbdisplay.conf
}

remove_upstart_script()
{
  rm -f /etc/init/smiusbdisplay.conf
}

add_wayland_script()
{
if [ "$(lsb_release -r --short)"  == "20.04" ];
then
  mkdir -p /usr/share/xsessions/hidden
  dpkg-divert --rename --divert /usr/share/xsessions/hidden/ubuntu.desktop --add /usr/share/xsessions/ubuntu.desktop
fi
}

remove_wayland_script()
{
if [ "$(lsb_release -r --short)"  == "20.04" ];
then
  dpkg-divert --rename --remove /usr/share/xsessions/ubuntu.desktop
fi
}

add_systemd_service()
{
  cat > /lib/systemd/system/smiusbdisplay.service <<'EOF'
[Unit]
Description=SiliconMotion Driver Service
After=display-manager.service
Conflicts=getty@tty7.service

[Service]
Environment=LD_LIBRARY_PATH=/opt/siliconmotion
ExecStartPre=/bin/bash -c "modprobe evdi || (dkms remove -m evdi -v $(awk -F '=' '/PACKAGE_VERSION/{print $2}' /opt/siliconmotion/module/dkms.conf) --all; if [ $? != 0 ]; then rm –rf /var/lib/dkms/$(awk -F '=' '/PACKAGE_VERSION/{print $2}' /opt/siliconmotion/module/dkms.conf) ;fi; dkms install /opt/siliconmotion/module/ && cp /opt/siliconmotion/evdi.conf /etc/modprobe.d && modprobe evdi)"

ExecStart= /opt/siliconmotion/SMIUSBDisplayManager
Restart=always
WorkingDirectory=/opt/siliconmotion
RestartSec=5

EOF

  chmod 0644 /lib/systemd/system/smiusbdisplay.service
}

trigger_udev_if_devices_connected()
{
  for device in $(grep -lw 090c /sys/bus/usb/devices/*/idVendor); do
    udevadm trigger --action=add "$(dirname "$device")"
  done
}

remove_systemd_service()
{
  driver_name="smiusbdisplay"
  echo "Stopping ${driver_name} systemd service"
  systemctl stop ${driver_name}.service
  systemctl disable ${driver_name}.service
  rm -f /lib/systemd/system/${driver_name}.service
}

remove_pm_scripts()
{
  rm -f /etc/pm/sleep.d/smipm.sh
  rm -f /lib/systemd/system-sleep/smipm.sh
}

cleanup()
{
  rm -rf $COREDIR
  rm -rf $LOGPATH
  rm -f /usr/bin/smi-installer
  rm -f /usr/bin/SMIFWLogCapture
}

binary_location()
{
  echo "$(pwd)/binaries"
  
}

install()
{
  echo "Installing..."

  echo "Installing EVDI displaylink driver from URL: ${FEDORA41_DISPLAYLINK_RPM}"
  dnf install ${FEDORA41_DISPLAYLINK_RPM}

  mkdir -p $COREDIR
  chmod 0755 $COREDIR
  
  # cp -f "$SELF" "$COREDIR"
  echo "Copying binaries..."
  cp -f $(pwd)/binaries/* $COREDIR

  echo "Creating symlinks and setting permissions..."
  ln -sf $COREDIR/libusb-1.0.so.0.2.0 $COREDIR/libusb-1.0.so.0
  ln -sf $COREDIR/libusb-1.0.so.0.2.0 $COREDIR/libusb-1.0.so
  ln -sf /usr/libexec/displaylink/libevdi.so $COREDIR/libevdi.so.1

  chmod 0755 $COREDIR/SMIUSBDisplayManager
  chmod 0755 $COREDIR/libusb*.so*
  chmod 0755 $COREDIR/SMIFWLogCapture
  
  ln -sf $COREDIR/SMIFWLogCapture /usr/bin/SMIFWLogCapture
  chmod 0755 /usr/bin/SMIFWLogCapture

  source smi-udev-installer.sh
  siliconmotion_bootstrap_script="$COREDIR/smi-udev.sh"
  create_bootstrap_file "$SYSTEMINITDAEMON" "$siliconmotion_bootstrap_script"
  
  add_wayland_script

  echo "Adding udev rule for SiliconMotion devices"
  create_udev_rules_file /etc/udev/rules.d/99-smiusbdisplay.rules

  echo "Adding upstart scripts"
  if [ "upstart" == "$SYSTEMINITDAEMON" ]; then
    echo "Starting SMIUSBDisplay upstart job"
    add_upstart_script
#   add_pm_script "upstart"
  elif [ "systemd" == "$SYSTEMINITDAEMON" ]; then
    echo "Starting SMIUSBDisplay systemd service"
    add_systemd_service
#  add_pm_script "systemd"
  fi

  echo -e "\nInstallation complete!"
  echo -e "\nPlease reboot your computer and check if everything is working as intended."
}

uninstall()
{
  echo "Uninstall is not implemented yet."
  exit 0

  if [ "upstart" == "$SYSTEMINITDAEMON" ]; then
    echo "Stopping SMIUSBDisplay upstart job"
    stop smiusbdisplay
    remove_upstart_script
  elif [ "systemd" == "$SYSTEMINITDAEMON" ]; then
    echo "Stopping SMIUSBDisplay systemd service"
    systemctl stop smiusbdisplay.service
    remove_systemd_service

  fi

  echo "[ Removing suspend-resume hooks ]"
  #remove_pm_scripts

  echo "[ Removing udev rule ]"
  rm -f /etc/udev/rules.d/99-smiusbdisplay.rules
  udevadm control -R
  udevadm trigger
  
  remove_wayland_script

  echo "[ Removing Core folder ]"
  cleanup

  modprobe -r evdi

  if [ -d $OTHERPDDIR ]; then
	  echo "WARNING: There are other products in the system using EVDI."
  else 
	  echo "Removing EVDI from kernel tree, DKMS, and removing sources."
    	  (
    	  cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && \
	  uninstall_evdi_module "evdi.tar.gz"
    	  )
  fi

  echo -e "\nUninstallation steps complete."
  if [ -f /sys/devices/evdi/count ]; then
    echo "Please note that the evdi kernel module is still in the memory."
    echo "A reboot is required to fully complete the uninstallation process."
  fi
}

usage()
{
  echo
  echo "Installs $PRODUCT, version $VERSION."
  echo "Usage: $SELF [ install | uninstall ]"
  echo
  echo "The default operation is install."
  echo "If unknown argument is given, a quick compatibility check is performed but nothing is installed."
  exit 1
}

detect_init_daemon()
{
    INIT=$(readlink /proc/1/exe)
    if [ "$INIT" == "/sbin/init" ]; then
        INIT=$(/sbin/init --version)
    fi

    [ -z "${INIT##*upstart*}" ] && SYSTEMINITDAEMON="upstart"
    [ -z "${INIT##*systemd*}" ] && SYSTEMINITDAEMON="systemd"

    if [ -z "$SYSTEMINITDAEMON" ]; then
        echo "ERROR: the installer script is unable to find out how to start SMIUSBDisplayManager service automatically on your system." >&2
        echo "Please set an environment variable SYSTEMINITDAEMON to 'upstart' or 'systemd' before running the installation script to force one of the options." >&2
        echo "Installation terminated." >&2
        exit 1
    fi
}

distro_check()
{
  if [ -f /etc/fedora-release ] && grep -q "Fedora release 41" /etc/fedora-release
  then
    echo -n "Fedora 41 recognized. "
  else
    echo -n "This script has not been tested on your distro/release. "
    
    read -rp 'Do you want to continue? [y/N] ' CHOICE

    [[ "${CHOICE:-N}" == "${CHOICE#[nN]}" ]] || exit 1
  fi

  echo "Will proceed..."
}

if [ "$(id -u)" != "0" ]; then
  echo "You need to be root to use this script." >&2
  exit 1
fi

[ -z "$SYSTEMINITDAEMON" ] && detect_init_daemon || echo "Trying to use the forced init system: $SYSTEMINITDAEMON"
distro_check

install

systemctl start smiusbdisplay.service
