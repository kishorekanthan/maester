def states: ["ok", "warn", "error", "off"];
def schemes: ["bundle", "path", "pid", "sf", "asset"];

def icon_check(obj; $tag):
  (obj.icon) as $v
  | if $v == null then []
    elif ($v | type) != "string" or ($v | index(":")) == null then
      ["\($tag): icon must be '<scheme>:<value>'"]
    else
      ($v | split(":")[0]) as $scheme
      | ($v | sub("^[^:]*:"; "")) as $rest
      | if (schemes | index($scheme)) == null then
          ["\($tag): unknown icon scheme \"\($scheme)\", expected one of \(schemes | join(", "))"]
        elif ($rest | length) == 0 then
          ["\($tag): icon \"\($v)\" has no value"]
        else []
        end
    end;

def dup_at($arr; $i):
  ($arr[$i].id) as $id
  | if ($id | type) == "string" and ($id | length) > 0 then
      ([range(0; $i) | select($arr[.].id == $id)] | length) > 0
    else false
    end;

def metrics_check($ms; $at):
  ($ms // []) as $arr
  | reduce range(0; $arr | length) as $i
      ({errors: [], warnings: []};
        ($arr[$i]) as $m
        | "\($at).metrics[\($i)]" as $tag
        | if ($m | type) != "object" then
            .errors += ["\($tag) is not an object"]
          else
            ( if ($m.id | type) != "string" or ($m.id | length) == 0 then
                .errors += ["\($tag): id missing — it is the sparkline history key"]
              elif dup_at($arr; $i) then
                .errors += ["\($tag): duplicate id \"\($m.id)\""]
              else . end
            | ($m.value != null) as $has_num
            | ($m.text != null) as $has_text
            | if $has_num and $has_text then
                .errors += ["\($tag): has both value and text; pick one"]
              elif ($has_num | not) and ($has_text | not) then
                .warnings += ["\($tag): neither value nor text — renders as '—'"]
              else . end
            | if $has_num and ($m.value | type) != "number" then
                .errors += ["\($tag): value must be numeric"]
              elif $has_num and ($m.unit | type) != "string" then
                .warnings += ["\($tag): numeric metric with no unit"]
              else . end
            | ($m.pct) as $p
            | if $p != null and (($p | type) != "number" or $p < 0 or $p > 100) then
                .errors += ["\($tag): pct \($p) outside 0..100"]
              else . end )
          end
      );

def actions_check($acts; $at):
  ($acts // []) as $arr
  | reduce range(0; $arr | length) as $i
      ({errors: []};
        ($arr[$i]) as $a
        | "\($at).actions[\($i)]" as $tag
        | if ($a | type) != "object" then
            .errors += ["\($tag) is not an object"]
          else
            ( if ($a.id | type) != "string" or ($a.id | length) == 0 then
                .errors += ["\($tag): id missing — Maester dispatches on it"]
              elif dup_at($arr; $i) then
                .errors += ["\($tag): duplicate action id \"\($a.id)\""]
              else . end
            | if ($a.label | type) != "string" or ($a.label | length) == 0 then
                .errors += ["\($tag): label missing"]
              else . end )
          end
      );

def validate($d; $where):
  {errors: [], warnings: []}
  | if ($d | type) != "object" then
      .errors += ["\($where) is not a JSON object"]
    else
      ( if $d.schema != 1 then .errors += ["\($where): schema must be 1, got \($d.schema)"] else . end
      | if ($d.title | type) != "string" or ($d.title | length) == 0 then
          .errors += ["\($where): title missing"]
        else . end
      | if (states | index($d.state)) == null then
          .errors += ["\($where): state \($d.state) not one of \(states)"]
        else . end
      | if ($d | has("summary")) and ($d.summary | type) != "string" then
          .errors += ["\($where): summary must be a string"]
        else . end
      | .errors += icon_check($d; $where)
      | ($d.capabilities // {}) as $caps
      | if ($caps | type) != "object" then
          .errors += ["\($where): capabilities must be an object"]
        else
          ( ($caps.refresh) as $r
          | if $r != null and (($r | type) != "number" or $r < 1 or $r > 3600) then
              .errors += ["\($where): capabilities.refresh \($r) outside 1..3600"]
            else . end )
        end
      | ($d.lines // []) as $lines
      | reduce range(0; $lines | length) as $i (.;
          ($lines[$i]) as $l
          | if ($l | type) != "object" or ($l.label | type) != "string" then
              .errors += ["\($where): lines[\($i)] needs a label"]
            elif $l.state != null and (states | index($l.state)) == null then
              .errors += ["\($where): lines[\($i)].state \($l.state) invalid"]
            else . end)
      | (metrics_check($d.metrics; $where)) as $mres
      | .errors += $mres.errors | .warnings += $mres.warnings
      | (actions_check($d.actions; $where)) as $ares
      | .errors += $ares.errors
      | ($d.items // []) as $items
      | reduce range(0; $items | length) as $i (.;
          ($items[$i]) as $it
          | "\($where).items[\($i)]" as $tag
          | if ($it | type) != "object" then
              .errors += ["\($tag) is not an object"]
            else
              ( .errors += icon_check($it; $tag)
              | ( if ($it.id | type) != "string" or ($it.id | length) == 0 then
                    .errors += ["\($tag): id missing — it keys metric history and is passed to `do`"]
                  elif dup_at($items; $i) then
                    .errors += ["\($tag): duplicate item id \"\($it.id)\""]
                  else . end )
              | ( if ($it.label | type) != "string" or ($it.label | length) == 0 then
                    .errors += ["\($tag): label missing"]
                  else . end )
              | ( if $it.state != null and (states | index($it.state)) == null then
                    .errors += ["\($tag): state \($it.state) invalid"]
                  else . end )
              | (metrics_check($it.metrics; $tag)) as $imres
              | .errors += $imres.errors | .warnings += $imres.warnings
              | (actions_check($it.actions; $tag)) as $iares
              | .errors += $iares.errors )
          end))
    end;

validate($d; $where)
