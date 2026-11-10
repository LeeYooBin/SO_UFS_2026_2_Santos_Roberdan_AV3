
#!/usr/bin/env bash

set -uo pipefail

IMAGE="python@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b"
ITERATIONS=20000000

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT="$ROOT/results/raw/$RUN_ID"

mkdir -p "$OUTPUT"

echo "Laboratorio AV3"
echo "Execucao: $RUN_ID"
echo "Iteracoes: $ITERATIONS"
echo "Resultados: $OUTPUT"

printf 'run_id,condition,repetition,quota,iterations,exit_code\n' \
  > "$OUTPUT/manifest.csv"

for repetition in 1 2 3; do
  for condition in C1 C2; do

    if [[ "$condition" == "C1" ]]; then
      QUOTA="0.5"
    else
      QUOTA="1.0"
    fi

    ID="${condition}_R${repetition}"
    DIR="$OUTPUT/$ID"
    mkdir -p "$DIR"

    echo
    echo "=== $ID | CPU=$QUOTA ==="

    date -u +%FT%TZ > "$DIR/start_utc.txt"

    timeout --signal=TERM --kill-after=5s 90s \
      docker run --rm \
        --name "av3-${RUN_ID,,}-${ID,,}" \
        --network none \
        --cpus="$QUOTA" \
        --memory=256m \
        --memory-swap=256m \
        --pids-limit=64 \
        --mount "type=bind,src=$ROOT/scripts,dst=/app,readonly" \
        --mount "type=bind,src=$DIR,dst=/output" \
        -w /app \
        "$IMAGE" \
        sh -c '
          CG=/sys/fs/cgroup

          cat "$CG/cpu.max" > /output/cpu.max
          cat "$CG/memory.max" > /output/memory.max
          cat "$CG/memory.swap.max" > /output/memory.swap.max
          cat "$CG/pids.max" > /output/pids.max

          cat "$CG/cpu.stat" > /output/cpu_before.stat
          cat "$CG/memory.current" > /output/memory_before.txt
          cat "$CG/pids.current" > /output/pids_before.txt

          timeout 60s python cpu_load.py \
            --iterations "$1" \
            > /output/result.json \
            2> /output/stderr.txt

          status=$?

          cat "$CG/cpu.stat" > /output/cpu_after.stat
          cat "$CG/memory.current" > /output/memory_after.txt
          cat "$CG/memory.peak" > /output/memory_peak.txt
          cat "$CG/pids.current" > /output/pids_after.txt

          echo "$status" > /output/workload_exit_code.txt

          exit "$status"
        ' sh "$ITERATIONS" \
        > "$DIR/docker_stdout.txt" \
        2> "$DIR/docker_stderr.txt"

    STATUS=$?

    docker rm -f "av3-${RUN_ID,,}-${ID,,}" \
      >> "$DIR/docker_stderr.txt" 2>&1 || true

    date -u +%FT%TZ > "$DIR/end_utc.txt"
    echo "$STATUS" > "$DIR/docker_exit_code.txt"

    printf '%s,%s,%s,%s,%s,%s\n' \
      "$RUN_ID" "$condition" "$repetition" \
      "$QUOTA" "$ITERATIONS" "$STATUS" \
      >> "$OUTPUT/manifest.csv"

    if [[ "$STATUS" -eq 0 ]]; then
      echo "OK: $ID"
    else
      echo "FALHA: $ID (exit=$STATUS)"
      echo "Verifique $DIR/docker_stderr.txt"
    fi

  done
done

echo
echo "Bateria finalizada."
echo "Resultados preservados em: $OUTPUT"
