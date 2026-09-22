def gib: (. / 1073741824 * 100 | round) / 100;
def round1: (. * 10 | round) / 10;
def cores_of($ncpu): (. / 100) as $c | { cores: ((($c * 100 | round) / 100)), pct: ([($c / $ncpu * 100), 100] | min | round1) };

def item_for($ncpu):
  . as $app
  | ($app.pids | map(tostring)) as $pidstrs
  | (reduce $pidstrs[] as $p ({cpu: 0, mem: 0}; . as $acc | ($after[$p] // {cpu: 0, mem: 0}) as $t | {cpu: ($acc.cpu + $t.cpu), mem: ($acc.mem + $t.mem)})) as $post
  | (reduce $pidstrs[] as $p (0; . + ($before[$p].cpu // 0))) as $prior_cpu
  | ($app.bundle // $app.name) as $key
  | (if ($elapsed // 0) > 0 then
       (($post.cpu - $prior_cpu) as $delta | if $delta >= 0 then (($delta / $elapsed * 100) | round1) else null end)
     else null end) as $cpu
  | ($hangs[$key] // false) as $hung
  | ($app.pids | length) as $nproc
  | { id: $key,
      label: $app.name,
      detail: ((if $hung then "not responding · " else "" end) + "\($nproc) process" + (if $nproc == 1 then "" else "es" end)),
      state: (if $hung then "warn" else "ok" end),
      icon: (if $app.bundle then "bundle:\($app.bundle)" else "pid:\($app.pid)" end),
      metrics: ((if $cpu != null then [{id: "cpu", label: "CPU"} + ($cpu | cores_of($ncpu) | {value: .cores, unit: "cores", pct})] else [] end)
                + [{id: "mem", label: "Mem", value: ($post.mem | gib), unit: "GiB"}]),
      actions: [{id: "open", label: "Open"},
                {id: "quit", label: "Quit", removes: true},
                {id: "force-quit", label: "Force quit", removes: true}],
      _mem: $post.mem };

($apps | map(item_for($ncpu)) | sort_by(-._mem)) as $ranked
| ($ranked | .[0:$max_apps] | map(del(._mem))) as $items
| ($ranked | map(select(.state == "warn")) | length) as $hung_count
| ($ranked | map(._mem) | add // 0) as $total_mem
| ($apps | length) as $napps
| ($ranked | map(.metrics[] | select(.id == "cpu") | .value) | add // 0) as $total_cpu_cores
| {
    schema: 1,
    title: "Applications",
    state: (if $hung_count > 0 then "warn" else "ok" end),
    icon: "sf:square.grid.2x2.fill",
    summary: ("\($napps) app" + (if $napps == 1 then "" else "s" end) + " · \($total_mem | gib) GiB"
              + (if $hung_count > 0 then " · \($hung_count) not responding" else "" end)),
    capabilities: { stream: true, refresh: 5 },
    lines: [ { label: "Foreground apps", value: ($napps | tostring), state: "ok" } ],
    metrics: ([{id: "apps_mem", label: "Apps memory", value: ($total_mem | gib), unit: "GiB"}]
              + (if ($elapsed // 0) > 0 then
                   [{id: "apps_cpu", label: "Apps CPU", value: (($total_cpu_cores * 100 | round) / 100),
                     unit: "/ \($ncpu) cores", pct: ([($total_cpu_cores / $ncpu * 100), 100] | min | round1)}]
                 else [] end)),
    items: $items,
    actions: [{id: "activity", label: "Activity Monitor"}]
  }
