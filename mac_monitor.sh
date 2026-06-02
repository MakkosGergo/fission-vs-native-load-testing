#!/bin/bash
echo "Timestamp,CPU_User_%,Mem_Free_MB" > mac_eroforras.csv
echo "Mérés indítva... (Leállítás: Ctrl+C)"

while true; do
    # Kinyerjük az aktuális időt UTC-ben, hogy passzoljon a Hubble JSON-höz!
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Kinyerjük a Mac CPU (User) százalékot és a Szabad memóriát a 'top'-ból
    CPU=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%')
    MEM=$(top -l 1 | grep "PhysMem" | awk '{print $6}' | tr -d 'M')

    echo "$TIMESTAMP,$CPU,$MEM" >> mac_eroforras.csv
    sleep 1
done
