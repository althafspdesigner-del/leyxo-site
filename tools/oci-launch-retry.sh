#!/bin/bash
# Retries launching the leyxo-omnichannel server until Oracle has Always Free
# Arm capacity in the home region. Run inside Oracle Cloud Shell, which is
# already signed in:   bash ~/leyxo-launch.sh
# Contains no secrets: the key below is the PUBLIC half of the login key.
C=$OCI_TENANCY
PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINTtnK32ryouPScR0cd1ECokZ2bDfIgfJo2ZgAwfEG4Q leyxo-omnichannel'
OCPUS=${OCPUS:-1}
MEM=${MEM:-6}
AD=$(oci iam availability-domain list -c "$C" --query 'data[0].name' --raw-output)
SUB=$(oci network subnet list -c "$C" --display-name leyxo-public-subnet --query 'data[0].id' --raw-output)
IMG=$(oci compute image list -c "$C" --operating-system 'Canonical Ubuntu' --operating-system-version '24.04' --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC --query 'data[0].id' --raw-output)
echo "AD=$AD"; echo "SUBNET=$SUB"; echo "IMAGE=$IMG"; echo "SHAPE=A1.Flex ${OCPUS} OCPU / ${MEM} GB"
[ -n "$AD" ] && [ -n "$SUB" ] && [ -n "$IMG" ] || { echo 'lookup failed'; exit 1; }
existing=$(oci compute instance list -c "$C" --display-name leyxo-omnichannel --lifecycle-state RUNNING --query 'data[0].id' --raw-output 2>/dev/null)
[ -n "$existing" ] && { echo "already running: $existing"; exit 0; }
n=0
while true; do
  n=$((n+1)); printf '%s attempt %d: ' "$(date +%H:%M:%S)" "$n"
  out=$(oci compute instance launch -c "$C" --availability-domain "$AD" \
    --shape VM.Standard.A1.Flex --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM}" \
    --image-id "$IMG" --subnet-id "$SUB" --assign-public-ip true \
    --display-name leyxo-omnichannel --hostname-label leyxo \
    --boot-volume-size-in-gbs 100 \
    --metadata "{\"ssh_authorized_keys\":\"$PUB\"}" 2>&1)
  if echo "$out" | grep -q '"lifecycle-state"'; then
    echo LAUNCHED; echo "$out" | grep -E '"id"|"lifecycle-state"' | head -3; break
  fi
  if echo "$out" | grep -qi 'out of capacity'; then echo 'out of capacity, retry in 60s'; sleep 60; continue; fi
  if echo "$out" | grep -qi 'TooManyRequests'; then echo 'rate limited, retry in 180s'; sleep 180; continue; fi
  echo 'unexpected error:'; echo "$out" | head -20; break
done
