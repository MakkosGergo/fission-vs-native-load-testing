# Fission vs. Native Performance Analysis

Ez a projekt a **Fission (Serverless)** és a **hagyományos (Native)** konténer-alapú architektúrák összehasonlító elemzését tartalmazza különböző terhelési forgatókönyvek mellett.

## Overview / Áttekintés
A projekt célja annak kvantitatív vizsgálata, hogy a szerverless architektúra (FaaS) milyen teljesítménykülönbséget mutat a hagyományos konténeres megoldásokhoz képest, különös tekintettel a CPU fojtásra és a hálózati konkureciára.

## Methodology / Metodológia
A mérések egy általam fejlesztett, **automatizált Bash-alapú keretrendszerrel** történtek. A mérési folyamat (pipeline) a következő determinisztikus lépésekből áll:

1. **Környezet-konfiguráció:** Az infrastruktúra tisztítása és a teszt-podok automatizált telepítése.
2. **Valós idejű monitorozás:** Erőforrás-felhasználás rögzítése eBPF/Hubble alapokon.
3. **Stressz- és ciklusvezérlés:** Szimmetrikus terhelés generálása (`stress-ng`, `hey`) mindkét architektúrán.
4. **Adatkonzolidáció:** A nyers mérési eredmények egységesítése és strukturált mentése.
5. **Rendszer-helyreállítás:** Automatikus "cool-down" periódus a mérések közötti torzítások elkerülése érdekében.

## Usage / Használat
A mérések a run_cpu_stress_v3.sh és auto_meres_loop_v5.sh szkriptekkel indíthatóak, amely automatikusan kezeli a teljes ciklust.
További scriptek, amiket az előzőek használnak, vagy utómunkát végeznek, a futások után, amit manuálisan kell indítani.
Nativ: auto_meres_native_v4.sh
Fission: auto_meres_loop_v5.sh
Mac monitorozás: mac_monitor.sh
Adatfúzió dataset_merger_v4.sh
