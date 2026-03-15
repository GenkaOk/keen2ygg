#!/bin/sh

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


# Function to get the IPv6 address from yggdrasilctl getself
get_ipv6_address() {
  yggdrasilctl getself | awk '/^IPv6 address:/ {print $3}'
}

ipv6_address=$(get_ipv6_address)

/opt/etc/init.d/S83yggdrasil stop
/opt/etc/init.d/S82radvd stop

if [ -n "$ipv6_address" ]; then
  ipv6_address_network="3${ipv6_address#?}"
  ip addr del $ipv6_address_network/64 dev br0
fi

rm /opt/etc/init.d/S83yggdrasil
rm /opt/etc/init.d/S82radvd

if confirm "Delete yggdrassil configuration? (Public key, IPv6)" "Yes" "No"; then
  rm /opt/etc/yggdrasil.conf
fi

rm /opt/etc/radvd.conf

rm /opt/etc/ndm/netfilter.d/iptables.sh

ip6tables -w -D FORWARD -j CUSTOM6YGG_FORWARD
ip6tables -w -F CUSTOM6YGG_FORWARD
ip6tables -w -X CUSTOM6YGG_FORWARD

opkg remove yggdrasil-go radvd