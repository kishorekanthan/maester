def gib: (. / 1073741824 * 100 | round) / 100;
def round1: (. * 10 | round) / 10;
def cores_of($ncpu): (. / 100) as $c | { cores: ((($c * 100 | round) / 100)), pct: ([($c / $ncpu * 100), 100] | min | round1) };

($cpu_s | if length == 0 then null else tonumber end) as $cpu
| ($load_s | if length == 0 then null else . end) as $load
| ($diskio_s | if length == 0 then null else . end) as $diskio
| ($slow.mem) as $mem
| ($slow.disk) as $disk
| ($slow.gpu) as $gpu
| ($slow.battery) as $battery
| ($slow.thermal) as $thermal
| ($slow.uptime) as $uptime

| (if $cpu != null then [{id: "cpu", label: "CPU", value: ($cpu | round1), unit: "%", pct: ([$cpu, 100] | min | round1)}] else [] end) as $cpu_metric
| (if $gpu != null then [{id: "gpu", label: "GPU", value: ($gpu | tonumber), unit: "%", pct: ([($gpu | tonumber), 100] | min | round1)}] else [] end) as $gpu_metric
| (if $mem != null and $mem.total > 0 then
     [{id: "mem", label: "Memory", value: ($mem.used | gib), unit: "GiB", pct: ([($mem.used / $mem.total * 100), 100] | min | round1)}]
   else [] end) as $mem_metric
| (if $disk != null then
     [{id: "disk", label: "Data volume", value: ($disk.used | gib), unit: "GiB", pct: ($disk.pct | round1)}]
   else [] end) as $disk_metric
| (if $diskio != null then [{id: "diskio", label: "Disk I/O", text: $diskio}] else [] end) as $diskio_metric
| ($cpu_metric + $gpu_metric + $mem_metric + $disk_metric + $diskio_metric) as $metrics

| (if $mem != null and $mem.total > 0 then
     [{label: "Memory pressure", value: $mem.pressure, state: (if $mem.pressure == "normal" then "ok" else "warn" end)},
      {label: "Wired · compressed", value: "\($mem.wired | gib) · \($mem.compressed | gib) GiB", state: "ok"}]
   else [] end) as $mem_lines
| (if $disk != null then
     [{label: "Data volume free", value: "\($disk.avail | gib) GiB", state: (if $disk.pct >= 90 then "warn" else "ok" end)}]
   else [] end) as $disk_lines
| (if $load != null then [{label: "Load average", value: "\($load) · \($ncpu) cores", state: "ok"}] else [] end) as $load_lines
| [{label: "Cores", value: $core_split, state: "ok"}] as $core_lines
| (if $uptime != null then [{label: "Uptime", value: $uptime, state: "ok"}] else [] end) as $uptime_lines
| ($battery.pct != null and $battery.pct < 20 and $battery.state == "discharging") as $battery_low
| (if $battery.pct != null then
     [{label: "Battery", value: "\($battery.pct)% · \($battery.state)", state: (if $battery_low then "warn" else "ok" end)}]
   else [] end) as $battery_lines
| (if $thermal != "nominal" then [{label: "Thermal", value: $thermal, state: "warn"}] else [] end) as $thermal_lines
| ($mem_lines + $disk_lines + $load_lines + $core_lines + $uptime_lines + $battery_lines + $thermal_lines) as $lines

| ( ($mem != null and $mem.pressure != "normal")
    or ($disk != null and $disk.pct >= 90)
    or $battery_low
    or ($thermal != "nominal") ) as $has_warn
| (if $has_warn then "warn" else "ok" end) as $state

| ($slow.procs | map(
     (.cpu | cores_of($ncpu)) as $c
     | { id: "proc/\(.name)",
         label: .name,
         detail: "pid \(.pid)",
         state: "ok",
         icon: "path:\(.path)",
         metrics: [ {id: "cpu", label: "CPU", value: $c.cores, unit: "cores", pct: $c.pct},
                    {id: "mem", label: "Mem", value: .mem, unit: "%", pct: ([.mem, 100] | min)} ],
         actions: [] }
   )) as $items

| ( [ (if $cpu != null then "CPU \($cpu | round)%" else empty end),
      (if $gpu != null then "GPU \($gpu | round)%" else empty end),
      (if $mem != null and $mem.total > 0 then "RAM \((($mem.used / $mem.total * 100) | round))%" else empty end),
      (if $disk != null then "data vol \($disk.pct | round)%" else empty end) ] ) as $bits
| (if ($bits | length) > 0 then ($bits | join(" · ")) else "no readings" end) as $summary

| { schema: 1, title: "This Mac", state: $state, icon: "sf:apple.logo",
    summary: $summary,
    capabilities: { stream: true, refresh: 5 },
    lines: $lines, metrics: $metrics, items: $items,
    actions: [{id: "activity", label: "Activity Monitor"}] }
