#!/usr/bin/env bash

# REQUIREMENTS: figlet lolcat
## CONFIG

text="D T Production"
#text="$(hostname -A | cut -d" " -f1)"

## END CONFIG

/usr/bin/figlet "$text" | /usr/bin/lolcat -f

# get load averages
IFS=" " read LOAD1 LOAD5 LOAD15 <<<$(/bin/cat /proc/loadavg | awk '{ print $1,$2,$3 }')
# get free memory
IFS=" " read USED FREE TOTAL <<<$(free -htm | grep "Mem" | awk {'print $3,$4,$2'})
# get processes
PROCESS=`ps -eo user=|sort|uniq -c | awk '{ print $2 " " $1 }'`
PROCESS_ALL=`echo "$PROCESS"| awk {'print $2'} | awk '{ SUM += $1} END { print SUM }'`
PROCESS_ROOT=`echo "$PROCESS"| grep root | awk {'print $2'}`
PROCESS_USER=`echo "$PROCESS"| grep -v root | awk {'print $2'} | awk '{ SUM += $1} END { print SUM }'`

W="\e[0;39m"
G="\e[1;32m"

echo -e "
${W}System Information:
$W  Distro......: $W`cat /etc/*release | grep "PRETTY_NAME" | cut -d "=" -f 2- | sed 's/"//g'`
$W  Kernel......: $W`uname -sr`
$W  Uptime......: $W`uptime -p`
$W  Load........: $G$LOAD1$W (1m), $G$LOAD5$W (5m), $G$LOAD15$W (15m)
$W  Processes...:$W $G$PROCESS_ROOT$W (root), $G$PROCESS_USER$W (user) | $G$PROCESS_ALL$W (total)
$W  CPU.........: $W`cat /proc/cpuinfo | grep "model name" | cut -d ' ' -f3- | awk {'print $0'} | head -1`
$W  Memory......: $G$USED$W used, $G$FREE$W free, $G$TOTAL$W in total$W"

echo ""

declare -a services=(
    "nginx.service"
    "mongod.service"
    "dt-login.service"
    "dt-admin.service"
    "dt-game-main.service"
    "dt-game-ru.service"
    "dt-game-pg13.service"
)

declare -a service_name=(
    "Nginx"
    "MongoDB"
    "DT Login Server"
    "DT Admin Server"
    "DT Main Server"
    "DT RU Server"
    "DT PG13 Server"
)

declare -a service_status=()
declare -a lengthened_service_name=()

max_length=0
for i in "${!service_name[@]}"; do
    if [  "${#service_name[$i]}" -gt ${max_length} ]; then
      (( max_length=${#service_name[$i]}+2 ))
    fi
done

for i in "${!service_name[@]}"; do
    (( dot_length=max_length-${#service_name[$i]} ))
    lengthened_service_name[$i]=${service_name[$i]}
    for (( ; dot_length>0; dot_length-- )); do
        lengthened_service_name[$i]+="."
    done
done

# Get service status
for i in "${services[@]}"; do
    service_status+=("$(systemctl is-active "${i}")")
done

for i in "${!service_status[@]}"
do
    if [[ "${service_status[$i]}" == "active" ]]; then
        line+="  \e[0m${lengthened_service_name[$i]}: \e[32m● ${service_status[$i]}\e[0m\n"
    else
        line+="  \e[0m${lengthened_service_name[$i]}: \e[31m▲ ${service_status[$i]}\e[0m\n"
    fi
done
echo -e "\nService Status:"
echo -e "$line"


echo "Storage Information"
mountpoints=('/dev/sda2')
barWidth=50
maxDiscUsage=90
clear="\e[39m\e[0m"
dim="\e[2m"
barclear=""

for point in "${mountpoints[@]}"; do
    line=$(df -h "${point}")
    usagePercent=$(echo "$line"|tail -n1|awk '{print $5;}'|sed 's/%//')
    usedBarWidth=$((($usagePercent*$barWidth)/100))
    barContent=""
    color="\e[32m"
    if [ "${usagePercent}" -ge "${maxDiscUsage}" ]; then
        color="\e[31m"
    fi
    barContent="${color}"
    for sep in $(seq 1 $usedBarWidth); do
        barContent="${barContent}|"
    done
    barContent="${barContent}${clear}${dim}"
    for sep in $(seq 1 $(($barWidth-$usedBarWidth))); do
        barContent="${barContent}-"
    done
    bar="[${barContent}${clear}]"
	echo "${line}" | awk  '{if ($1 != "Filesystem") printf("%-30s%+3s used out of %+5s\n", $1, $3, $2); }' | sed -e 's/^/  /'
	echo -e "${bar}" | sed -e 's/^/  /'
echo ""

done


# fail2ban-client status to get all jails, takes about ~70ms
jails=($(fail2ban-client status | grep "Jail list:" | sed "s/ //g" | awk '{split($2,a,",");for(i in a) print a[i]}'))

out="jail,failed,total,banned,total\n"

for jail in ${jails[@]}; do
    # slow because fail2ban-client has to be called for every jail (~70ms per jail)
    status=$(fail2ban-client status ${jail})
    failed=$(echo "$status" | grep -ioP '(?<=Currently failed:\t)[[:digit:]]+')
    totalfailed=$(echo "$status" | grep -ioP '(?<=Total failed:\t)[[:digit:]]+')
    banned=$(echo "$status" | grep -ioP '(?<=Currently banned:\t)[[:digit:]]+')
    totalbanned=$(echo "$status" | grep -ioP '(?<=Total banned:\t)[[:digit:]]+')
    out+="$jail,$failed,$totalfailed,$banned,$totalbanned\n"
done

printf "\nFail2Ban Statistics:\n"
printf $out | column -ts $',' | sed -e 's/^/  /'

# REQUIREMENTS: openssl
## CONFIG

certificates=(
    "/etc/letsencrypt/live/derguns.town/cert.pem"
    "/etc/letsencrypt/live/discord.derguns.town/cert.pem"
    "/etc/letsencrypt/live/report.derguns.town/cert.pem"
)

certificateNames=(
    "Main URL"
    "DT Discord"
    "Report URL"
 
)

## END CONFIG

expiry_date () {
    out=$(openssl x509 -enddate -noout -in "$1" | cut -d "=" -f 2)
    unix_date "$out"
}

unix_date () {
    date -d "$@" +%s
}

expires_in () {
    diff=$(( $1 - $2 ))
    expiresInHours=$(( $diff / 3600 ))

    if [ $expiresInHours -gt 48 ]; then
        echo "$(( $expiresInHours / 24 )) days"
    else
        echo "$expiresInHours hours"
    fi
}


echo ""
echo "TLS Certificates:"


for i in "${!certificates[@]}"; do
    cert="${certificates[$i]}"

    expires=$(expiry_date $cert)
    now=$(unix_date "now")
    inAWeek=$(unix_date "1 week")

    expiresIn=$(expires_in $expires $now)

    if [ $expires -le $now ]; then
        echo -e "  ${certificateNames[$i]}: \e[31m▲ expired\e[0m"
    elif [ $expires -le $inAWeek ]; then
        echo -e "  ${certificateNames[$i]}: \e[33m● expiring soon ($expiresIn left)\e[0m"
    else
        echo -e "  ${certificateNames[$i]}: \e[32m● expires in $expiresIn\e[0m"
    fi

echo ""
done

/usr/bin/fortune | /usr/bin/cowsay -f $(ls /usr/share/cowsay | shuf -n1) | /usr/bin/lolcat