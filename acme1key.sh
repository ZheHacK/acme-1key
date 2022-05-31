#!/bin/bash

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt-get -y update" "apt-get -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "Silakan jalankan skrip di bawah pengguna root" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Sistem VPS saat ini tidak didukung, silakan gunakan sistem operasi utama" && exit 1

back2menu() {
    green "Operasi yang dipilih selesai"
    read -p "Silakan masukkan "y" untuk keluar, atau tekan tombol apa saja untuk kembali ke menu utama：" back2menuInput
    case "$back2menuInput" in
        y) exit 1 ;;
        *) menu ;;
    esac
}

install_acme(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    [[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl
    [[ -z $(type -P wget) ]] && ${PACKAGE_INSTALL[int]} wget
    [[ -z $(type -P socat) ]] && ${PACKAGE_INSTALL[int]} socat
    [[ -z $(type -P cron) && $SYSTEM =~ Debian|Ubuntu ]] && ${PACKAGE_INSTALL[int]} cron && systemctl start cron systemctl enable cron
    [[ -z $(type -P crond) && $SYSTEM == CentOS ]] && ${PACKAGE_INSTALL[int]} cronie && systemctl start crond && systemctl enable crond
    read -rp "Silakan masukkan email Anda yang terdaftar（contoh：admin@misaka.rest，atau biarkan kosong untuk menghasilkan secara otomatis）：" acmeEmail
    [[ -z $acmeEmail ]] && autoEmail=$(date +%s%N | md5sum | cut -c 1-32) && acmeEmail=$autoEmail@gmail.com
    curl https://get.acme.sh | sh -s email=$acmeEmail
    source ~/.bashrc
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
        green "Skrip aplikasi sertifikat Acme.sh berhasil diinstal！"
    else
        red "Maaf, skrip permintaan sertifikat Acme.sh gagal dipasang"
        green "saran di bawah ini："
        yellow "1. Periksa lingkungan jaringan VPS"
        yellow "2. Skrip mungkin tidak mengikuti waktu, disarankan untuk memposting tangkapan layar ke GitHub Issues atau grup TG untuk penyelidikan"
    fi
    back2menu
}

getSingleCert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "acme.sh tidak diinstal, tidak dapat melakukan operasi" && exit 1
    WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    realip=$(curl -sm8 ip.sb)
    read -rp "Silakan masukkan nama domain yang diselesaikan:" domain
    [[ -z $domain ]] && red "Tidak ada nama domain yang dimasukkan, operasi tidak dapat dilakukan！" && exit 1
    green "nama domain yang dimasukkan：$domain" && sleep 1
    domainIP=$(curl -sm8 ipget.net/?ip=misaka.sama."$domain")
    if [[ -n $(echo $domainIP | grep nginx) ]]; then
        domainIP=$(curl -sm8 ipget.net/?ip="$domain")
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            if [[ -n $(echo $realip | grep ":") ]]; then
                bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6
            else
                bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256
            fi
        else
            if [[ $domainIP == $ipv6 ]]; then
                bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6
            fi
            if [[ $domainIP == $ipv4 ]]; then
                bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256
            fi
        fi

        if [[ -n $(echo $domainIP | grep nginx) ]]; then
            yellow "Resolusi nama domain tidak valid, harap periksa apakah nama domain diisi dengan benar atau tunggu beberapa menit hingga resolusi selesai sebelum menjalankan skrip"
            exit 1
        elif [[ -n $(echo $domainIP | grep ":") || -n $(echo $domainIP | grep ".") ]]; then
            if [[ $domainIP != $ipv4 ]] && [[ $domainIP != $ipv6 ]] && [[ $domainIP != $realip ]]; then
                green "${domain} Hasil parsing：（$domainIP）"
                red "IP yang diselesaikan dengan nama domain saat ini tidak cocok dengan IP asli yang digunakan oleh VPS saat ini"
                green "saran di bawah ini："
                yellow "1. Pastikan CloudFlare dimatikan (hanya DNS), dan hal yang sama berlaku untuk situs web resolusi nama domain lainnya"
                yellow "2. Silakan periksa apakah IP yang disetel oleh resolusi DNS adalah IP asli dari VPS"
                yellow "3. Skrip mungkin tidak mengikuti waktu, disarankan untuk memposting tangkapan layar ke GitHub Issues atau grup TG untuk penyelidikan"
                exit 1
            fi
        fi
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

getDomainCert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "acme.sh tidak diinstal, tidak dapat melakukan operasi" && exit 1
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    read -rp "Harap masukkan nama domain generik yang perlu mengajukan permohonan sertifikat (format input: example.com) ：" domain
    [[ -z $domain ]] && red "Tidak ada nama domain yang dimasukkan, operasi tidak dapat dilakukan！" && exit 1
    if [[ $(echo ${domain:0-2}) =~ cf|ga|gq|ml|tk ]]; then
        red "Itu terdeteksi sebagai nama domain gratis Freenom. Itu tidak dapat diterapkan karena CloudFlare API tidak mendukungnya.！"
        back2menu
    fi
    read -rp "Silakan masukkan Kunci API Global CloudFlare：" GAK
    [[ -z $GAK ]] && red "Kunci API Global CloudFlare tidak dimasukkan, operasi tidak dapat dilakukan！" && exit 1
    export CF_Key="$GAK"
    read -rp "Silakan masukkan email login CloudFlare Anda：" CFemail
    [[ -z $domain ]] && red "Operasi tidak dapat dilakukan tanpa memasukkan email login CloudFlare！" && exit 1
    export CF_Email="$CFemail"
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${domain}" -d "${domain}" -k ec-256 --listen-v6
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${domain}" -d "${domain}" -k ec-256
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d "*.${domain}" --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

getSingleDomainCert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "Acme.sh tidak diinstal, tidak dapat melakukan operasi" && exit 1
    ipv4=$(curl -s4m8 https://ip.gs)
    ipv6=$(curl -s6m8 https://ip.gs)
    read -rp "Silakan masukkan nama domain yang ingin Anda ajukan sertifikatnya：" domain
    if [[ $(echo ${domain:0-2}) =~ cf|ga|gq|ml|tk ]]; then
        red "Itu terdeteksi sebagai nama domain gratis Freenom. Itu tidak dapat diterapkan karena CloudFlare API tidak mendukungnya.！"
        back2menu
    fi
    read -rp "Silakan masukkan Kunci API Global CloudFlare：" GAK
    [[ -z $GAK ]] && red "Kunci API Global CloudFlare tidak dimasukkan, operasi tidak dapat dilakukan！" && exit 1
    export CF_Key="$GAK"
    read -rp "Silakan masukkan email login CloudFlare Anda：" CFemail
    [[ -z $domain ]] && red "Operasi tidak dapat dilakukan tanpa memasukkan email login CloudFlare！" && exit 1
    export CF_Email="$CFemail"
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --listen-v6
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256
    fi
    bash ~/.acme.sh/acme.sh --install-cert -d "${domain}" --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
    checktls
}

checktls() {
    if [[ -f /root/cert.crt && -f /root/private.key ]]; then
        if [[ -s /root/cert.crt && -s /root/private.key ]]; then
            sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
            echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
            green "Aplikasi sertifikat berhasil! Sertifikat yang diminta oleh skrip（cert.crt）dan kunci pribadi（private.key）Disimpan ke /root folder"
            yellow "Jalur crt sertifikat adalah sebagai berikut:：/root/cert.crt"
            yellow "Jalur kunci pribadi adalah sebagai berikut:：/root/private.key"
            back2menu
        else
            red "Maaf, permintaan sertifikat gagal"
            green "saran di bawah ini："
            yellow "1. Periksa apakah firewall terbuka sendiri Jika Anda menggunakan mode aplikasi port 80, silakan tutup firewall atau lepaskan port 80."
            yellow "2. Beberapa aplikasi untuk nama domain yang sama dapat memicu kontrol risiko resmi Let's Encrypt, harap ubah nama domain atau tunggu 7 hari sebelum mencoba menjalankan skrip"
            yellow "3. Skrip mungkin tidak mengikuti waktu, disarankan untuk memposting tangkapan layar ke GitHub Issues atau grup TG untuk penyelidikan"
            back2menu
        fi
    fi
}

revoke_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "acme.sh tidak diinstal, tidak dapat melakukan operasi" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -rp "Silakan masukkan sertifikat nama domain yang akan dicabut (salin nama domain yang ditampilkan di bawah Main_Domain):" domain
    [[ -z $domain ]] && red "Tidak ada nama domain yang dimasukkan, operasi tidak dapat dilakukan！" && exit 1
    if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
        bash ~/.acme.sh/acme.sh --revoke -d ${domain} --ecc
        bash ~/.acme.sh/acme.sh --remove -d ${domain} --ecc
        rm -rf ~/.acme.sh/${domain}_ecc
        rm -f /root/cert.crt /root/private.key
        green "menarik kembali${domain}Sertifikat nama domain berhasil"
        back2menu
    else
        red "Masukan yang Anda masukkan tidak ditemukan${domain}Sertifikat nama domain, silakan periksa sendiri！"
        back2menu
    fi
}

renew_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "acme.sh tidak diinstal, tidak dapat melakukan operasi" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -rp "Sertifikat nama domain, silakan periksa sendiri :" domain
    [[ -z $domain ]] && red "Tidak ada nama domain yang dimasukkan, operasi tidak dapat dilakukan！" && exit 1
    if [[ -n $(bash ~/.acme.sh/acme.sh --list | grep $domain) ]]; then
        bash ~/.acme.sh/acme.sh --renew -d ${domain} --force --ecc
        checktls
        back2menu
    else
        red "Sertifikat nama domain ${domain} yang Anda masukkan tidak ditemukan, harap periksa kembali apakah nama domain dimasukkan dengan benar"
        back2menu
    fi
}

uninstall() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "Uninstaller gagal menjalankan Acme.sh tidak diinstal" && exit 1
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --uninstall
    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
    rm -rf ~/.acme.sh
    rm -f acme1key.sh
    back2menu
}

menu() {
    clear
    red "=================================="
    echo "                           "
    red "    Skrip aplikasi sekali klik sertifikat nama domain Acme.sh     "
    red "          oleh stasiun rusak Misaka           "
    echo "                           "
    red "  Site: https://owo.misaka.rest  "
    echo "                           "
    red "=================================="
    echo "                           "
    green "1. Instal skrip aplikasi sertifikat nama domain Acme.sh (harus diinstal)"
    green "2. Mengajukan permohonan sertifikat nama domain tunggal (80 aplikasi port)"
    green "3. Mengajukan permohonan sertifikat nama domain tunggal (aplikasi CF API) (tidak diperlukan resolusi) (nama domain freenom tidak didukung)"
    green "4. Mengajukan permohonan sertifikat nama domain generik (aplikasi CF API) (tidak diperlukan resolusi) (nama domain freenom tidak didukung)"
    green "5. Cabut dan hapus sertifikat yang diminta"
    green "6. Perpanjang sertifikat nama domain secara manual"
    green "7. Copot pemasangan skrip aplikasi sertifikat nama domain Acme.sh"
    green "0. berhenti"
    echo "         "
    read -rp "Silakan masukkan angka:" NumberInput
    case "$NumberInput" in
        1) install_acme ;;
        2) getSingleCert ;;
        3) getSingleDomainCert ;;
        4) getDomainCert ;;
        5) revoke_cert ;;
        6) renew_cert ;;
        7) uninstall ;;
        *) exit 1 ;;
    esac
}

menu
