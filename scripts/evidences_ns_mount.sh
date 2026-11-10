#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="python@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT="$ROOT/evidences/$RUN_ID"
DATA="$ROOT/data"

A="av3-ns-a-$RUN_ID"
B="av3-ns-b-$RUN_ID"

mkdir -p "$OUTPUT" "$DATA"
printf 'Documento sintetico para AV3\n' > "$DATA/text.txt"

cleanup() {
  docker rm -f "$A" "$B" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== AMBIENTE DO DAEMON ===" | tee "$OUTPUT/environment.txt"
docker info --format \
  'OS={{.OperatingSystem}}
Kernel={{.KernelVersion}}
CPUs={{.NCPU}}
Memory={{.MemTotal}}
Cgroup={{.CgroupVersion}}' \
  | tee -a "$OUTPUT/environment.txt"

echo
echo "=== INICIANDO CONTEINERES ==="

for name in "$A" "$B"; do
  docker run -d \
    --name "$name" \
    --network none \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    "$IMAGE" \
    sleep 120
done

echo
echo "=== NAMESPACES ==="

printf 'container,host_pid,internal_pid1,pid_ns,mnt_ns,net_ns\n' \
  > "$OUTPUT/namespaces.csv"

for name in "$A" "$B"; do
  file="$OUTPUT/$name.txt"

  host_pid="$(docker inspect --format '{{.State.Pid}}' "$name")"
  internal_pid1="$(docker exec "$name" cat /proc/1/comm)"

  pid_ns="$(docker exec "$name" readlink /proc/1/ns/pid)"
  mnt_ns="$(docker exec "$name" readlink /proc/1/ns/mnt)"
  net_ns="$(docker exec "$name" readlink /proc/1/ns/net)"

  {
    echo "Container: $name"
    echo "Host PID (daemon): $host_pid"
    echo "PID 1 command: $internal_pid1"
    echo "PID namespace: $pid_ns"
    echo "Mount namespace: $mnt_ns"
    echo "Network namespace: $net_ns"
  } | tee "$file"

  printf '%s,%s,%s,%s,%s,%s\n' \
    "$name" "$host_pid" "$internal_pid1" \
    "$pid_ns" "$mnt_ns" "$net_ns" \
    >> "$OUTPUT/namespaces.csv"
done

echo
echo "=== TESTE READ-ONLY ==="

docker run --rm \
  --network none \
  --user 65534:65534 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --mount "type=bind,src=$DATA,dst=/dados,readonly" \
  "$IMAGE" \
  sh -c '
    echo "Identidade:"
    id

    echo "Leitura:"
    cat /dados/text.txt

    echo "Tentativa de escrita:"
    if touch /dados/novo.txt 2>/tmp/write_error; then
      echo "FALHA: escrita permitida"
      exit 1
    else
      status=$?

      echo "Codigo de saida do touch: $status"
      echo "Mensagem de erro:"
      cat /tmp/write_error

      if ! grep -q "Read-only file system" /tmp/write_error; then
        echo "FALHA: motivo da negacao inesperado"
        exit 1
      fi

      if test -e /dados/novo.txt; then
        echo "FALHA: arquivo foi criado"
        exit 1
      fi

      echo "SUCESSO: escrita negada pelo mount read-only"
    fi
  ' | tee "$OUTPUT/read_only.txt"

echo
echo "=== FINALIZADO ==="
echo "Evidencias: $OUTPUT"
