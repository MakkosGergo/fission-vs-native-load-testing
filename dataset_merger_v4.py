import os
import json
import csv
import statistics

# Konfiguráció
CPU_DIR = 'dataset_cpu'
NET_DIR = 'dataset_net'
OUTPUT_FILE = 'final_ml_dataset.csv'

# Oszlopok (Bővítve a Mac metrikákkal)
HEADERS = [
    'architecture', 'is_cold_start', 'cpu_stress_percent', 'net_concurrency',
    'latency_ms', 'mac_cpu_actual_avg', 'mac_mem_free_mb_avg'
]

def get_mac_averages(csv_path):
    """Beolvassa a monitor CSV-t és átlagolja a CPU/MEM értékeket."""
    if not os.path.exists(csv_path):
        return 0, 0

    cpus = []
    mems = []
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # ITT VOLT A HIBA: A valós oszlopneveket kell használni!
                if 'CPU_User_%' in row and 'Mem_Free_MB' in row:
                    cpus.append(float(row['CPU_User_%']))
                    mems.append(float(row['Mem_Free_MB']))

        avg_cpu = statistics.mean(cpus) if cpus else 0
        avg_mem = statistics.mean(mems) if mems else 0
        return round(avg_cpu, 2), round(avg_mem, 2)
    except Exception as e:
        print(f" Hiba a Mac adatok olvasásakor ({csv_path}): {e}")
        return 0, 0

def parse_json_to_csv(json_path, mac_csv_path, arch, is_fission, cpu_val, net_val, csv_writer):
    if not os.path.exists(json_path):
        return

    # Kinyerjük a gép valós átlagos terhelését a mérés alatt
    mac_cpu, mac_mem = get_mac_averages(mac_csv_path)

    try:
        with open(json_path, 'r') as f:
            valid_responses = 0
            for line in f:
                line = line.strip()
                if not line: continue
                try:
                    data = json.loads(line)
                    if 'flow' in data and 'l7' in data['flow']:
                        l7 = data['flow']['l7']
                        if l7.get('type') == 'RESPONSE' and 'latency_ns' in l7:
                            latency_ms = int(l7['latency_ns']) / 1_000_000

                            cold_start_flag = 1 if (is_fission and valid_responses == 0) else 0

                            csv_writer.writerow([
                                arch, cold_start_flag, cpu_val, net_val,
                                round(latency_ms, 2), mac_cpu, mac_mem
                            ])
                            valid_responses += 1
                except:
                    continue
    except Exception as e:
        print(f"Hiba a {json_path} feldolgozásakor: {e}")

print(" ML Dataset Egyesítés (Mac adatokkal) Indítása...")

with open(OUTPUT_FILE, 'w', newline='') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(HEADERS)

    # --- 1. CPU ADATOK ---
    for cpu_percent in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
        # Fission
        parse_json_to_csv(
            f"{CPU_DIR}/fission_cpu_{cpu_percent}.json",
            f"{CPU_DIR}/mac_cpu_{cpu_percent}.csv",
            "fission", True, cpu_percent, 1, writer
        )
        # Native
        parse_json_to_csv(
            f"{CPU_DIR}/nativ_cpu_{cpu_percent}.json",
            f"{CPU_DIR}/mac_cpu_{cpu_percent}.csv",
            "native", False, cpu_percent, 1, writer
        )

    # --- 2. NET ADATOK ---
    for concurrency in [1, 10, 25, 50, 100]:
        # Fission
        parse_json_to_csv(
            f"{NET_DIR}/fission_net_{concurrency}.json",
            f"{NET_DIR}/mac_net_{concurrency}.csv",
            "fission", True, 0, concurrency, writer
        )
        # Native
        parse_json_to_csv(
            f"{NET_DIR}/nativ_net_{concurrency}.json",
            f"{NET_DIR}/mac_net_{concurrency}.csv",
            "native", False, 0, concurrency, writer
        )

print(f" KÉSZ! A végleges dataset Mac adatokkal elmentve: {OUTPUT_FILE}")
