#!/bin/bash

get_cpu_temp() {
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    echo "scale=2; $TEMP_RAW / 1000" | bc -l
  else
    echo "0"
  fi
}

send_temperature() {
  local retries
  retries=0
  TEMP=$(get_cpu_temp)
  TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")

  JSON_PAYLOAD=$(cat <<EOF
{
  "device": "$DEVICE_NAME",
  "temperature": $TEMP,
  "timestamp": "$TIMESTAMP"
}
EOF
)

  while [ $retries -lt $MAX_RETRIES ]; do
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD" "$WEBHOOK_URL")

    if [ "$HTTP_RESPONSE" -eq 200 ]; then
      echo "$(date): Daten erfolgreich gesendet. Temp: $TEMP°C"
      return 0
    else
      echo "$(date): Fehler beim Senden (Status: $HTTP_RESPONSE). Versuch $((retries + 1))/$MAX_RETRIES."
      retries=$((retries + 1))
      sleep $RETRY_DELAY
    fi
  done

  echo "$(date): Max. Anzahl von Versuchen erreicht. Daten nicht gesendet."
  return 1
}

while true; do
  send_temperature
  sleep 60
done
