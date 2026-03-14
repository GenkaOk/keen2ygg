# Keen2Ygg
## Скрипт-установщик Yggdrassil на Keenetic

1) Устанавливает зависимости для `yggdrassil`
2) Подготавливает `radvd` конфигурацию для расшаривания в сеть IPv6 Yggdrassil
3) Подготавливает `ip6tables` правила

### Установка

```bash
curl -O https://raw.githubusercontent.com/GenkaOk/keen2ygg/refs/heads/main/keen2ygg.sh && bash keen2ygg.sh
```

### Удаление
```bash
curl -O https://raw.githubusercontent.com/GenkaOk/keen2ygg/refs/heads/main/keen2ygg_uninstall.sh && bash keen2ygg_uninstall.sh
```