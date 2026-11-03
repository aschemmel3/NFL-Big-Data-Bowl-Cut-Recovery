$ErrorActionPreference = 'Stop'
$dataPath = Join-Path $PSScriptRoot 'nfl-big-data-bowl-2027/nfl-big-data-bowl-2027'
$outputPath = Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
function HasValue($value) { return ($null -ne $value -and $value -notin @('', 'NA', 'NaN', 'null')) }
$players = @{}
$games = @{}
$drills = @{}
Import-Csv (Join-Path $dataPath 'games.csv') | ForEach-Object { $games[$_.game_id] = $_ }
Import-Csv (Join-Path $dataPath 'players.csv') | Where-Object nfl_position -eq 'WR' | ForEach-Object {
    $players[$_.nfl_id] = [ordered]@{
        nfl_id = $_.nfl_id; name = $_.display_name; draft_year = $_.draft_year
        draft_overall_pick = $_.draft_overall_pick
        forty = ''; ten_yd_split = ''; three_cone = ''; short_shuttle = ''
        tracking_frames = 0; tracking_events = [System.Collections.Generic.HashSet[string]]::new()
        skill_events = [System.Collections.Generic.HashSet[string]]::new()
        agility_events = [System.Collections.Generic.HashSet[string]]::new()
        rookie_routes = 0; rookie_separation_routes = 0; rookie_target_routes = 0
        rookie_target_separation_routes = 0; rookie_nontarget_routes = 0
        rookie_nontarget_separation_routes = 0; rookie_separation_sum = 0.0
    }
}
Import-Csv (Join-Path $dataPath 'combine_results.csv') | ForEach-Object {
    if ($players.ContainsKey($_.nfl_id)) {
        foreach ($column in @('forty','ten_yd_split','three_cone','short_shuttle')) {
            $players[$_.nfl_id][$column] = $_.$column
        }
    }
}
Write-Output 'Auditing combine tracking...'
Import-Csv (Join-Path $dataPath 'combine_tracking.csv') | ForEach-Object {
    if ($_.entity_type -eq 'PLAYER' -and $players.ContainsKey($_.nfl_id)) {
        $p = $players[$_.nfl_id]
        $p.tracking_frames++
        [void]$p.tracking_events.Add($_.event_id)
        if ($_.drill_type -eq 'SKILL_DRILLS_WR') { [void]$p.skill_events.Add($_.event_id) }
        if ($_.drill_type -in @('SHORT_SHUTTLE','THREE_CONE_DRILL')) { [void]$p.agility_events.Add($_.event_id) }
        $key = "$($_.draft_year)|$($_.drill_type)|$($_.drill_name)"
        if (-not $drills.ContainsKey($key)) {
            $drills[$key] = [ordered]@{ draft_year=$_.draft_year; drill_type=$_.drill_type; drill_name=$_.drill_name; frames=0; players=[System.Collections.Generic.HashSet[string]]::new(); events=[System.Collections.Generic.HashSet[string]]::new() }
        }
        $drills[$key].frames++
        [void]$drills[$key].players.Add($_.nfl_id)
        [void]$drills[$key].events.Add("$($_.nfl_id)|$($_.event_id)")
    }
}
Write-Output 'Auditing rookie regular-season routes and separation...'
$unmatchedGames = 0
Import-Csv (Join-Path $dataPath 'player_play.csv') | ForEach-Object {
    if ($players.ContainsKey($_.nfl_id) -and (HasValue $_.route_ran) -and $_.play_nullified_by_penalty -eq 'N') {
        if (-not $games.ContainsKey($_.game_id)) { $unmatchedGames++ }
        else {
            $p = $players[$_.nfl_id]
            $g = $games[$_.game_id]
            if ($g.season -eq $p.draft_year -and $g.season_type -eq 'REG') {
                $p.rookie_routes++
                $isTarget = $_.target -eq 'TRUE'
                if ($isTarget) { $p.rookie_target_routes++ } else { $p.rookie_nontarget_routes++ }
                if (HasValue $_.separation_at_pass_forward) {
                    $p.rookie_separation_routes++
                    $p.rookie_separation_sum += [double]::Parse($_.separation_at_pass_forward, [cultureinfo]::InvariantCulture)
                    if ($isTarget) { $p.rookie_target_separation_routes++ } else { $p.rookie_nontarget_separation_routes++ }
                }
            }
        }
    }
}
$rows = @($players.Values | ForEach-Object {
    $p = $_
    [pscustomobject][ordered]@{
        nfl_id=$p.nfl_id; name=$p.name; draft_year=$p.draft_year; draft_overall_pick=$p.draft_overall_pick
        forty=$p.forty; ten_yd_split=$p.ten_yd_split; three_cone=$p.three_cone; short_shuttle=$p.short_shuttle
        complete_traditional_tests=((HasValue $p.forty) -and (HasValue $p.three_cone) -and (HasValue $p.short_shuttle))
        tracking_frames=$p.tracking_frames; tracking_events=$p.tracking_events.Count
        skill_events=$p.skill_events.Count; agility_events=$p.agility_events.Count
        rookie_routes=$p.rookie_routes; rookie_separation_routes=$p.rookie_separation_routes
        rookie_target_routes=$p.rookie_target_routes; rookie_target_separation_routes=$p.rookie_target_separation_routes
        rookie_nontarget_routes=$p.rookie_nontarget_routes; rookie_nontarget_separation_routes=$p.rookie_nontarget_separation_routes
        rookie_mean_separation=$(if ($p.rookie_separation_routes -gt 0) { $p.rookie_separation_sum / $p.rookie_separation_routes } else { $null })
    }
} | Sort-Object draft_year,name)
$rows | Export-Csv (Join-Path $outputPath 'wr_player_coverage.csv') -NoTypeInformation
$drills.Values | ForEach-Object {
    [pscustomobject]@{ draft_year=$_.draft_year; drill_type=$_.drill_type; drill_name=$_.drill_name; frames=$_.frames; players=$_.players.Count; events=$_.events.Count }
} | Sort-Object draft_year,drill_type,drill_name | Export-Csv (Join-Path $outputPath 'wr_drill_coverage.csv') -NoTypeInformation
$summary = @($rows | Group-Object draft_year | ForEach-Object {
    $r = @($_.Group)
    [pscustomobject][ordered]@{
        draft_year=$_.Name; receivers=$r.Count
        with_forty=@($r | Where-Object { HasValue $_.forty }).Count
        with_three_cone=@($r | Where-Object { HasValue $_.three_cone }).Count
        with_shuttle=@($r | Where-Object { HasValue $_.short_shuttle }).Count
        complete_traditional_tests=@($r | Where-Object complete_traditional_tests).Count
        with_skill_tracking=@($r | Where-Object skill_events -gt 0).Count
        with_agility_tracking=@($r | Where-Object agility_events -gt 0).Count
        with_rookie_separation=@($r | Where-Object rookie_separation_routes -gt 0).Count
        with_50_rookie_separation_routes=@($r | Where-Object rookie_separation_routes -ge 50).Count
        with_100_rookie_separation_routes=@($r | Where-Object rookie_separation_routes -ge 100).Count
        rookie_routes=($r | Measure-Object rookie_routes -Sum).Sum
        separation_routes=($r | Measure-Object rookie_separation_routes -Sum).Sum
        target_routes=($r | Measure-Object rookie_target_routes -Sum).Sum
        target_separation_routes=($r | Measure-Object rookie_target_separation_routes -Sum).Sum
        nontarget_routes=($r | Measure-Object rookie_nontarget_routes -Sum).Sum
        nontarget_separation_routes=($r | Measure-Object rookie_nontarget_separation_routes -Sum).Sum
    }
})
[ordered]@{ cohorts=$summary; route_rows_with_unmatched_games=$unmatchedGames; notes=@('Routes require nonmissing route_ran, nonnullified play, rookie season, and REG season_type.','Tracking availability is not a count of valid cuts; cut extraction and quality checks remain.','Fifty and 100 routes are sensitivity thresholds, not preselected inclusion requirements.') } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outputPath 'wr_coverage_summary.json')
$summary | Format-List
