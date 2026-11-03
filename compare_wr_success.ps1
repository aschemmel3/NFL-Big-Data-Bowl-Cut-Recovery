$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'reports/success'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$success = @{}
Import-Csv (Join-Path $PSScriptRoot 'nfl-big-data-bowl-2027/nfl-big-data-bowl-2027/player_career_successes.csv') | ForEach-Object { $success[$_.nfl_id] = $_ }
$rows = @(Import-Csv (Join-Path $PSScriptRoot 'reports/wr_player_coverage.csv') | ForEach-Object {
    $s = $success[$_.nfl_id]
    if ($null -eq $s) { throw "Missing career row: $($_.nfl_id)" }
    [pscustomobject]@{
        nfl_id=$_.nfl_id; name=$_.name; draft_year=$_.draft_year
        measured_routes=[int]$_.rookie_separation_routes
        separation=$(if([int]$_.rookie_separation_routes -gt 0){[double]$_.rookie_mean_separation}else{$null})
        career_snaps=[int]$s.career_offensive_snaps; career_starts=[int]$s.career_games_started
        active_games=[int]$s.career_games_active
        snaps_per_active_game=$(if([int]$s.career_games_active -gt 0){[double]$s.career_offensive_snaps/[double]$s.career_games_active}else{$null})
        honored=([int]$s.ap_all_pro_1st_team+[int]$s.ap_all_pro_2nd_team+[int]$s.pro_bowl_original_ballot -gt 0)
        top_quartile_snaps=$false
    }
})
# Define playing-time groups using all WRs in each class, before outcome exclusions.
foreach($class in ($rows | Group-Object draft_year)) {
    $ordered = @($class.Group | Sort-Object career_snaps -Descending)
    $index = [int][math]::Ceiling($ordered.Count/4)-1
    $threshold = $ordered[$index].career_snaps
    foreach($r in $class.Group){ $r.top_quartile_snaps = $r.career_snaps -ge $threshold }
}
$rows | Export-Csv (Join-Path $out 'wr_success_player_comparison.csv') -NoTypeInformation
$rng = [random]::new(20261102)
function Mean($values) { ($values | Measure-Object -Average).Average }
$comparisons = @(foreach($minimum in @(1,50)) {
    foreach($label in @('2023','2024','2025','all')) {
        $eligible = @($rows | Where-Object { $_.measured_routes -ge $minimum -and ($label -eq 'all' -or $_.draft_year -eq $label) })
        foreach($definition in @('honored','top_quartile_snaps')) {
            $high = @($eligible | Where-Object { $_.$definition })
            $low = @($eligible | Where-Object { -not $_.$definition })
            $delta=$null; $lo=$null; $hi=$null
            if($high.Count -and $low.Count){
                $delta=(Mean $high.separation)-(Mean $low.separation)
                # Resample receivers separately within class and success group.
                $strata = @($eligible | Group-Object { "$($_.draft_year)|$($_.$definition)" })
                $boot = @(for($b=0;$b -lt 2000;$b++){
                    $hs=0.0; $ls=0.0; $hn=0; $ln=0
                    foreach($stratum in $strata){
                        for($j=0;$j -lt $stratum.Count;$j++){
                            $r=$stratum.Group[$rng.Next($stratum.Count)]
                            if($r.$definition){$hs+=$r.separation; $hn++}else{$ls+=$r.separation; $ln++}
                        }
                    }
                    $hs/$hn-$ls/$ln
                })
                $boot = @($boot | Sort-Object)
                $lo=$boot[49]; $hi=$boot[1949]
            }
            [pscustomobject]@{
                minimum_routes=$minimum; draft_year=$label; success_definition=$definition
                successful_n=$high.Count; other_n=$low.Count
                successful_mean_yards=$(if($high.Count){Mean $high.separation}else{$null})
                other_mean_yards=$(if($low.Count){Mean $low.separation}else{$null})
                difference_yards=$delta; bootstrap_95_low=$lo; bootstrap_95_high=$hi
            }
        }
    }
})
$comparisons | Export-Csv (Join-Path $out 'wr_success_group_comparison.csv') -NoTypeInformation
$comparisons | Where-Object minimum_routes -eq 50 | Format-Table -AutoSize
$rows | Where-Object { $_.honored } | Select-Object name,draft_year,measured_routes,separation,career_snaps | Format-Table -AutoSize
