!/bin/bash

echo "========================================="
echo " NATIVE 10x eBPF MÉRÉS (CSAK WARM START) "
echo "========================================="

MAX_RETRIES=4
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
    echo ""
    echo " [$ATTEMPT/$MAX_RETRIES] NATIVE PRÓBÁLKOZÁS INDÍTÁSA..."
    echo "-----------------------------------------"

    # 0. Takarítás (DE NINCS POD TÖRLÉS!)
    echo "[0/5] Takarítás..."
    pkill -f "cilium hubble port-forward" 2>/dev/null
    pkill -f "hubble observe" 2>/dev/null
    rm -f nyers_meres.json tiszta_meres.json hubble_error_native.log
    sleep 2

    # 1. Alagút
    echo "[1/5] Hubble alagút megnyitása..."
    cilium hubble port-forward > /dev/null 2>&1 &
    PF_PID=$!
    sleep 5

    # 2. Megfigyelő (namespace: default, mert itt van a natív pod)
    echo "[2/5] Hubble L7 figyelő indítása (default ns)..."
    hubble observe --namespace default --protocol http -f -o json > nyers_meres.json 2> hubble_error_native.log &
    HUBBLE_PID=$!
    echo "⏳ Hubble bemelegítése (12s)..."
    sleep 12

    # 3. Kérések elküldése (a natív service-t hívjuk)
    echo "[3/5] Natív függvény hívása 10-szer (MIND WARM START!)..."
    kubectl exec debug-curl-pod -- sh -c "for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -m 15 http://native-fib-svc.default.svc.cluster.local:80/fib; echo ' - Kész'; sleep 0.5; done"
    echo ""

    # 4. Puffer
    echo "[4/5] Várakozás a hálózati adatokra..."
    sleep 3

    # 5. Leállítás
    echo "[5/5] Mérés leállítása..."
    kill -SIGINT $HUBBLE_PID 2>/dev/null
    sleep 2
    kill -SIGINT $PF_PID 2>/dev/null
    sleep 1

    # KIÉRTÉKELÉS
    if [ ! -s nyers_meres.json ]; then
        echo "HIBA: A Hubble nem rögzített adatot."
    else
        grep '"type":"RESPONSE"' nyers_meres.json | grep '"latency_ns":' > tiszta_meres.json
        SOROK=$(wc -l < tiszta_meres.json)

        if [ "$SOROK" -ge 10 ]; then
            echo "SIKER! Mind a 10 natív válaszidő rögzítve."
            SUCCESS=true
        else
            echo "HIBA: Csak $SOROK/10 válasz lett meg."
            if [ $ATTEMPT -lt $MAX_RETRIES ]; then
                echo "🔃 Újrapróbálkozás..."
                ((ATTEMPT++))
                sleep 5
            else
                echo "Elfogytak a próbálkozások."
                ((ATTEMPT++))
            fi
        fi
    fi
done

echo "========================================="
[ "$SUCCESS" = true ] && echo "NATIVE CIKLUS KÉSZ!" || echo "NATIVE CIKLUS HIÁNYOS."
echo "========================================="
