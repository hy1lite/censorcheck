#!/usr/bin/env bash

# -----------------------------------------
# Censor-check script
# Автор скрипта Nikola Tesla ©, по багам, вопросам пишите в ТГ https://t.me/tracerlab 
# Некоторые функции экспериментальные
# -----------------------------------------

TIMEOUT=4
RETRIES=2
MAX_PARALLEL=10
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
IP_VERSION=4
PROXY=""
VERBOSE=false
DEBUG=false

RIPE_API_KEY="5a5edf32-179b-4783-b2a4-e96b0506ce36" 
REALITY_SNI="max.ru"

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -d|--debug)
      DEBUG=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

DOMAINS=(
  "youtube.com"
  "instagram.com"
  "facebook.com"
  "x.com"
  "patreon.com"
  "linkedin.com"
  "signal.org"
  "tiktok.com"
  "api.telegram.org"
  "web.whatsapp.com"
  "discord.com"
  "viber.com"
  "chatgpt.com"
  "grok.com"
  "reddit.com"
  "twitch.tv"
  "netflix.com"
  "rutracker.org"
  "nnmclub.to"
  "digitalocean.com"
  "api.cloudflare.com"
  "speedtest.net"
  "aws.amazon.com"
  "ooni.org"
  "amnezia.org"
  "torproject.org"
  "proton.me"
  "github.com"
  "google.com"
)

AI_DOMAINS=(
  "chatgpt.com"
  "grok.com"
  "netflix.com"
)

RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
GREEN="\033[32m"
BLUE="\033[34m"
RESET="\033[0m"
ITALIC="\033[3m"
RED_ITALIC="\033[31;3m"
GREEN_ITALIC="\033[32;3m"
YELLOW_ITALIC="\033[33;3m"
BLUE_ITALIC="\033[34;3m"
DIM="\033[2;90m"

DOMAIN_WIDTH=22
LINE_SEP="----------------------------------------------------------------------"

# Чек на заглушки
RKN_STUB_IPS=(
  "195.208.4.1"    # Ростелеком
  "195.208.5.1"    # Ростелеком
  "188.186.157.35" # МТС
  "80.93.183.168"  # Билайн
  "213.87.154.141" # МТС
  "92.101.255.255" # Мегафон
)

is_rkn_spoof() {
  local ip="$1"
  for stub in "${RKN_STUB_IPS[@]}"; do
    [[ "$ip" == "$stub" ]] && return 0
  done
  return 1
}

install_missing_deps() {
  local deps=("curl" "nslookup" "nc" "openssl" "date" "awk" "python3")
  local missing=()

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null; then
      missing+=("$dep")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    return 0
  fi

  echo "Missing dependencies: ${missing[*]}. Installing automatically..."

  local prefix=""
  if [ "$(id -u)" -eq 0 ]; then
    prefix=""
  elif command -v sudo >/dev/null 2>&1; then
    prefix="sudo "
  else
    echo "You are not root, and sudo is not available."
    exit 1
  fi

  local pkg_mgr=""
  local update_cmd=""
  local quiet_update_cmd=""
  local install_cmd=""
  local quiet_install_cmd=""
  local pkg_names=()

  if [ -f /etc/debian_version ] || grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    pkg_mgr="apt"
    update_cmd="apt update -y"
    quiet_update_cmd="apt update -y -q"
    install_cmd="apt install -y"
    quiet_install_cmd="apt install -y -q"
    for dep in "${missing[@]}"; do
      case "$dep" in
        curl) pkg_names+=("curl") ;;
        nslookup) pkg_names+=("dnsutils") ;;
        nc) pkg_names+=("netcat-openbsd") ;;
        openssl) pkg_names+=("openssl") ;;
        date) pkg_names+=("coreutils") ;;
        awk) pkg_names+=("gawk") ;;
        python3) pkg_names+=("python3") ;;
      esac
    done
  elif [ -f /etc/fedora-release ] || grep -qi "fedora" /etc/os-release 2>/dev/null; then
    pkg_mgr="dnf"
    update_cmd="dnf check-update -y"
    quiet_update_cmd="dnf check-update -y --quiet"
    install_cmd="dnf install -y"
    quiet_install_cmd="dnf install -y --quiet"
    for dep in "${missing[@]}"; do
      case "$dep" in
        curl) pkg_names+=("curl") ;;
        nslookup) pkg_names+=("bind-utils") ;;
        nc) pkg_names+=("nc") ;;
        openssl) pkg_names+=("openssl") ;;
        date) pkg_names+=("coreutils") ;;
        awk) pkg_names+=("gawk") ;;
        python3) pkg_names+=("python3") ;;
      esac
    done
  elif [ -f /etc/centos-release ] || grep -qi "centos\|rhel" /etc/os-release 2>/dev/null; then
    if command -v dnf >/dev/null; then
      pkg_mgr="dnf"
      update_cmd="dnf check-update -y"
      quiet_update_cmd="dnf check-update -y --quiet"
      install_cmd="dnf install -y"
      quiet_install_cmd="dnf install -y --quiet"
    else
      pkg_mgr="yum"
      update_cmd="yum check-update -y"
      quiet_update_cmd="yum check-update -y --quiet"
      install_cmd="yum install -y"
      quiet_install_cmd="yum install -y --quiet"
    fi
    for dep in "${missing[@]}"; do
      case "$dep" in
        curl) pkg_names+=("curl") ;;
        nslookup) pkg_names+=("bind-utils") ;;
        nc) pkg_names+=("nc") ;;
        openssl) pkg_names+=("openssl") ;;
        date) pkg_names+=("coreutils") ;;
        awk) pkg_names+=("gawk") ;;
        python3) pkg_names+=("python3") ;;
      esac
    done
  elif [ -f /etc/arch-release ] || grep -qi "arch" /etc/os-release 2>/dev/null; then
    pkg_mgr="pacman"
    update_cmd="pacman -Sy --noconfirm"
    quiet_update_cmd="pacman -Sy --noconfirm -qq"
    install_cmd="pacman -S --noconfirm"
    quiet_install_cmd="pacman -S --noconfirm -qq"
    for dep in "${missing[@]}"; do
      case "$dep" in
        curl) pkg_names+=("curl") ;;
        nslookup) pkg_names+=("bind") ;;
        nc) pkg_names+=("openbsd-netcat") ;;
        openssl) pkg_names+=("openssl") ;;
        date) pkg_names+=("coreutils") ;;
        awk) pkg_names+=("gawk") ;;
        python3) pkg_names+=("python3") ;;
      esac
    done
  else
    echo "Unsupported distribution. Please install dependencies manually."
    exit 1
  fi

  ${prefix}${quiet_update_cmd} >/dev/null 2>&1
  for pkg in "${pkg_names[@]}"; do
    ${prefix}${quiet_install_cmd} "$pkg" >/dev/null 2>&1
  done
}

install_missing_deps

fetch_code() {
  local proxy_opt=""
  if [[ -n "$PROXY" ]]; then
    if [[ "$PROXY" == http://* ]]; then
      proxy_opt="--proxy $PROXY"
    else
      proxy_opt="--proxy socks5://$PROXY"
    fi
  fi

  curl -s -o /dev/null \
       --retry "$RETRIES" \
       --connect-timeout "$TIMEOUT" \
       --max-time "$TIMEOUT" \
       -$IP_VERSION \
       -A "$USER_AGENT" \
       $proxy_opt \
       -w "%{http_code}" \
       "$1"
}

check_keyword_blocking() {
  local domain="$1"
  local test_url="https://$domain"
  
  local dpi_response
  dpi_response=$(curl -s -A "Suspicious-Agent TLS/1.3" --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$test_url" 2>/dev/null)
  
  if echo "$dpi_response" | grep -qi "blocked\|forbidden\|access.denied\|roscomnadzor\|rkn\|firewall\|censorship\|prohibited\|restricted"; then
    return 0  
  fi
  
  local sni_code
  sni_code=$(curl -s -o /dev/null --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" --resolve "$domain:443:192.0.2.1" "$test_url" -w "%{http_code}" 2>/dev/null)
  
  if [[ "$sni_code" =~ [45][0-9][0-9] || "$sni_code" == "000" ]]; then
    return 0 
  fi
  
  return 1 
}

check_certificate() {
  local domain="$1"
  local cert_info
  cert_info=$(timeout "$TIMEOUT" openssl s_client -connect "$domain:443" -servername "$domain" -CApath /etc/ssl/certs -verify 5 < /dev/null 2>&1)
  
  if echo "$cert_info" | grep -q "Verification error:" || ! echo "$cert_info" | grep -q "Verification: OK"; then
    $VERBOSE && echo "TLS verification failed for $domain"
    return 1
  fi
  
  local not_after=$(echo "$cert_info" | openssl x509 -noout -dates 2>/dev/null | grep "notAfter" | cut -d= -f2)
  if [[ -n "$not_after" ]]; then
    local expire_epoch=$(date -d "$not_after" +%s 2>/dev/null)
    local current_epoch=$(date +%s)
    if [[ $expire_epoch -lt $current_epoch ]]; then
      $VERBOSE && echo "Certificate expired for $domain"
      return 1
    fi
    return 0
  fi
  return 1
}

check_domain() {
  local domain="$1"
  local block_type="UNKNOWN"
  local status_color=$RED
  local status_text="BLOCKED"

  local ips
  ips=$(timeout "$TIMEOUT" nslookup "$domain" 2>/dev/null | awk '/^Address: / && !/#/ {print $2}')
  
  if [[ -z "$ips" ]]; then
    block_type="DNS"
    printf "%-${DOMAIN_WIDTH}s  ${RED_ITALIC}%s${RESET} (${YELLOW}%s${RESET})\n" "$domain" "$status_text" "$block_type"
    echo "STATUS:BLOCKED"
    return
  fi

  for ip in $ips; do
    if is_rkn_spoof "$ip"; then
      block_type="DNS-SPOOF"
      printf "%-${DOMAIN_WIDTH}s  ${RED_ITALIC}%s${RESET} (${YELLOW}%s${RESET}) ${RED}[RKN stub: %s]${RESET}\n" \
        "$domain" "$status_text" "$block_type" "$ip"
      echo "STATUS:BLOCKED"
      return
    fi
  done

  local ip_ok=false
  local port_443_ok=false
  local port_80_ok=false
  
  for ip in $ips; do
    if nc -z -w "$TIMEOUT" "$ip" 443 2>/dev/null; then
      ip_ok=true
      port_443_ok=true
      break
    fi
  done
  
  if ! $port_443_ok; then
    for ip in $ips; do
      if nc -z -w "$TIMEOUT" "$ip" 80 2>/dev/null; then
        port_80_ok=true
        ip_ok=true
        break
      fi
    done
  fi

  if ! $ip_ok; then
    block_type="IP/TCP"
    printf "%-${DOMAIN_WIDTH}s  ${RED_ITALIC}%s${RESET} (${YELLOW}%s${RESET})\n" "$domain" "$status_text" "$block_type"
    echo "STATUS:BLOCKED"
    return
  fi

  local cert_status=""
  if check_certificate "$domain"; then
    cert_status="✓TLS"
  else
    cert_status="✗TLS"
    block_type="TLS/SSL"
  fi

  local http_code https_code
  http_code=$(fetch_code "http://$domain")
  https_code=$(fetch_code "https://$domain")

  if [[ "$http_code" =~ 3[0-9][0-9] ]]; then
    $VERBOSE && echo "HTTP redirect detected for $domain, falling back to HTTPS"
    http_code="$https_code"
  fi

  if [[ "$http_code" == "000" && "$https_code" == "000" ]]; then
    if $ip_ok; then
      block_type="HTTP(S)"
    else
      block_type="IP/HTTP"
    fi
  elif [[ "$http_code" =~ [45][0-9][0-9] && "$https_code" =~ [45][0-9][0-9] ]]; then
    block_type="HTTP-RESPONSE"
  fi

  if check_keyword_blocking "$domain"; then
    if [[ "$block_type" != "UNKNOWN" ]]; then
      block_type="$block_type/DPI"
    else
      block_type="DPI/KEYWORD"
    fi
  fi

  if [[ " ${AI_DOMAINS[*]} " =~ " ${domain} " ]]; then
    local ai_response
    ai_response=$(curl -s -A "$USER_AGENT" \
      -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
      -H "Accept-Language: en-US,en;q=0.5" \
      -H "Upgrade-Insecure-Requests: 1" \
      -H "Sec-Fetch-Dest: document" \
      -H "Sec-Fetch-Mode: navigate" \
      -H "Sec-Fetch-Site: none" \
      -H "Sec-Fetch-User: ?1" \
      -H "Connection: keep-alive" \
      --compressed \
      --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "https://$domain" 2>/dev/null)
    if echo "$ai_response" | grep -qi "sorry, you have been blocked\|you are unable to access\|not available in your region\|restricted in your country\|access denied due to location\|blocked in your area\|unable to load site\|if you are using a vpn\|Not Available"; then
      block_type="REGIONAL"
      http_code="000"  
      https_code="000"
    elif echo "$ai_response" | grep -qi "just a moment\|enable javascript and cookies"; then
      block_type=""  
      http_code="200"  
      https_code="200"
    fi
  fi

  if [[ "$http_code" == "000" && "$https_code" == "000" ]]; then
    printf "%-${DOMAIN_WIDTH}s  ${RED_ITALIC}%s${RESET} (${YELLOW}%s${RESET}) ${cert_status}\n" "$domain" "$status_text" "$block_type"
    echo "STATUS:BLOCKED"
  elif [[ "$http_code" =~ [23][0-9][0-9] || "$https_code" =~ [23][0-9][0-9] ]]; then
    printf "%-${DOMAIN_WIDTH}s  ${GREEN_ITALIC}%s${RESET} ${cert_status}\n" "$domain" "OK"
    echo "STATUS:OK"
  else
    printf "%-${DOMAIN_WIDTH}s  ${YELLOW_ITALIC}%s${RESET} (${BLUE}%s${RESET}) ${cert_status}\n" "$domain" "PARTIAL" "$block_type"
    echo "STATUS:PARTIAL"
  fi
}

animate() {
  local total=$1
  local tmpdir=$2
  local i=0
  
  local frames=(
    "🤬 🔨       🌐"
    "🤬  🔨      🌐"
    "🤬   🔨     🌐"
    "🤬    🔨    🌐"
    "🤬     🔨   🌐"
    "🤬      🔨  🌐"
    "🤬       💥 💔"
    "🤬        🔥💨"
  )

  local funny_texts=(
    "Роскомнадзор заблокировал сам себя. Ждем..."
    "Объясняем ТСПУ, что это просто картинки с котиками..."
    "Маскируем Reality-трафик под доставку ВкусВилл..."
    "Ищем свободный IP в реестре запрещенных сайтов..."
    "Оформляем VLESS как доступ к Госуслугам..."
    "РКН снова забанил 127.0.0.1. Пытаемся выжить..."
    "Оборачиваем BGP-маршруты в шапочку из фольги..."
    "Настраиваем передачу пакетов голубиной почтой..."
    "Спорим с провайдером о цифровой независимости..."
  )

  tput civis 2>/dev/null

  while true; do
    local done_count=$(ls "$tmpdir"/*.txt 2>/dev/null | wc -l)
    
    local frame_idx=$(( (i / 2) % ${#frames[@]} ))
    local frame="${frames[$frame_idx]}"
    
    local text_idx=$(( (i / 50) % ${#funny_texts[@]} ))
    local current_text="${funny_texts[$text_idx]}"
    
    printf "\r[${GREEN}%2d${RESET}/${YELLOW}%d${RESET}] %s  ${CYAN}%s${RESET}\e[K" \
      "$done_count" "$total" "$frame" "$current_text"
    
    sleep 0.2
    i=$(( i + 1 ))
  done
}

clear
echo "======================================================================"
echo "              Network Censorship Checker by Nikola Tesla              "
echo "======================================================================"
echo

printf "%-${DOMAIN_WIDTH}s  %-8s %s\n" "Domain" "Status" "Block Type"
echo "$LINE_SEP"

start_time=$(date +%s)

TMPDIR_RESULTS=$(mktemp -d)

animate "${#DOMAINS[@]}" "$TMPDIR_RESULTS" &
ANIM_PID=$!

job_pids=()

for i in "${!DOMAINS[@]}"; do
  d="${DOMAINS[$i]}"
  check_domain "$d" > "$TMPDIR_RESULTS/$i.txt" &
  job_pids+=($!)

  while (( $(jobs -p | wc -l) > MAX_PARALLEL )); do
    wait -n 2>/dev/null
  done
done

wait "${job_pids[@]}" 2>/dev/null

kill "$ANIM_PID" 2>/dev/null
wait "$ANIM_PID" 2>/dev/null 
printf "\r\e[K"              
tput cnorm 2>/dev/null       

count_ok=0
count_blocked=0
count_partial=0

for i in "${!DOMAINS[@]}"; do
  grep -v "^STATUS:" "$TMPDIR_RESULTS/$i.txt"
  status=$(grep "^STATUS:" "$TMPDIR_RESULTS/$i.txt" | cut -d: -f2)
  case "$status" in
    OK)      (( count_ok++ ))      ;;
    BLOCKED) (( count_blocked++ )) ;;
    PARTIAL) (( count_partial++ )) ;;
  esac
done

rm -rf "$TMPDIR_RESULTS"

total_domains=${#DOMAINS[@]}

echo "$LINE_SEP"
printf "${GREEN}OK: %d${RESET}  ${RED}BLOCKED: %d${RESET}  ${YELLOW}PARTIAL: %d${RESET}  ${DIM}Total: %d${RESET}\n" \
  "$count_ok" "$count_blocked" "$count_partial" "$total_domains"

# Чекаем IP сервера нужен для Atlas
CURRENT_IP=$(curl -s -4 --connect-timeout 3 https://api.ipify.org 2>/dev/null)

if [[ -n "$CURRENT_IP" ]] && [[ -n "$RIPE_API_KEY" ]]; then
  echo "$LINE_SEP"
  
  # Чекер 443 порта, нужен для Atlas
  if ! ss -tuln 2>/dev/null | grep -qE "(0\.0\.0\.0|\*|$CURRENT_IP):443\b"; then
    echo -e "${DIM}Радар ТСПУ отменен. Для корректной проверки запустите VPN (Xray/3X-UI)${RESET}"
  else
    echo -e "Опрос сетей РФ: РТК, МТС, МГТС, Билайн, Corbina, ТТК, РТК-Юг (Сочи)"
    
    TMP_ATLAS=$(mktemp)
    TMP_ATLAS_DEBUG=$(mktemp)
    python3 -c "
import sys, json, time, urllib.request

api_key = sys.argv[1]
target_ip = sys.argv[2]
sni = sys.argv[3]
debug = (len(sys.argv) > 4 and sys.argv[4] == 'true')

def dlog(msg):
    if debug:
        print(f'[DEBUG] {msg}', file=sys.stderr, flush=True)

dlog(f'target_ip={target_ip} sni={sni}')

url = 'https://atlas.ripe.net/api/v2/measurements/'
data = {
    'definitions': [{
        'target': target_ip, 
        'description': 'Reality TLS Handshake',
        'type': 'sslcert',
        'port': 443,
        'hostname': sni,
        'af': 4
    }],
    'probes': [
        {'requested': 4, 'type': 'asn', 'value': 12389, 'tags': {'include': ['system-ipv4-works']}},
        {'requested': 4, 'type': 'asn', 'value': 8402,  'tags': {'include': ['system-ipv4-works']}},
        {'requested': 4, 'type': 'asn', 'value': 25513, 'tags': {'include': ['system-ipv4-works']}},
        {'requested': 4, 'type': 'asn', 'value': 8359,  'tags': {'include': ['system-ipv4-works']}},
        {'requested': 4, 'type': 'asn', 'value': 3216,  'tags': {'include': ['system-ipv4-works']}},
        {'requested': 3, 'type': 'asn', 'value': 20485, 'tags': {'include': ['system-ipv4-works']}},
        {'requested': 1, 'type': 'asn', 'value': 25490, 'tags': {'include': ['system-ipv4-works']}}
    ],
    'is_oneoff': True
}

req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), 
                             headers={'Content-Type': 'application/json', 'Authorization': f'Key {api_key}'})
try:
    with urllib.request.urlopen(req) as response:
        resp_data = json.loads(response.read().decode())
        msm_id = resp_data['measurements'][0]
        dlog(f'measurement_id={msm_id}')
except Exception as e:
    dlog(f'API create error: {type(e).__name__}: {e}')
    print('ERROR API_FAIL')
    sys.exit(0)

results_url = f'https://atlas.ripe.net/api/v2/measurements/{msm_id}/results/'
results = []
start_time = time.time()

for attempt in range(25):
    time.sleep(2)
    try:
        with urllib.request.urlopen(results_url) as response:
            results = json.loads(response.read().decode())
            elapsed = int(time.time() - start_time)
            dlog(f'poll {attempt+1}/25 [{elapsed}s]: results={len(results)}/24')
            if len(results) >= 24: 
                break
    except Exception as e:
        dlog(f'poll {attempt+1} error: {type(e).__name__}: {e}')

if debug:
    dlog(f'FINAL: total={len(results)} after {int(time.time()-start_time)}s')
    for i, probe in enumerate(results):
        prb_id = probe.get('prb_id', '?')
        asn = probe.get('asn', '?')
        keys = [k for k in ('cert','method','alert','err') if k in probe]
        err = probe.get('err', '')
        dlog(f'  probe[{i}] prb_id={prb_id} asn={asn} keys={keys} err={err!r}')

if not results:
    print('ERROR NO_DATA')
    sys.exit(0)

blocked = 0
for probe in results:
    if 'cert' in probe or 'method' in probe or 'alert' in probe:
        pass 
    else:
        blocked += 1 

total = len(results)
success = total - blocked
print(f'OK {total} {success} {blocked}')
    " "$RIPE_API_KEY" "$CURRENT_IP" "$REALITY_SNI" "$DEBUG" > "$TMP_ATLAS" 2>"$TMP_ATLAS_DEBUG" &
    
    ATLAS_PID=$!

    wave=(" " "▂" "▃" "▄" "▅" "▆" "▇" "█" "▇" "▆" "▅" "▄" "▃" "▂")
    wave_len=${#wave[@]}
    i=0
    
    tput civis 2>/dev/null 
    
    while kill -0 $ATLAS_PID 2>/dev/null; do
      pulse=""
      for (( k=0; k<8; k++ )); do
        idx=$(( (i + k * 2) % wave_len ))
        case $(( k % 4 )) in
          0) pulse+="${CYAN}${wave[$idx]}${RESET}"  ;;
          1) pulse+="${BLUE}${wave[$idx]}${RESET}"  ;;
          2) pulse+="${CYAN}${wave[$idx]}${RESET}"  ;;
          3) pulse+="${GREEN}${wave[$idx]}${RESET}" ;;
        esac
      done
      printf "\r${CYAN}Запуск радара ТСПУ (Ожидайте проверки)${RESET} %b\e[K" "$pulse"
      sleep 0.1
      ((i++))
    done
    
    wait $ATLAS_PID
    tput cnorm 2>/dev/null 
    
    printf "\r${CYAN}Запуск радара ТСПУ${RESET}\e[K\n"

    ATLAS_RESULT=$(cat "$TMP_ATLAS")
    rm -f "$TMP_ATLAS"

    STATUS=$(echo "$ATLAS_RESULT" | awk '{print $1}')
    
    if [[ "$STATUS" == "OK" ]]; then
      TOTAL_PROBES=$(echo "$ATLAS_RESULT" | awk '{print $2}')
      SUCCESS_PROBES=$(echo "$ATLAS_RESULT" | awk '{print $3}')
      BLOCKED_PROBES=$(echo "$ATLAS_RESULT" | awk '{print $4}')
      
      if (( TOTAL_PROBES > 0 )); then
        SUCCESS_PERCENT=$(( SUCCESS_PROBES * 100 / TOTAL_PROBES ))
      else
        SUCCESS_PERCENT=0
      fi
      
      if (( SUCCESS_PERCENT == 100 )); then
        COLOR=$GREEN
        STAT_TEXT="ПОЛНЫЙ ДОСТУП ИЗ РФ"
      elif (( SUCCESS_PERCENT > 50 )); then
        COLOR=$YELLOW
        STAT_TEXT="ЧАСТИЧНАЯ БЛОКИРОВКА (Дропы у части провайдеров)"
      else
        COLOR=$RED
        STAT_TEXT="КРИТИЧНАЯ БЛОКИРОВКА ТСПУ (IP недоступен)"
      fi

      echo -e "Зондов ответило: ${CYAN}${TOTAL_PROBES}${RESET} | Пробились: ${GREEN}${SUCCESS_PROBES}${RESET} | Заблокированы: ${RED}${BLOCKED_PROBES}${RESET}"
      echo -e "ТСПУ Статус: ${COLOR}${SUCCESS_PERCENT}% ${STAT_TEXT}${RESET}"
      
    else
      echo -e "${YELLOW}Не удалось получить данные.${RESET}"
    fi

    if $DEBUG && [[ -s "$TMP_ATLAS_DEBUG" ]]; then
      echo "$LINE_SEP"
      echo -e "${CYAN}[DEBUG] RIPE Atlas log:${RESET}"
      cat "$TMP_ATLAS_DEBUG"
    fi
    rm -f "$TMP_ATLAS_DEBUG"
  fi
fi

echo "$LINE_SEP"

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
elapsed_minutes=$((elapsed_time / 60))
elapsed_seconds=$((elapsed_time % 60))

if (( elapsed_minutes > 0 )); then
  echo "Test completed in ${elapsed_minutes}m ${elapsed_seconds}s."
else
  echo "Test completed in ${elapsed_seconds}s."
fi

if $DEBUG; then
  echo "$LINE_SEP"
  echo -e "${CYAN}=== DEBUG INFO ===${RESET}"
  echo "Script:        $0"
  echo "Bash version:  $BASH_VERSION"
  echo "OS:            $(uname -a 2>/dev/null || echo 'n/a')"
  echo "Date:          $(date)"
  echo "Public IP:     ${CURRENT_IP:-not detected}"
  echo "Reality SNI:   $REALITY_SNI"
  echo "Total domains: ${#DOMAINS[@]}"
  echo "Max parallel:  $MAX_PARALLEL"
  echo "Timeout:       ${TIMEOUT}s"
  echo "Retries:       $RETRIES"
  echo "Elapsed:       ${elapsed_time}s"
  echo
  echo "--- Listening ports (ss -tlnp | head -20) ---"
  ss -tlnp 2>/dev/null | head -20 || echo 'ss not available'
  echo
  echo "--- Tools versions ---"
  echo "curl:    $(curl --version 2>/dev/null | head -1)"
  echo "openssl: $(openssl version 2>/dev/null)"
  echo "python3: $(python3 --version 2>/dev/null)"
  echo "nc:      $(nc -h 2>&1 | head -1)"
  echo
  echo "--- DNS test (nslookup google.com) ---"
  nslookup google.com 2>&1 | head -10
  echo
  echo "--- Ping test (1.1.1.1) ---"
  ping -c 2 -W 2 1.1.1.1 2>&1 | tail -5
fi

echo -e "Follow: $(tput setaf 6)https://t.me/tracerlab$(tput sgr0)"