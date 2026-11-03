$ErrorActionPreference = 'Stop'
$culture = [cultureinfo]::InvariantCulture
$dataPath = Join-Path $PSScriptRoot 'nfl-big-data-bowl-2027/nfl-big-data-bowl-2027'
$outPath = Join-Path $PSScriptRoot 'reports/tracking'
New-Item -ItemType Directory -Force -Path $outPath | Out-Null
$players = @{}
Import-Csv (Join-Path $dataPath 'players.csv') | Where-Object { $_.nfl_position -eq 'WR' -and $_.draft_year -in @('2023','2024') } | ForEach-Object { $players[$_.nfl_id] = $_ }
$events = @{}
Import-Csv (Join-Path $dataPath 'combine_tracking.csv') | ForEach-Object {
    if ($_.entity_type -eq 'PLAYER' -and $_.drill_type -eq 'SKILL_DRILLS_WR' -and $players.ContainsKey($_.nfl_id)) {
        $key = "$($_.nfl_id)|$($_.event_id)|$($_.attempt)"
        if (-not $events.ContainsKey($key)) { $events[$key] = [System.Collections.Generic.List[object]]::new() }
        $events[$key].Add($_)
    }
}
$summaries = foreach ($key in ($events.Keys | Sort-Object)) {
    $raw = @($events[$key])
    $frames = @($raw | Sort-Object time)
    $first = $frames[0]
    $duplicates = 0; $gaps = 0; $jumps = 0; $invalid = 0
    $errors = [System.Collections.Generic.List[double]]::new()
    for ($i = 0; $i -lt $frames.Count; $i++) {
        $f = $frames[$i]
        if ($f.x -eq '' -or $f.y -eq '' -or $f.s -eq '') { $invalid++; continue }
        if ($i -eq 0) { continue }
        $p = $frames[$i-1]
        $dt = ([datetime]::Parse($f.time, $culture) - [datetime]::Parse($p.time, $culture)).TotalSeconds
        if ($dt -eq 0) { $duplicates++; continue }
        if ($dt -gt 0.15) { $gaps++ }
        if ($p.x -eq '' -or $p.y -eq '' -or $p.s -eq '') { continue }
        $dx = [double]::Parse($f.x,$culture) - [double]::Parse($p.x,$culture)
        $dy = [double]::Parse($f.y,$culture) - [double]::Parse($p.y,$culture)
        $coordinateSpeed = [math]::Sqrt($dx*$dx+$dy*$dy)/$dt
        if ($coordinateSpeed -gt 15) { $jumps++ }
        $expected = ([double]::Parse($f.s,$culture)+[double]::Parse($p.s,$culture))/2
        $errors.Add([math]::Abs($coordinateSpeed-$expected))
    }
    $sortedErrors = @($errors | Sort-Object)
    [pscustomobject]@{
        nfl_id=$first.nfl_id; name=$players[$first.nfl_id].display_name; draft_year=$first.draft_year
        event_id=$first.event_id; attempt=$first.attempt; drill_name=$first.drill_name
        frames=$frames.Count; duration_s=([datetime]::Parse($frames[-1].time,$culture)-[datetime]::Parse($first.time,$culture)).TotalSeconds
        duplicate_times=$duplicates; gaps_over_150ms=$gaps; coordinate_speed_over_15=$jumps; missing_numeric_frames=$invalid
        median_speed_abs_error=$(if($sortedErrors.Count){$sortedErrors[[int][math]::Floor(($sortedErrors.Count-1)/2)]}else{$null})
    }
}
$summaries | Export-Csv (Join-Path $outPath 'development_event_quality.csv') -NoTypeInformation
# Select one deterministic example per unmodified drill label. No NFL outcomes or 2025 data are read.
$examples = @($summaries | Group-Object drill_name | ForEach-Object { $_.Group | Sort-Object duplicate_times,gaps_over_150ms,coordinate_speed_over_15,nfl_id,event_id | Select-Object -First 1 })
$html = [System.Text.StringBuilder]::new()
[void]$html.Append('<!doctype html><meta charset="utf-8"><title>WR development tracking diagnostics</title><style>body{font:16px system-ui;max-width:1100px;margin:30px auto}svg{border:1px solid #ddd;margin:8px}section{margin-bottom:35px}polyline{fill:none;stroke:#176a9a;stroke-width:2}</style><h1>WR development tracking diagnostics</h1><p>2023–2024 only. One deterministic example per original drill label. Green marks the start; red marks the end. Paths use equal coordinate scales. Speed curves use actual elapsed time. These are inspection plots, not validated cut measurements.</p>')
foreach ($example in $examples) {
    $key = "$($example.nfl_id)|$($example.event_id)|$($example.attempt)"
    $frames = @($events[$key] | Sort-Object time)
    $xs = @($frames | ForEach-Object { [double]::Parse($_.x,$culture) }); $ys = @($frames | ForEach-Object { [double]::Parse($_.y,$culture) })
    $minX=($xs|Measure-Object -Minimum).Minimum; $maxX=($xs|Measure-Object -Maximum).Maximum
    $minY=($ys|Measure-Object -Minimum).Minimum; $maxY=($ys|Measure-Object -Maximum).Maximum
    $scale=320/[math]::Max(1,[math]::Max($maxX-$minX,$maxY-$minY))
    $pathPoints = for($i=0;$i -lt $frames.Count;$i++){ '{0},{1}' -f (20+($xs[$i]-$minX)*$scale).ToString('F2',$culture),(340-($ys[$i]-$minY)*$scale).ToString('F2',$culture) }
    $speedPoints = foreach($f in $frames){ $t=([datetime]::Parse($f.time,$culture)-[datetime]::Parse($frames[0].time,$culture)).TotalSeconds; '{0},{1}' -f (30+400*$t/[math]::Max(0.1,$example.duration_s)).ToString('F2',$culture),(320-25*[double]::Parse($f.s,$culture)).ToString('F2',$culture) }
    $label=[System.Net.WebUtility]::HtmlEncode("$($example.drill_name): $($example.name) ($($example.draft_year))")
    [void]$html.Append("<section><h2>$label</h2><p>Event $($example.event_id), attempt $($example.attempt). Frames: $($example.frames); gaps: $($example.gaps_over_150ms); duplicate times: $($example.duplicate_times).</p><svg viewBox='0 0 370 370' width='370'><polyline points='$($pathPoints -join ' ')'/><circle cx='$($pathPoints[0].Split(',')[0])' cy='$($pathPoints[0].Split(',')[1])' r='4' fill='green'/><circle cx='$($pathPoints[-1].Split(',')[0])' cy='$($pathPoints[-1].Split(',')[1])' r='4' fill='red'/><text x='15' y='365'>Trajectory (x/y in source coordinates)</text></svg><svg viewBox='0 0 460 370' width='460'><path d='M30 20V320H435' fill='none' stroke='gray'/><polyline points='$($speedPoints -join ' ')'/><text x='30' y='345'>0 to $($example.duration_s) seconds</text><text x='30' y='18'>Speed (source s), vertical range 0–12</text></svg></section>")
}
$html.ToString() | Set-Content (Join-Path $outPath 'development_diagnostics.html') -Encoding utf8
[pscustomobject]@{players=$players.Count; events=@($summaries).Count; examples=$examples.Count; duplicate_times=($summaries|Measure-Object duplicate_times -Sum).Sum; gaps=($summaries|Measure-Object gaps_over_150ms -Sum).Sum; coordinate_speed_over_15=($summaries|Measure-Object coordinate_speed_over_15 -Sum).Sum} | ConvertTo-Json | Set-Content (Join-Path $outPath 'development_summary.json')
Get-Content (Join-Path $outPath 'development_summary.json')
