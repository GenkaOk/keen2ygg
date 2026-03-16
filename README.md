# Keen2Ygg
## Скрипт-установщик Yggdrasil на Keenetic

1) Устанавливает зависимости для `yggdrassil`
2) Подготавливает `radvd` конфигурацию для расшаривания в сеть IPv6 Yggdrassil
3) Подготавливает `ip6tables` правила

### Подготовка
1) Подключитесь по SSH, Telnet или перейдите по ссылке `http://IP Вашего роутера/a` (Например: http://192.168.1.1/a)
2) Выполните команды `no ipv6 subnet Default` и `system configuration save`

Это необходимо для освобождения IPv6 подсети для сети Yggdrasil.

После этого можно приступать к установке.

### Установка

```bash
curl -O https://raw.githubusercontent.com/GenkaOk/keen2ygg/refs/heads/main/keen2ygg.sh && bash keen2ygg.sh
```

### Удаление
```bash
curl -O https://raw.githubusercontent.com/GenkaOk/keen2ygg/refs/heads/main/keen2ygg_uninstall.sh && bash keen2ygg_uninstall.sh
```
