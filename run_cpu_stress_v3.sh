#!/bin/bash

echo "======================================================"
echo " ML DATASET GENERÁLÁS: CPU STRESSZ SKÁLÁZÓDÁS v3 🔥ó"
echo "======================================================"

mkdir -p dataset_cpu

echo " Infrastruktúra előkészítése..."
kubectl delete pod debug-curl-pod --ignore-not-found=true
kubectl run debug-curl-pod --image=curlimages/curl --restart=Never -- sh -c "sleep infinity"
echo " Várakozás a mérő-pod elindulására..."
kubectl wait --for=condition=Ready pod debug-curl-pod --timeout=60s
echo " Mérő-pod készen áll!"

for CPU_LOAD in 10 20 30 40 50 60 70 80 90 100; do
    echo " "
    echo "  MÉRÉSI CIKLUS INDÍTÁSA: ${CPU_LOAD}% CPU TERHELÉS"

    # stress-ng indítása (8 szálon)
    stress-ng --cpu 8 --cpu-load $CPU_LOAD > /dev/null 2>&1 &
    STRESS_PID=$!
    sleep 5

    rm -f mac_eroforras.csv
    ./mac_monitor.sh > /dev/null 2>&1 &
    MAC_PID=$!

    # FISSION Mérés (Itt hívjuk az új v5-et, ami magának csinálja a Cold Startot!)
    ./auto_meres_loop_v5.sh
    mv tiszta_meres.json dataset_cpu/fission_cpu_${CPU_LOAD}.json
    sleep 5

    # NATÍV Mérés (Ezt is futtatjuk, ennek nincs Cold Startja, ez a referencia)
    ./auto_meres_native_v4.sh
    mv tiszta_meres.json dataset_cpu/nativ_cpu_${CPU_LOAD}.json

    echo " [5/5] Monitor és stressz leállítása..."
    kill $MAC_PID 2>/dev/null
    kill $STRESS_PID 2>/dev/null
    pkill -f stress-ng

    mv mac_eroforras.csv dataset_cpu/mac_cpu_${CPU_LOAD}.csv
    echo " KÉSZ: ${CPU_LOAD}%-os adatok elmentve!"

    # Extra biztonsági pod gyilkosság a hűtés alatt
    kubectl delete pod -l functionName=fib -n default --ignore-not-found=true > /dev/null 2>&1

    echo " Hűtés (20 mp)..."
    sleep 20
done

echo " Mérő-Pod eltávolítása..."
kubectl delete pod debug-curl-pod
echo "TELJES CPU MÉRÉSI MÁTRIX BEFEJEZVE!"
