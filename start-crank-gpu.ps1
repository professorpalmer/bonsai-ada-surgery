# Lock the 4070 to a high boost band so decode does not drop to P8 between tokens.
# Needs elevation. Power limit is already the card max (200 W).
$ErrorActionPreference = 'Stop'
nvidia-smi -pl 200
nvidia-smi -lgc 2800,3105
nvidia-smi -lmc 10501
nvidia-smi --query-gpu=power.limit,clocks.gr,clocks.mem,clocks.max.gr,clocks.max.mem --format=csv
