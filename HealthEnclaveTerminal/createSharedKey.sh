#!/bin/sh

#  createSharedKey.sh
#  HealthEnclaveTerminal
#
#  Created by Lukas Schmierer on 15.06.20.
#  
head -c 32 /dev/urandom | base64 | qrencode -8 -o sharedKey.png
