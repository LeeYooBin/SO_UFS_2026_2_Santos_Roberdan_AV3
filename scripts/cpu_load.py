import argparse
import json
import resource
import time

MODULO = 1_000_000_007


def executar(iteracoes: int) -> int:
    checksum = 0

    for i in range(iteracoes):
        checksum = (
            checksum * 31 + (i * i + 7)
        ) % MODULO

    return checksum


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, required=True)
    args = parser.parse_args()

    if args.iterations <= 0:
        parser.error("--iterations deve ser positivo")

    inicio_wall = time.perf_counter()
    inicio_cpu = time.process_time()

    checksum = executar(args.iterations)

    wall_time = time.perf_counter() - inicio_wall
    cpu_time = time.process_time() - inicio_cpu

    uso = resource.getrusage(resource.RUSAGE_SELF)

    print(json.dumps({
        "iterations": args.iterations,
        "checksum": checksum,
        "status": "success",
        "wall_time_seconds": round(wall_time, 6),
        "cpu_time_seconds": round(cpu_time, 6),
        "work_per_second": round(
            args.iterations / wall_time, 2
        ),
        "max_rss_kib": uso.ru_maxrss,
        "minor_page_faults": uso.ru_minflt,
        "major_page_faults": uso.ru_majflt
    }, indent=2))


if __name__ == "__main__":
    main()
