#!/bin/bash

echo "========================================="
echo " FISSION 10x eBPF MÉRÉS (COLD START) "
echo "========================================="

MAX_RETRIES=4
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
    echo ""
    echo " [$ATTEMPT/$MAX_RETRIES] PRÓBÁLKOZÁS INDÍTÁSA..."
    echo "-----------------------------------------"

    # 0. Takarítás (Tiszta nullára skálázás a mérés előtt)
    echo "[0/5]  Takarítás és Pod letakarítása..."
    pkill -f "cilium hubble port-forward" 2>/dev/null
    pkill -f "hubble observe" 2>/dev/null
    rm -f nyers_meres.json tiszta_meres.json hubble_error_fission.log

    kubectl scale deploy -l functionName=fib --replicas=0 -n default > /dev/null 2>&1
    echo " Várakozás a hálózat tiszta ürülésére (60s timeout)..."
    kubectl wait --for=delete pod -l functionName=fib -n default --timeout=60s 2>/dev/null || true
    sleep 2

    # 1. Alagút
    echo "[1/5] Hubble alagút megnyitása..."
    cilium hubble port-forward > /dev/null 2>&1 &
    PF_PID=$!
    sleep 5

    # 2. Megfigyelő
    echo "[2/5]  Hubble L7 figyelő indítása..."
    hubble observe --namespace fission --protocol http -f -o json > nyers_meres.json 2> hubble_error_fission.log &
    HUBBLE_PID=$!
    echo "⏳ Hubble bemelegítése (12s)..."
    sleep 12

    # --- A ZSENIÁLIS LÉPÉS: MI INDÍTJUK A COLD STARTOT ---
    echo "[2.5/5]  COLD START INDÍTÁSA (Scale to 1)..."
    kubectl scale deploy -l functionName=fib --replicas=1 -n default > /dev/null 2>&1
    # --------------------------------------------------------

    # 3. Kérések elküldése
    echo "[3/5]  Függvény meghívása 10-szer..."
    kubectl exec debug-curl-pod -- sh -c "for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -m 60 http://router.fission.svc.cluster.local:80/fib; echo ' - Kész'; sleep 0.5; done"
    echo ""

    # 4. Puffer
    echo "[4/5] ⏳ Várakozás a hálózati puffer ürülésére..."
    sleep 3

    # 5. Leállítás (GRACEFUL SHUTDOWN)
    echo "[5/5]  Mérés leállítása (SIGINT)..."
    kill -SIGINT $HUBBLE_PID 2>/dev/null
    sleep 2
    kill -SIGINT $PF_PID 2>/dev/null
    sleep 1

    # EREDMÉNY KIÉRTÉKELÉSE
    if [ ! -s nyers_meres.json ]; then
        echo " HIBA: A Hubble nem rögzített semmit a fájlba."
    else
        grep "fib" nyers_meres.json > tiszta_meres.json
        SOROK=$(grep '"type":"RESPONSE"' tiszta_meres.json | grep '"latency_ns":' | wc -l)

        if [ "$SOROK" -ge 10 ]; then
            echo " SIKER! Mind a 10 válaszidő rögzítve (benne a Cold Start is!)."
            SUCCESS=true
        else
            echo "⚠️  RÉSZLEGES SIKER: Csak $SOROK/10 válasz lett meg."
            if [ $ATTEMPT -lt $MAX_RETRIES ]; then
                echo "🔃 Újrapróbálkozás következik..."
                ((ATTEMPT++))
                sleep 5
            else
                echo " Elfogytak a próbálkozások. Mentjük, ami megvan."
                ((ATTEMPT++))
            fi
        fi
    fi
done

echo "========================================="
if [ "$SUCCESS" = true ]; then
    echo " A MÉRÉSI CIKLUS SIKERESEN LEFUTOTT!"
fi
echo "========================================="
