#!/bin/bash

get_cpu_temp() {
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    echo "scale=2; $TEMP_RAW / 1000" | bc -l
  else
    echo "0"
  fi
}

send_email_notification() {
  local subject=$1
  local body=$2

  echo -e "Subject: $subject\n\n$body" | msmtp --host=$SMTP_SERVER --auth=on --user=$SMTP_USER --passwordeval="echo $SMTP_PASSWORD" $NOTIFY_EMAIL
}

send_temperature() {
  local retries=0
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
      echo "$(date): Daten erfolgreich gesendet. Temp: $TEMP°C" >> $LOG_FILE
      return 0
    else
      echo "$(date): Fehler beim Senden (Status: $HTTP_RESPONSE). Versuch $((retries + 1))/$MAX_RETRIES." >> $LOG_FILE
      retries=$((retries + 1))
      sleep $RETRY_DELAY
    fi
  done

  echo "$(date): Max. Anzahl von Versuchen erreicht. Daten nicht gesendet." >> $LOG_FILE

  send_email_notification \
    "Warnung: Temperatur konnte nicht gesendet werden" \
    "Die CPU-Temperatur konnte nicht an den Webserver gesendet werden.\n\nLetzte bekannte Temperatur: $TEMP°C\nGerät: $DEVICE_NAME\nZeit: $TIMESTAMP\nLog-Datei: $LOG_FILE"

  return 1
}

while true; do
  send_temperature
  sleep 60
done
