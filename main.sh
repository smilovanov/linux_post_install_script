#!/bin/bash

function promptPassphrase {
	PASS=""
	PASSCONF=""
	while [ -z "$PASS" ]; do
		read -s -p "Passphrase: " PASS
		echo ""
	done
	
	while [ -z "$PASSCONF" ]; do
		read -s -p "Confirm passphrase: " PASSCONF
		echo ""
	done
	echo ""
}

function getPassphrase {
	promptPassphrase
	while [ "$PASS" != "$PASSCONF" ]; do
		echo "Passphrases did not match, try again..."
		promptPassphrase
	done
}


#check that script run as root
if [[ $UID -ne 0 ]]; then
 echo "This script needs to be run as root (with sudo)."
 exit 1
fi

#adding corporate repository and installing software
echo "deb [arch=amd64] https://repo.infobip.com stable main" | tee /etc/apt/sources.list.d/corporate list
wget -qO - https://repo.infobip.com/gpg.key | sudo apt-key add -
apt-get update
apt-get install -y globalprotect falcon_sensor
snap install slack

#modifying list of standard applications
apt-get dist-upgrade -y
apt-get remove -y popularity-contest
apt-get install -y apparmor-profiles apparmor-utils auditd

#importing root certificate authority
mkdir /usr/share/ca-certificates/certs 
wget #certificate link
cp #certificate
update-ca-certificates
firefox
#importing ca-certificate to firefox 

# Set grub password.
echo -e "Configuring grub..."
echo "Please enter a grub sysadmin passphrase..."
getPassphrase

echo "set superusers=\"sysadmin\"" >> /etc/grub.d/40_custom
echo -e "$PASS\n$PASS" | grub-mkpasswd-pbkdf2 | tail -n1 | awk -F" " '{print "password_pbkdf2 sysadmin " $7}' >> /etc/grub.d/40_custom
sed -ie '/echo "menuentry / s/echo "menuentry /echo "menuentry --unrestricted /' /etc/grub.d/10_linux
sed -ie '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ module.sig_enforce=yes"/' /etc/default/grub
echo "GRUB_SAVEDEFAULT=false" >> /etc/default/grub
update-grub

# Set permissions for admin user's home directory.
ADMINUSER=$(ls /home)
chmod 700 "/home/$ADMINUSER"

# Configure automatic updates.
echo -e "Configuring automatic updates..."
EXISTS=$(grep "APT::Periodic::Update-Package-Lists" /etc/apt/apt.conf.d/20auto-upgrades)
if [ -z "$EXISTS" ]; then
	sed -i '/APT::Periodic::Update-Package-Lists/d' /etc/apt/apt.conf.d/20auto-upgrades
	echo "APT::Periodic::Update-Package-Lists \"1\";" >> /etc/apt/apt.conf.d/20auto-upgrades
fi

EXISTS=$(grep "APT::Periodic::Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades)
if [ -z "$EXISTS" ]; then
	sed -i '/APT::Periodic::Unattended-Upgrade/d' /etc/apt/apt.conf.d/20auto-upgrades
	echo "APT::Periodic::Unattended-Upgrade \"1\";" >> /etc/apt/apt.conf.d/20auto-upgrades
fi

EXISTS=$(grep "APT::Periodic::AutocleanInterval" /etc/apt/apt.conf.d/10periodic)
if [ -z "$EXISTS" ]; then
	sed -i '/APT::Periodic::AutocleanInterval/d' /etc/apt/apt.conf.d/10periodic
	echo "APT::Periodic::AutocleanInterval \"7\";" >> /etc/apt/apt.conf.d/10periodic
fi

chmod 644 /etc/apt/apt.conf.d/20auto-upgrades
chmod 644 /etc/apt/apt.conf.d/10periodic

# Prevent standard user executing su.
echo -e "Configure su execution..."
dpkg-statoverride --update --add root adm 4750 /bin/su

# Protect user home directories.
echo -e "Configuring home directories and shell access..."
sed -ie '/^DIR_MODE=/ s/=[0-9]*\+/=0700/' /etc/adduser.conf

# Installing libpam-pwquality 
echo -e "Configuring minimum password requirements..."
apt-get install -f libpam-pwquality

#creating local non-admin user
echo
echo "Please enter a username for the primary device user that will be created by this script."
while [ -z "$ENDUSER" ]; do read -p "Username for primary device user: " ENDUSER; done
adduser "$ENDUSER"

# Set AppArmor profiles to enforce mode.
echo -e "Configuring apparmor..."
aa-enforce /etc/apparmor.d/usr.bin.firefox
aa-enforce /etc/apparmor.d/usr.sbin.avahi-daemon
aa-enforce /etc/apparmor.d/usr.sbin.dnsmasq
aa-enforce /etc/apparmor.d/bin.ping
aa-enforce /etc/apparmor.d/usr.sbin.rsyslogd

# Setup auditing.
echo -e "Configuring system auditing..."
if [ ! -f /etc/audit/rules.d/tmp-monitor.rules ]; then
echo "# Monitor changes and executions within /tmp
-w /tmp/ -p wa -k tmp_write
-w /tmp/ -p x -k tmp_exec" > /etc/audit/rules.d/tmp-monitor.rules
fi

if [ ! -f /etc/audit/rules.d/admin-home-watch.rules ]; then
echo "# Monitor administrator access to /home directories
-a always,exit -F dir=/home/ -F uid=0 -C auid!=obj_uid -k admin_home_user" > /etc/audit/rules.d/admin-home-watch.rules
fi
augenrules
systemctl restart auditd.service

# Configure the settings for the "Welcome" popup box on first login.
echo -e "Configuring user first login settings..."
mkdir -p "/home/$ENDUSER/.config"
echo yes > "/home/$ENDUSER/.config/gnome-initial-setup-done"
chown -R "$ENDUSER:$ENDUSER" "/home/$ENDUSER/.config"
sudo -H -u "$ENDUSER" ubuntu-report -f send no

# Disable error reporting services
echo -e "Configuring error reporting..."
systemctl stop apport.service
systemctl disable apport.service
systemctl mask apport.service

systemctl stop whoopsie.service
systemctl disable whoopsie.service
systemctl mask whoopsie.service

# Lockdown Gnome screensaver lock settings
echo -e "${HIGHLIGHT}Configuring Gnome screensaver lock settings...${NC}"
mkdir -p /etc/dconf/db/local.d/locks
echo "[org/gnome/login-screen]
disable-user-list=true
[org/gnome/desktop/session]
idle-delay=600
[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=0
ubuntu-lock-on-suspend=true" > /etc/dconf/db/local.d/00_custom-lock

echo "/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/lock-delay
/org/gnome/desktop/screensaver/ubuntu-lock-on-suspend
/org/gnome/login-screen/disable-user-list" > /etc/dconf/db/local.d/locks/00_custom-lock

# Report-technical-promlems Setting
echo "
[org/gnome/desktop/privacy]
report-technical-problems=false" >> /etc/dconf/db/local.d/00_custom-lock
echo "/org/gnome/desktop/privacy/report-technical-problems" >> /etc/dconf/db/local.d/locks/00_custom-lock

#disabling USB usage on lockscreen
echo "usb-protection-level='lockscreen'" >> /etc/dconf/db/local.d/00_custom-lock
echo "/org/gnome/desktop/privacy/usb-protection-level" >> /etc/dconf/db/local.d/locks/00_custom-lock

dconf update
# Fix dconf permissions, otherwise option locks don't apply upon subsequent script executions
chmod 644 -R /etc/dconf/db/
chmod a+x /etc/dconf/db/local.d/locks
chmod a+x /etc/dconf/db/local.d
chmod a+x /etc/dconf/db

# Disable apport (error reporting)
sed -ie '/^enabled=1$/ s/1/0/' /etc/default/apport

sudo -H -u "$ENDUSER" dbus-launch gsettings set com.ubuntu.update-notifier show-apport-crashes false

# Setting up firewall without any rules.
echo -e "Configuring firewall… "
ufw enable	


echo -e "Installation complete."

read -p "Reboot now? [y/n]: " CONFIRM
if [ "$CONFIRM" == "y" ]; then
	reboot
fi