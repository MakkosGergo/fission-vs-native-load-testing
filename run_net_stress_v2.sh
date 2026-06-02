#!/bin/bash

echo "======================================================"
echo " ML DATASET GENERÁLÁS: HÁLÓZATI SKÁLÁZÓDÁS (HEY) "
echo "======================================================"

mkdir -p dataset_net

echo "======================================================"
echo " HUBBLE ADATALAGÚT (PORT-FORWARD) FELÉPÍTÉSE..."
echo "======================================================"
cilium hubble port-forward > /dev/null 2>&1 &
PF_PID=$!
echo " Várakozás 5 másodpercet az alagút stabilizálódására..."
sleep 5

MAX_RETRIES=4

for CONCURRENCY in 1 10 25 50 100; do
    echo " "
    echo "======================================================"
    echo "  MÉRÉSI CIKLUS INDÍTÁSA: ${CONCURRENCY} PÁRHUZAMOS KLIENS"
    echo "======================================================"

    ATTEMPT=1
    SUCCESS=false

    while [ $ATTEMPT -le $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
        echo "🔄 [$ATTEMPT/$MAX_RETRIES] PRÓBÁLKOZÁS INDÍTÁSA..."

        # 1. Mac monitor indítása
        echo " [1/5] Mac infrastruktúra monitor indítása..."
        rm -f mac_eroforras.csv
        pkill -f mac_monitor.sh 2>/dev/null
        ./mac_monitor.sh > /dev/null 2>&1 &
        MAC_PID=$!

        # ==========================================
        # 2. FISSION MÉRÉS (COLD BURST)
        # ==========================================
        echo " [2/5] Fission podok nullázása (Cold Burst előkészítése)..."
        pkill -f "hubble observe" 2>/dev/null
        kubectl scale deploy -l functionName=fib --replicas=0 -n default > /dev/null 2>&1
        kubectl wait --for=delete pod -l functionName=fib -n default --timeout=60s 2>/dev/null || true
        sleep 2

        echo "🔬 Hubble indítása a Fission figyelésére..."
        hubble observe --namespace default --protocol http -f -o json > dataset_net/fission_net_${CONCURRENCY}.json 2> hubble_error_fission.log &
        HUBBLE_PID_FISSION=$!
        sleep 3

        echo "  COLD START INDÍTÁSA (Scale to 1)..."
        kubectl scale deploy -l functionName=fib --replicas=1 -n default > /dev/null 2>&1

        echo " Fission terhelés indítása (${CONCURRENCY} szálon, 20 másodpercig)..."
        kubectl run -i --rm load-generator --image=williamyeh/hey --restart=Never -- -c $CONCURRENCY -z 20s -t 60 http://router.fission.svc.cluster.local:80/fib

        sleep 3
        kill -SIGINT $HUBBLE_PID_FISSION 2>/dev/null

        echo "⏳ Pihenő a Fission és a Natív mérés között (10s)..."
        sleep 10

        # ==========================================
        # 3. NATÍV MÉRÉS (WARM THROUGHPUT)
        # ==========================================
        echo " [3/5] Hubble indítása a Natív figyelésére..."
        hubble observe --namespace default --protocol http -f -o json > dataset_net/nativ_net_${CONCURRENCY}.json 2> hubble_error_nativ.log &
        HUBBLE_PID_NATIV=$!
        sleep 3

        echo " [4/5] Natív K8s terhelés indítása (${CONCURRENCY} szálon, 20 másodpercig)..."
        kubectl run -i --rm load-generator --image=williamyeh/hey --restart=Never -- -c $CONCURRENCY -z 20s -t 60 http://native-fib-svc.default.svc.cluster.local:80/fib

        sleep 3
        kill -SIGINT $HUBBLE_PID_NATIV 2>/dev/null

        # ==========================================
        # 4. TAKARÍTÁS ÉS ELLENŐRZÉS
        # ==========================================
        echo " [5/5] Takarítás és adatok ellenőrzése..."
        kill -SIGINT $MAC_PID 2>/dev/null

        # Ellenőrizzük, hogy mindkét fájlban van-e 'RESPONSE' adat
        FISSION_VALID=$(grep '"type":"RESPONSE"' dataset_net/fission_net_${CONCURRENCY}.json 2>/dev/null | wc -l)
        NATIV_VALID=$(grep '"type":"RESPONSE"' dataset_net/nativ_net_${CONCURRENCY}.json 2>/dev/null | wc -l)

        if [ "$FISSION_VALID" -gt 0 ] && [ "$NATIV_VALID" -gt 0 ]; then
            echo " SIKER! Mindkét mérés rögzített valós adatokat (Fission: $FISSION_VALID, Natív: $NATIV_VALID)."
            mv mac_eroforras.csv dataset_net/mac_net_${CONCURRENCY}.csv 2>/dev/null
            SUCCESS=true
        else
            echo "  HIBA: A Hubble elvesztette az adatokat (Fission: $FISSION_VALID, Natív: $NATIV_VALID)."
            if [ $ATTEMPT -lt $MAX_RETRIES ]; then
                echo " Újrapróbálkozás következik a(z) ${CONCURRENCY} klienssel..."
                ((ATTEMPT++))
                sleep 5
            else
                echo " Elfogytak a próbálkozások. Lépünk a következő terhelésre."
                mv mac_eroforras.csv dataset_net/mac_net_${CONCURRENCY}.csv 2>/dev/null
                ((ATTEMPT++))
            fi
        fi
    done

    echo "⏳ Várakozás 15 másodpercet a következő iteráció előtt..."
    sleep 15
done

echo "======================================================"
echo " TAKARÍTÁS: Hubble adatalagút lezárása..."
kill -SIGINT $PF_PID 2>/dev/null

echo "======================================================"
echo " TELJES HÁLÓZATI MÉRÉSI MÁTRIX BEFEJEZVE! "
echo "======================================================"
