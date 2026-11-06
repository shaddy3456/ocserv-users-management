#!/bin/bash

if [[ $(id -u) != "0" ]]; then
    echo -e "\e[0;31m"Error: You must be root to run this install script."\e[0m"
    exit 1
fi

basepath=$(dirname $0)
cd ${basepath}

Config_Variable() {
    # Variable settings
    # Single IP maximum number of connections, the default is 2
    maxsameclients=2
    # The maximum number of connections, the default is 16
    maxclients=1024
    # Server certificate and key file, placed in the same directory with the script, the key file permissions should be 600 or 400
    servercert=${1-server-cert.pem}
    serverkey=${2-server-key.pem}
    # VPN Intranet IP segment
    vpnnetwork="172.16.24.0/24"
    # DNS
    dns1="8.8.8.8"
    dns2="8.8.4.4"
    # Configuration directory
    confdir="/etc/ocserv"

    # Obtain the network card interface name
    ethlist=$(ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v -E '^(lo|docker|veth|br-|vpns|tun)')
    # Prefer the interface that holds the default route
    eth=$(ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n 1)
    if [[ -z "${eth}" ]]; then
        eth=$(printf "${ethlist}\n" | head -n 1)
    fi
    if [[ $(printf "${ethlist}\n" | wc -l) -gt 1 ]]; then
        echo ======================================
        echo "Network Interface list:"
        printf "\e[33m${ethlist}\e[0m\n"
        echo ======================================
        echo "Which network interface you want to listen for ocserv?"
        printf "Default network interface is \e[33m${eth}\e[0m, let it blank to use this network interface: "
        read ethtmp
        if [[ -n "${ethtmp}" ]]; then
            eth=${ethtmp}
        fi
    fi

    # Port, the default is 10443
    port=10443
    echo -e "\nPlease input the port ocserv listen to."
    printf "Default port is \e[33m${port}\e[0m, let it blank to use this port: "
    read porttmp
    if [[ -n "${porttmp}" ]]; then
        port=${porttmp}
    fi

    # User name, default is user
    username=user
    echo -e "\nPlease input ocserv user name."
    printf "Default user name is \e[33m${username}\e[0m, let it blank to use this user name: "
    read usernametmp
    if [[ -n "${usernametmp}" ]]; then
        username=${usernametmp}
    fi

    # random code
    randstr() {
        index=0
        str=""
        for i in {a..z}; do arr[index]=$i; index=$(expr ${index} + 1); done
        for i in {A..Z}; do arr[index]=$i; index=$(expr ${index} + 1); done
        for i in {0..9}; do arr[index]=$i; index=$(expr ${index} + 1); done
        for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
        echo ${str}
    }
    password=$(randstr)
    printf "\nPlease input \e[33m${username}\e[0m's password.\n"
    printf "Random password is \e[33m${password}\e[0m, let it blank to use this password: "
    read passwordtmp
    if [[ -n "${passwordtmp}" ]]; then
        password=${passwordtmp}
    fi    
}

Print_Variable() {
    # Print the configuration parameters
    clear

    ipv4=$(ip -4 -f inet addr show ${eth} | grep 'inet' | sed 's/.*inet \([0-9\.]\+\).*/\1/')
    ipv6=$(ip -6 -f inet6 addr show ${eth} | grep -v -P "(::1\/128|fe80)" | grep -o -P "([a-z\d]+:[a-z\d:]+)")
    echo -e "IPv4:\t\t\e[34m$(echo ${ipv4})\e[0m"
    if [ ! "$ipv6" = "" ]; then
        echo -e "IPv6:\t\t\e[34m$(echo ${ipv6})\e[0m"
    fi
    echo -e "Port:\t\t\e[34m${port}\e[0m"
    echo -e "Username:\t\e[34m${username}\e[0m"
    echo -e "Password:\t\e[34m${password}\e[0m"
    echo
    echo "Press any key to start install ocserv."

    get_char() {
        SAVEDSTTY=$(stty -g)
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty ${SAVEDSTTY}
    }
    char=$(get_char)
    clear  
}

Install_Ocserv() {
    echo -e "\e[0;36m"Installing Ocserv..."\e[0m"
    apt-get update
    apt-get install -y ocserv gnutls-bin
    if [    "$?" = "0" ];then
        echo -e "\e[0;32m"Ocserv Installation Was Successful."\e[0m"
    else
        echo -e "\e[0;31m"Ocserv Installation Is Failed"\e[0m"
        exit 1
    fi    
}

Config_Ocserv() {
   # Detects whether there is a certificate and a key file
    if [[ ! -f "${servercert}" ]] || [[ ! -f "${serverkey}" ]]; then
        # Create a ca certificate and a server certificate (refer to http://www.infradead.org/ocserv/manual.html#heading5)
        certtool --generate-privkey --outfile ca-key.pem

        cat << _EOF_ >ca.tmpl
cn = "Endway Cisco VPN"
organization = "Endway"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
crl_signing_key
_EOF_

        certtool --generate-self-signed --load-privkey ca-key.pem \
        --template ca.tmpl --outfile ca-cert.pem
        certtool --generate-privkey --outfile ${serverkey}

        cat << _EOF_ >server.tmpl
cn = "Endway Cisco VPN"
organization = "Endway"
serial = 2
expiration_days = 3650
signing_key
encryption_key #only if the generated key is an RSA one
tls_www_server
_EOF_

        certtool --generate-certificate --load-privkey ${serverkey} \
        --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem \
        --template server.tmpl --outfile ${servercert}
    fi

    # Copy the certificate and point ocserv.conf at it
    mkdir -p "${confdir}/ssl"
    cp "${servercert}" "${confdir}/ssl/server-cert.pem"
    cp "${serverkey}" "${confdir}/ssl/server-key.pem"
    chmod 600 "${confdir}/ssl/server-key.pem"
    sed -i "s@^server-cert = .*@server-cert = ${confdir}/ssl/server-cert.pem@" "${confdir}/ocserv.conf"
    sed -i "s@^server-key = .*@server-key = ${confdir}/ssl/server-key.pem@" "${confdir}/ocserv.conf"

    # Edit the configuration file
    (echo "${password}"; sleep 1; echo "${password}") | ocpasswd -c "${confdir}/ocpasswd" ${username}

    sed -i 's@auth = "pam"@#auth = "pam"\nauth = "plain[passwd=/etc/ocserv/ocpasswd]"@g' "${confdir}/ocserv.conf"
    sed -i "s/max-same-clients = 2/max-same-clients = ${maxsameclients}/g" "${confdir}/ocserv.conf"
    sed -i "s/max-clients = 16/max-clients = ${maxclients}/g" "${confdir}/ocserv.conf"
    sed -i "s/tcp-port = 443/tcp-port = ${port}/g" "${confdir}/ocserv.conf"
    sed -i "s/udp-port = 443/udp-port = ${port}/g" "${confdir}/ocserv.conf"
    sed -i 's/^ca-cert = /#ca-cert = /g' "${confdir}/ocserv.conf"
    sed -i 's/^cert-user-oid = /#cert-user-oid = /g' "${confdir}/ocserv.conf"
    sed -i "s/default-domain = example.com/#default-domain = example.com/g" "${confdir}/ocserv.conf"
    sed -i "s@#ipv4-network = 192.168.1.0/24@ipv4-network = ${vpnnetwork}@g" "${confdir}/ocserv.conf"
    sed -i "s/#dns = 192.168.1.2/dns = ${dns1}\ndns = ${dns2}/g" "${confdir}/ocserv.conf"
    sed -i "s/cookie-timeout = 300/cookie-timeout = 86400/g" "${confdir}/ocserv.conf"
    sed -i 's/user-profile = profile.xml/#user-profile = profile.xml/g' "${confdir}/ocserv.conf"
    sed -i 's/^#mtu/mtu = 1420/g' "${confdir}/ocserv.conf"
    sed -i 's/auth = "pam\[gid-min=1000\]"/#auth = "pam\[gid-min=1000\]"/g'  "${confdir}/ocserv.conf"
    ######################PAMMMMMM
}

Config_Firewall() {
    firewalldisactive=$(systemctl is-active firewalld.service 2>/dev/null)

    if [[ ${firewalldisactive} = 'active' ]]; then
        echo "Adding firewall ports (firewalld)."
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --permanent --add-port=${port}/udp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-masquerade
        firewall-cmd --reload
        return
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        echo "Adding firewall ports (ufw)."
        ufw allow ${port}/tcp
        ufw allow ${port}/udp
        ufw allow 80/tcp
        sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
        if ! grep -q "OCSERV_NAT" /etc/ufw/before.rules; then
            sed -i "1i # OCSERV_NAT\\n*nat\\n:POSTROUTING ACCEPT [0:0]\\n-A POSTROUTING -s ${vpnnetwork} -o ${eth} -j MASQUERADE\\nCOMMIT\\n# OCSERV_NAT_END\\n" /etc/ufw/before.rules
        fi
        ufw reload
        return
    fi

    # Plain iptables (default on most Ubuntu/Debian servers)
    echo "Configuring iptables NAT."
    iptables -C INPUT -p tcp --dport ${port} -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
    iptables -C INPUT -p udp --dport ${port} -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport ${port} -j ACCEPT
    iptables -C FORWARD -s ${vpnnetwork} -j ACCEPT 2>/dev/null || iptables -I FORWARD -s ${vpnnetwork} -j ACCEPT
    iptables -C FORWARD -d ${vpnnetwork} -j ACCEPT 2>/dev/null || iptables -I FORWARD -d ${vpnnetwork} -j ACCEPT
    iptables -t nat -C POSTROUTING -s ${vpnnetwork} -o ${eth} -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -s ${vpnnetwork} -o ${eth} -j MASQUERADE
    # Persist rules across reboots
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    netfilter-persistent save
}

Config_System() {
    # Disable selinux only where it exists (RHEL family)
    if [[ -f /etc/selinux/config ]]; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0 2>/dev/null
    fi
    echo "Enable IP forward."
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/60-ocserv.conf
    sysctl -w net.ipv4.ip_forward=1
    systemctl daemon-reload
    echo "Enable ocserv service to start during bootup."
    systemctl enable ocserv.service
    #Start the ocserv service
    systemctl start ocserv.service
    echo
}

INSTALL_PANNEL_Env() {
     echo -e "\e[0;36m"Installing Pannel Environment..."\e[0m"
    apt install python3 python3-pip virtualenv build-essential python3-dev nginx git -y
    if [    "$?" = "0" ];then
        echo -e "\e[0;32m"Environment Installation Was Successful."\e[0m"
    else
        echo -e "\e[0;31m"Environment Installation Is Failed"\e[0m"
        exit 1
    fi
}

GIT_PROJECT(){
    echo -e "\e[0;36m"Get Project From Git Repository..."\e[0m"
    git clone https://github.com/mmtaee/Ocserv-Vpn-User-Management.git
    if [    "$?" = "0" ];then
        echo -e "\e[0;32m"Git Clone Was Successful."\e[0m"
    else
        echo -e "\e[0;31m"Cannot "Git Clone" Project From "github"."\e[0m"
        exit 1
    fi
}

PRO_DIR() {
    echo -e "\e[0;36m"Preparation Directorys And Files..."\e[0m"

    mkdir -p /var/www/html/ocserv_pannel/

    cp -r $(pwd)/* /var/www/html/ocserv_pannel/
}

PRO_VENV() {
    echo -e "\e[0;36m"Creating Python virtualenv..."\e[0m"

    cd /var/www/html/ocserv_pannel/

    virtualenv -p python3 venv

    source venv/bin/activate

    pip install -r requirements.txt

    ./manage.py migrate

    # Random admin password instead of admin/admin
    panel_admin_password=$(head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
    PANEL_ADMIN_PASSWORD="${panel_admin_password}" python manage.py shell -c "import os; from django.contrib.auth import get_user_model; U = get_user_model(); U.objects.filter(username='admin').exists() or U.objects.create_superuser('admin', 'admin@localhost', os.environ['PANEL_ADMIN_PASSWORD'])"

    mkdir -p static

    ./manage.py collectstatic --noinput

    chown -R www-data /var/www/html/ocserv_pannel/

    # sudo rules in their own file, validated before use
    cat > /tmp/ocserv_panel.sudoers << '_EOF_'
www-data ALL = NOPASSWD: /usr/bin/ocpasswd
www-data ALL = NOPASSWD: /usr/bin/occtl
www-data ALL = NOPASSWD: /usr/bin/systemctl restart ocserv.service
www-data ALL = NOPASSWD: /usr/bin/systemctl status ocserv.service
_EOF_
    if visudo -c -f /tmp/ocserv_panel.sudoers; then
        install -m 440 /tmp/ocserv_panel.sudoers /etc/sudoers.d/ocserv_panel
    else
        echo -e "\e[0;31m"Invalid sudoers rules, not installed."\e[0m"
    fi
    rm -f /tmp/ocserv_panel.sudoers
}

PRO_SERVICES() {
    echo -e "\e[0;36m"Preparation Nginx"\e[0m"
    #################COPY CONFIG FILE
    rm -rf /etc/nginx/sites-enabled/default
    mv /var/www/html/ocserv_pannel/configs/ocserv_nginx.conf /etc/nginx/conf.d/
    mv /var/www/html/ocserv_pannel/configs/ocserv_uwsgi.service /lib/systemd/system
    systemctl daemon-reload;systemctl restart nginx ocserv_uwsgi.service;systemctl enable nginx ocserv_uwsgi.service;
    NGINX_STATE=`systemctl is-active nginx`
    if [    "$NGINX_STATE" = "active"  ]; then
        echo -e "\e[0;32m"Nginx Is Started."\e[0m"
    else
        echo -e "\e[0;31m"Nginx Is Not Running."\e[0m"
        exit 1
    fi
    OCSERV_STATE=`systemctl is-active ocserv`
    if [    "$OCSERV_STATE" = "active"  ]; then
        echo -e "\e[0;32m"Ocserv Is Started."\e[0m"
    else
        echo -e "\e[0;31m"Ocserv Is Not Running."\e[0m"
        exit 1
    fi  
        OCSERV_UWSGI_STATE=`systemctl is-active ocserv_uwsgi`
    if [    "$OCSERV_UWSGI_STATE" = "active"   ]; then
        echo -e "\e[0;32m"Ocserv_Uwsgi Is Started."\e[0m"
    else
        echo -e "\e[0;31m"Ocserv_Uwsgi Is Not Running."\e[0m"
        exit 1
    fi        
    
}

Config_Variable
Print_Variable
Install_Ocserv
Config_Ocserv
Config_Firewall
Config_System
INSTALL_PANNEL_Env
PRO_DIR
PRO_VENV
PRO_SERVICES

echo
echo "======================================"
echo -e "Panel URL:\t\e[34mhttp://${ipv4}/\e[0m"
echo -e "Panel user:\t\e[34madmin\e[0m"
echo -e "Panel pass:\t\e[34m${panel_admin_password}\e[0m"
echo -e "VPN:\t\t\e[34m${ipv4}:${port}\e[0m  user: \e[34m${username}\e[0m"
echo "Save the panel password now, it is not stored anywhere else."
echo "======================================"

