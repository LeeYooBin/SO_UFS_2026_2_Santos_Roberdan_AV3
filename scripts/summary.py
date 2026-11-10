
import csv
import json
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "results" / "raw"
PLOTS = ROOT / "results" / "plots"
EXPECTED_CHECKSUM = 464056848
EXPECTED_ITERATIONS = 20_000_000


def read_stat(path):
    result = {}
    for line in path.read_text().splitlines():
        key, value = line.split()
        result[key] = int(value)
    return result


def read_int(path):
    return int(path.read_text().strip())


def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    PLOTS.mkdir(parents=True, exist_ok=True)

    batches = sorted(
        p for p in RAW.iterdir()
        if p.is_dir() and (p / "manifest.csv").exists()
    )
    if not batches:
        raise RuntimeError("Nenhuma bateria encontrada")

    batch = batches[-1]
    rows = []

    for condition in ("C1", "C2"):
        for repetition in range(1, 4):
            folder = batch / f"{condition}_R{repetition}"

            data = json.loads(
                (folder / "result.json").read_text()
            )

            before = read_stat(folder / "cpu_before.stat")
            after = read_stat(folder / "cpu_after.stat")

            row = {
                "condition": condition,
                "repetition": repetition,
                "quota": 0.5 if condition == "C1" else 1.0,
                **data,
                "docker_exit_code": read_int(
                    folder / "docker_exit_code.txt"
                ),
                "workload_exit_code": read_int(
                    folder / "workload_exit_code.txt"
                ),
                "cpu_max": (
                    folder / "cpu.max"
                ).read_text().strip(),
                "memory_max": read_int(folder / "memory.max"),
                "memory_swap_max": read_int(
                    folder / "memory.swap.max"
                ),
                "pids_max": read_int(folder / "pids.max"),
                "memory_before": read_int(
                    folder / "memory_before.txt"
                ),
                "memory_after": read_int(
                    folder / "memory_after.txt"
                ),
                "memory_peak": read_int(
                    folder / "memory_peak.txt"
                ),
                "pids_after": read_int(
                    folder / "pids_after.txt"
                ),
            }

            for key in (
                "usage_usec",
                "nr_throttled",
                "throttled_usec",
            ):
                row[f"delta_{key}"] = (
                    after.get(key, 0) - before.get(key, 0)
                )

            row["valid"] = (
                data["status"] == "success"
                and data["checksum"] == EXPECTED_CHECKSUM
                and data["iterations"] == EXPECTED_ITERATIONS
                and row["docker_exit_code"] == 0
                and row["workload_exit_code"] == 0
                and row["memory_max"] == 268435456
                and row["memory_swap_max"] == 0
                and row["pids_max"] == 64
                and row["cpu_max"] == (
                    "50000 100000" if condition == "C1"
                    else "100000 100000"
                )
            )

            rows.append(row)

    csv_path = ROOT / "results" / "metrics.csv"
    with csv_path.open("w", newline="") as file:
        writer = csv.DictWriter(
            file, fieldnames=list(rows[0].keys())
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Bateria: {batch.name}")
    print(f"CSV: {csv_path}")
    print()

    for condition in ("C1", "C2"):
        group = [
            r for r in rows if r["condition"] == condition
        ]

        print(f"=== {condition} ===")
        print("Execucoes validas:",
              sum(r["valid"] for r in group), "/ 3")

        for key in (
            "wall_time_seconds",
            "cpu_time_seconds",
            "work_per_second",
            "delta_usage_usec",
            "delta_nr_throttled",
            "delta_throttled_usec",
            "memory_peak",
        ):
            values = [r[key] for r in group]
            print(
                f"{key}: "
                f"mediana={statistics.median(values):.3f}; "
                f"min={min(values):.3f}; "
                f"max={max(values):.3f}"
            )
        print()

    fig, ax = plt.subplots(figsize=(9, 5))

    labels = ["R1", "R2", "R3"]
    x = range(3)
    width = 0.35

    c1 = [
        r["wall_time_seconds"]
        for r in rows if r["condition"] == "C1"
    ]
    c2 = [
        r["wall_time_seconds"]
        for r in rows if r["condition"] == "C2"
    ]

    ax.bar(
        [i - width / 2 for i in x],
        c1, width, label="C1 - 0.5 CPU"
    )
    ax.bar(
        [i + width / 2 for i in x],
        c2, width, label="C2 - 1.0 CPU"
    )

    ax.set_xticks(list(x), labels)
    ax.set_ylabel("Tempo decorrido (s)")
    ax.set_xlabel("Repeticao")
    ax.set_title(
        "Carga fixa: 20 milhoes de iteracoes (n=3 por condicao)"
    )
    ax.legend()
    ax.grid(axis="y", alpha=0.2)
    fig.tight_layout()

    output = PLOTS / "cpu_wall_time.png"
    fig.savefig(output, dpi=180)
    plt.close(fig)

    print(f"Grafico: {output}")

    if not all(r["valid"] for r in rows):
        raise SystemExit(
            "Error: existem execucoes invalidas"
        )


if __name__ == "__main__":
    main()
