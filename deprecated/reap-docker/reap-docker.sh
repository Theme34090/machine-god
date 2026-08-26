#!/usr/bin/env bash
# reap-docker.sh — generic docker cruft reaper: build cache, unused images, and
# dangling volumes (each fingerprinted before you remove it). Does NOT touch
# dev-env compose stacks / their named volumes — that is reap-dev-env's job; a
# paypers dev DB volume is flagged and handed off.
#
# Subcommands:
#   scan                 read-only. df + reclaimable cache/images + a
#                        fingerprinted dangling-volume table. never removes.
#   sweep-cache          docker builder prune -af + image prune -af. Blanket-safe:
#                        cache regenerates, images not held by a container rebuild.
#   reap-volumes VOL...  targeted `docker volume rm` of the explicit volumes given.
#
# SAFETY: scan never removes. cache/images are the only blanket sweep. VOLUMES are
# removed ONLY by explicit name — never `docker volume prune`, which takes every
# dangling volume regardless of the data inside it.
set -uo pipefail

have_docker() { docker info >/dev/null 2>&1; }

# bytes -> human, docker-ish units
human_bytes() {
  awk -v b="${1:-0}" 'BEGIN{
    split("B kB MB GB TB",u," "); i=1
    while (b>=1024 && i<5){ b/=1024; i++ }
    if (i==1) printf "%dB", b; else printf "%.1f%s", b, u[i]
  }'
}

# TRUE reclaim of `image prune -af`: sum size of images NO container references
# (running OR stopped). `docker system df` Reclaimable counts images not held by a
# *running* container, so it overstates — prune protects any-container-referenced
# images. This is what sweep-cache will actually free.
real_image_reclaim() {
  local used total=0 id bytes c
  used=$(for c in $(docker ps -aq 2>/dev/null); do docker inspect -f '{{.Image}}' "$c" 2>/dev/null; done | sort -u)
  while read -r id; do
    [ -z "$id" ] && continue
    printf '%s\n' "$used" | grep -qxF "$id" && continue
    bytes=$(docker image inspect "$id" -f '{{.Size}}' 2>/dev/null || echo 0)
    total=$(( total + ${bytes:-0} ))
  done < <(docker image ls --no-trunc --format '{{.ID}}' 2>/dev/null | sort -u)
  echo "$total"
}

# first locally-present image able to `ls`/`cat` a mounted volume
peek_image() {
  local i
  for i in alpine busybox postgres:16-alpine; do
    docker image inspect "$i" >/dev/null 2>&1 && { echo "$i"; return; }
  done
  docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>' | head -1
}

# echoes "SIZE  KIND" for a volume's contents (postgresNN | empty | first entries)
fingerprint_vol() {
  local v="$1" img="$2"
  [ -z "$img" ] && { echo "?  no-peek-image"; return; }
  docker run --rm -v "$v":/x "$img" sh -c '
    printf "%s  " "$(du -sh /x 2>/dev/null | cut -f1)"
    if [ -f /x/PG_VERSION ]; then echo "postgres$(cat /x/PG_VERSION)"
    elif [ -z "$(ls -A /x 2>/dev/null)" ]; then echo "empty"
    else ls -A /x 2>/dev/null | head -3 | tr "\n" "," ; echo; fi' 2>/dev/null \
    || echo "?  peek-failed"
}

cmd_scan() {
  have_docker || { echo "docker not running" >&2; exit 1; }
  echo "== docker reclaimable =="
  docker system df
  echo
  echo "== real sweep-cache reclaim (what sweep-cache ACTUALLY frees) =="
  # docker df's Images "Reclaimable" overstates (counts images not held by a RUNNING
  # container); image prune -af protects any-container-referenced image. Real figure:
  local _img _cache
  _img=$(real_image_reclaim)
  _cache=$(docker system df --format '{{.Type}}	{{.Reclaimable}}' 2>/dev/null | awk -F'\t' '/Build Cache/{print $2}')
  printf '  %-22s %s\n' "images (unreferenced):" "$(human_bytes "$_img")"
  printf '  %-22s %s\n' "build cache:" "${_cache:-0B}"
  [ "${_img:-0}" -eq 0 ] && echo "  (all images backed by a container — image prune frees nothing)"
  echo
  echo "== dangling volumes — fingerprint before removing (may hold real data) =="
  local img; img="$(peek_image)"
  echo "  peek image: ${img:-<none — pull alpine to fingerprint>}"
  local any=0 v created fp tag
  while read -r v; do
    [ -z "$v" ] && continue
    any=1
    created="$(docker volume inspect "$v" --format '{{.CreatedAt}}' 2>/dev/null)"
    fp="$(fingerprint_vol "$v" "$img")"
    case "$v" in *paypers*dev_db) tag="  [dev-env DB — reseedable]";; *) tag="";; esac
    printf "  %-64s %s  %s%s\n" "$v" "$created" "$fp" "$tag"
  done < <(docker volume ls -q -f dangling=true)
  [ "$any" = 0 ] && echo "  (none)"
}

cmd_sweep_cache() {
  have_docker || { echo "docker not running" >&2; exit 1; }
  echo "== build cache =="; docker builder prune -af 2>&1 | tail -1
  echo "== unused images =="; docker image prune -af 2>&1 | tail -1
  echo "== after =="; docker system df
}

cmd_reap_volumes() {
  [ "$#" -eq 0 ] && { echo "usage: reap-volumes VOL..." >&2; exit 2; }
  local ok=0 skip=0 v
  for v in "$@"; do
    if docker volume rm "$v" >/dev/null 2>&1; then echo "REAPED $v"; ok=$((ok+1))
    else echo "SKIP (in use or missing): $v"; skip=$((skip+1)); fi
  done
  echo "--- reaped $ok, skipped $skip ---"
}

case "${1:-}" in
  scan)         cmd_scan;;
  sweep-cache)  cmd_sweep_cache;;
  reap-volumes) shift; cmd_reap_volumes "$@";;
  *) echo "usage: $0 {scan | sweep-cache | reap-volumes VOL...}" >&2; exit 2;;
esac
