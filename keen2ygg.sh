#!/bin/sh

file_exists() {
  local file="$1"
  [ -f "$file" ]
}

# Echo to stderr. Useful for printing script usage information.
echo_stderr() {
  >&2 echo "$@"
}

# Log the given message at the given level. All logs are written to stderr with a timestamp.
log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local script_name=$(basename "$0")
  echo_stderr -e "${timestamp} [${level}] [$script_name] ${message}"
}

# Replace text in a file using sed
file_replace_text() {
  original_text_regex="$1"
  replacement_text="$2"
  file="$3"

  sed -i "s|$original_text_regex|$replacement_text|" "$file" > /dev/null
}

# Function to get the IPv6 address from yggdrasilctl getself
get_ipv6_address() {
  yggdrasilctl getself | awk '/^IPv6 address:/ {print $3}'
}

load_peers() {
  log INFO "Download peers list" && curl https://raw.githubusercontent.com/GenkaOk/public-peers/refs/heads/master/nodes.csv > /tmp/nodes.csv
}

# Строка для хранения самых быстрых пиров
valid_peers=""
count_peers=3

get_rand_peers() {
  while [ $(echo "$valid_peers" | wc -w) -lt $count_peers ]; do
    # Получаем случайные 5 пиров
    rand_peers=$(awk -F',' 'NR>1 {print $3}' /tmp/nodes.csv | sort -R | head -n 10)

    # Удаляем символы возврата каретки
    rand_peers=$(echo "$rand_peers" | tr -d '\r')
    IFS=$'\n'
    set -- $rand_peers

    # Перебираем каждый выбранный пир и измеряем ping
    for peer in "$@"; do
      # Извлекаем адрес без протокола и порта
      address=$(echo "$peer" | sed -E 's/^.*:\/\/([^:/]+).*$/\1/')

      # Измеряем время пинга (в миллисекундах)
      ping_time=$(ping -c 1 -W 1 "$address" | awk -F'/' 'END {print $5}')

      # Проверяем на наличие времени пинга и если оно меньше 100
      if [ -n "$ping_time" ]; then
        # Сравниваем с 100 с помощью awk
        if echo "$ping_time" | awk '{exit !($1 < 100)}'; then
          log "DEBUG" "Found peer $peer with $ping_time ms"
          valid_peers="$valid_peers $peer" # Добавляем пир в список, если пинг меньше 100 мс
        fi
      fi
    done
  done
}

add_peers() {
  IFS=' '
  set -- $valid_peers
  peersConf=''
  # Добавляем пиров из валидного списка
  for peer in "$@"; do
    yggdrasilctl addpeer uri="$peer"
    if [ ! -n "$peersConf" ]; then
      peersConf="\"$peer\""
    else
      peersConf="$peersConf, \"$peer\""
    fi
    echo "Добавлен пир: $peer"
  done

  file_replace_text 'Peers: \[\]' "Peers: [$peersConf]" '/opt/etc/yggdrasil.conf'
}

confirm() {
  question=$1
  shift
  # Собираем аргументы в список (POSIX: нет массивов, работаем с позиционными)
  options_count=$#
  i=1
  # Собираем метки: два параллельных списка через строки: labels_keys и labels_vals
  labels_keys=""
  labels_vals=""

  # Формируем подсказку
  prompt=""
  idx=1
  while [ $idx -le $options_count ]; do
    eval opt=\${$idx}
    # короткая метка — первая буква в нижнем регистре (tr поддерживается в POSIX)
    first=$(printf "%s" "$opt" | awk '{print tolower(substr($0,1,1))}')
    # проверяем, встречалась ли такая метка ранее
    seen=0
    j=1
    while [ $j -lt $idx ]; do
      eval prev=\${$j}
      prevfirst=$(printf "%s" "$prev" | awk '{print tolower(substr($0,1,1))}')
      if [ "$prevfirst" = "$first" ]; then
        seen=1
        break
      fi
      j=$((j+1))
    done
    if [ $seen -eq 1 ]; then
      label=$idx
    else
      label=$first
    fi
    if [ -z "$prompt" ]; then
      prompt="${opt}/${label}"
    else
      prompt="${prompt} ${opt}/${label}"
    fi
    # добавляем в "словарь" метка->опция (разделитель — табуляция)
    labels_keys="${labels_keys}${label}
"
    labels_vals="${labels_vals}${opt}
"
    idx=$((idx+1))
  done

  prompt="(${prompt})"

  while :; do
    printf "%s %s: " "$question" "$prompt"
    if ! IFS= read -r ans; then
      # EOF — считать как отказ (вернуть 1)
      return 1
    fi
    # обрезаем пробелы по краям
    ans_trimmed=$(printf "%s" "$ans" | awk '{$1=$1;print}')
    if [ -z "$ans_trimmed" ]; then
      # пустой ввод — первый вариант
      # получить первый аргумент
      eval CONFIRM_CHOICE=\${1}
      return 0
    fi
    key=$(printf "%s" "$ans_trimmed" | awk '{print tolower($0)}')

    matched=""
    # 1) полное совпадение с одним из вариантов
    idx=1
    while [ $idx -le $options_count ]; do
      eval opt=\${$idx}
      lowopt=$(printf "%s" "$opt" | awk '{print tolower($0)}')
      if [ "$key" = "$lowopt" ]; then
        matched="$opt"
        break
      fi
      idx=$((idx+1))
    done

    # 2) если не найдено — по первой букве (метка буква)
    if [ -z "$matched" ]; then
      firstchar=$(printf "%s" "$key" | awk '{print substr($0,1,1)}')
      idx=1
      while [ $idx -le $options_count ]; do
        eval opt=\${$idx}
        optfirst=$(printf "%s" "$opt" | awk '{print tolower(substr($0,1,1))}')
        if [ "$firstchar" = "$optfirst" ]; then
          matched="$opt"
          break
        fi
        idx=$((idx+1))
      done
    fi

    # 3) если не найдено — по номеру
    if [ -z "$matched" ]; then
      # проверим, состоит ли key только из цифр
      case "$key" in
        *[!0-9]* ) : ;;
        *)
          # преобразуем в число и проверим диапазон
          # POSIX: арифметика через $(( ))
          num=$((key + 0))
          if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le "$options_count" ]; then
            eval matched=\${$num}
          fi
          ;;
      esac
    fi

    if [ -n "$matched" ]; then
      CONFIRM_CHOICE="$matched"
      # положительный только если выбран первый аргумент
      eval firstopt=\${1}
      if [ "$matched" = "$firstopt" ]; then
        return 0
      else
        return 1
      fi
    fi

    printf "Неверный ввод — попробуйте снова.\n"
  done
}

check_service() {
  cmd=$1

  # Выполнить команду, сохранить вывод и код возврата
  SERVICE_STATUS=$($cmd 2>&1)
  rc=$?

  SERVICE_ALIVE=no

  # Если команда завершилась с ошибкой — считаем сервис не живым
  if [ $rc -ne 0 ]; then
    return 1
  fi

  # Нормализуем вывод в одну строку (удаляем переводы строк и лишние пробелы)
  normalized=$(printf "%s" "$SERVICE_STATUS" | tr '\n' ' ' | awk '{$1=$1;print}')

  # Ищем характерные слова/фразы, обозначающие что сервис "alive" или "running"
  case "$normalized" in
    *alive*|*running*|*started*|*is\ running*|*active*)
      SERVICE_ALIVE=yes
      return 0
      ;;
    *)
      SERVICE_ALIVE=no
      return 1
      ;;
  esac
}

check_peers_empty() {
  cfg="/opt/etc/yggdrassil.conf"

  if [ ! -f "$cfg" ]; then
    return 1
  fi

  if grep -E -q '^[[:space:]]*Peers[[:space:]]*:[[:space:]]*\[\s*\][[:space:]]*$' "$cfg"; then
    return 0
  else
    return 1
  fi
}

log INFO "Updating OPKG..." && opkg update
log INFO "Installing curl, yggdrasil-go, radvd, iptables..." && opkg install curl yggdrasil-go radvd iptables

# Generate yggdrasil configuration
ygg_changed_config=
if file_exists "/opt/etc/yggdrasil.conf"; then
  log INFO "Yggdrasil configuration found"
  if confirm "Update configuration? (PublicKey, IPv6 will not changed)" "Yes" "No"; then
    # Update IfName: auto to IfName: yggdrasil
    if file_replace_text 'IfName: auto' 'IfName: yggdrasil' '/opt/etc/yggdrasil.conf'; then
      log INFO "Updated IfName in configuration to yggdrasil."
      ygg_changed_config=1
    else
      log ERROR "Failed to update IfName in configuration."
    fi
  else
    log INFO "Yggdrasil configuration skip"
  fi
else
  log INFO "Yggdrasil configuration not found, generating..."
  if yggdrasil -genconf > /opt/etc/yggdrasil.conf; then
    log INFO "Yggdrasil configuration generated successfully."

    if file_replace_text 'IfName: auto' 'IfName: yggdrasil' '/opt/etc/yggdrasil.conf'; then
      log INFO "Updated IfName in newly generated configuration to yggdrasil."
      ygg_changed_config=1
    else
      log ERROR "Failed to update IfName in newly generated configuration."
    fi
  else
    log ERROR "Failed to generate Yggdrasil configuration."
    exit 1
  fi
fi

if ! check_peers_empty; then
  log INFO "You have empty peers list"
fi

update_peers=
if confirm "Load peers list and add them?" "Yes" "No"; then
  log INFO "Load peers list" && load_peers
  log INFO "Search fastest peers..." && get_rand_peers
  update_peers=1
fi


# Generate yggdrasil init.d script
if file_exists "/opt/etc/init.d/S83yggdrasil"; then
  log INFO "Init.d Yggdrasil file already exists, no changes."
else
  ygg_changed_config=1
  log INFO "Creating init.d Yggdrasil file..."
  {
    echo '#!/bin/sh'
    echo
    echo 'ENABLED=yes'
    echo 'PROCS=yggdrasil'
    echo 'ARGS="-useconffile /opt/etc/yggdrasil.conf"'
    echo 'PREARGS=""'
    echo 'DESC=$PROCS'
    echo 'PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    echo
    echo '. /opt/etc/init.d/rc.func'
  } > /opt/etc/init.d/S83yggdrasil

  # Make the file executable
  if chmod +x /opt/etc/init.d/S83yggdrasil; then
    log INFO "Init.d Yggdrasil file created and made executable."
  else
    log ERROR "Failed to make init.d Yggdrasil file executable."
    exit 1
  fi
fi

log INFO "Check connection..."
ipv6_address=$(get_ipv6_address)
if [ -n "$ipv6_address" ]; then
  log INFO "Yggdrassil connected"
else
  ygg_changed_config=1 # Restart yggdrassil
fi

if [ -n "$ygg_changed_config" ]; then
  log INFO "Run yggdrasil"
  if /opt/etc/init.d/S83yggdrasil restart; then
    log INFO "Yggdrasil run successfully. Wait for connect 3 seconds..."
    sleep 3
  else
    log ERROR "Failed to run yggdrasil."
    exit 1
  fi
fi

# Get and log the IPv6 address
ipv6_address=$(get_ipv6_address)
if [ -n "$ipv6_address" ]; then
  log INFO "Retrieved IPv6 address: $ipv6_address"

  # Replace first symbol to 3
  ipv6_address_network="3${ipv6_address#?}"
  log INFO "IPv6 network: $ipv6_address_network/64"
else
  log ERROR "Failed to retrieve IPv6 address."
  exit 1
fi

if [ -n "$update_peers" ]; then
  log INFO "Add 3 fastest peers" && add_peers
fi

if file_exists "/opt/etc/init.d/S82radvd"; then
  if confirm "Update radvd configuration" "Yes" "No"; then
    rm "/opt/etc/init.d/S82radvd"
    rm "/opt/etc/radvd.conf"
  fi
fi

#### Create radvd init.d
radvd_changed_config=
if file_exists "/opt/etc/init.d/S82radvd"; then
  log INFO "Init.d radvd file already exists, no changes."
else
  radvd_changed_config=1
  log INFO "Creating init.d radvd file..."
  {
    echo '#!/bin/sh'
    echo
    echo 'ENABLED=yes'
    echo 'PROCS=radvd'
    echo 'ARGS="--config /opt/etc/radvd.conf"'
    echo 'PREARGS=""'
    echo 'DESC=$PROCS'
    echo 'PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    echo
    echo "ADDRESS='$ipv6_address_network/64'"
    echo
    echo '[ -z "$(ip a | grep "$ADDRESS")" ] && ip addr add $ADDRESS dev br0'
    echo
    echo '. /opt/etc/init.d/rc.func'
  } > /opt/etc/init.d/S82radvd

  # Make the file executable
  if chmod +x /opt/etc/init.d/S82radvd; then
    log INFO "Init.d radvd file created and made executable."
  else
    log ERROR "Failed to make init.d radvd file executable."
    exit 1
  fi
fi

#### Create radvd configuration
if file_exists "/opt/etc/radvd.conf"; then
  log INFO "/opt/etc/radvd.conf file exists"
else
  radvd_changed_config=1
  log INFO "Creating radvd configuration file..."
  {
    echo 'interface br0 {'
    echo '  AdvSendAdvert on;'
    echo '  AdvLinkMTU 1280;'
    echo '  MinRtrAdvInterval 30;'
    echo '  MaxRtrAdvInterval 100;'
    echo '  AdvHomeAgentFlag off;'
    echo
    echo "  prefix $ipv6_address_network/64 {"
    echo '      AdvOnLink on;'
    echo '      AdvAutonomous on;'
    echo '      AdvRouterAddr on;'
    echo '    };'
    echo '};'
  } > /opt/etc/radvd.conf
fi

#### Create iptables file
if file_exists "/opt/etc/ndm/netfilter.d/iptables.sh"; then
  log INFO "/opt/etc/ndm/netfilter.d/iptables.sh file exists"
else
  log INFO "Creating iptables file..."
  {
    echo '#!/bin/sh'
    echo
    echo 'if [ -z "$(ip6tables-save | grep CUSTOM6_FORWARD)" ]; then'
    echo '    ip6tables -w -N CUSTOM6_FORWARD;'
    echo '    ip6tables -w -A CUSTOM6_FORWARD -m state --state NEW -j DROP;'
    echo '    ip6tables -w -A CUSTOM6_FORWARD -i br0 -o yggdrasil -j ACCEPT;'
    echo '    ip6tables -w -A CUSTOM6_FORWARD -i yggdrasil -m state --state RELATED,ESTABLISHED -j ACCEPT;'
    echo '    ip6tables -w -A FORWARD -j CUSTOM6_FORWARD;'
    echo 'fi'
  } > /opt/etc/ndm/netfilter.d/iptables.sh

  chmod +x /opt/etc/ndm/netfilter.d/iptables.sh
  /opt/etc/ndm/netfilter.d/iptables.sh
fi

if ! check_service "/opt/etc/init.d/S82radvd status"; then
  radvd_changed_config=1
fi

if [ -n "$radvd_changed_config" ]; then
  log INFO "radvd config updated, need restart service"
  if /opt/etc/init.d/S82radvd restart; then
    log INFO "Radvd run successfully."
  else
    log ERROR "Failed to run radvd."
    exit 1
  fi
fi

log INFO "Check access in yggdrassil network"
curl http://[200:56bd:a9e9:c1fa:8f99:1d3c:3c84:6507]/myip