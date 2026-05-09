#!/bin/bash

# fichier de log pour ChabahRoot
LOGFILE="/var/log/chabah_detection.log"

echo "démarrage de la surveillance ChabahRoot ..."
echo " surveillance des transitions d'UID (privilège) ..."

# boucle de serveillance 
  journalctl -f -t sudo | while read line; do
      if echo "$line" | grep -q "COMMAND="; then
          USER_ACTION=$(echo "$line" | awk '{print $6}')
          COMMAND_RUN=$(echo "line" | grep -o "COMMAND=.*")
          MESSAGE="[ALERTE CHABAH] Transition détectée : $USER_ACTION exécute $COMMAND_RUN"
          echo "$(date) : $MESSAGE" | sudo tee -a $LOGFILE
          #cette ligne affiche une modification sur ton bureau ubuntu
           notify-send "ChabahRoot Alert" "$MESSAGE" --icon=dialog-warning
      fi
done
