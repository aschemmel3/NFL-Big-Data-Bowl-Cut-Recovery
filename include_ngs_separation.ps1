$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$supplement = @{}
Import-Csv (Join-Path $root 'data/external/nflverse/rookie_receiving_matched.csv') | ForEach-Object {
    $key = "$($_.nfl_id)|$($_.draft_year)"
    if ($supplement.ContainsKey($key)) { throw "Duplicate NGS rookie key: $key" }
    $supplement[$key] = $_
}
$inputPath = Join-Path $root 'reports/success/wr_success_player_comparison.csv'
if (-not (Test-Path $inputPath)) { throw 'Run compare_wr_success.ps1 first.' }
$rows = @(Import-Csv $inputPath | ForEach-Object {
    $r = $_
    $ngs = $supplement["$($r.nfl_id)|$($r.draft_year)"]
    $r | Add-Member -NotePropertyName ngs_catch_or_incompletion_separation_yards -NotePropertyValue $(if($ngs){$ngs.ngs_avg_separation}else{$null})
    $r | Add-Member -NotePropertyName ngs_targets -NotePropertyValue $(if($ngs){$ngs.ngs_targets}else{$null})
    $r | Add-Member -NotePropertyName ngs_available -NotePropertyValue ($null -ne $ngs)
    $r
})
$rows | Export-Csv (Join-Path $root 'reports/success/wr_success_with_ngs.csv') -NoTypeInformation
$matched = @($rows | Where-Object { $_.ngs_available -and [int]$_.measured_routes -ge 50 })
$summary = @(foreach($label in @('2023','2024','2025','all')) {
    foreach($definition in @('honored','top_quartile_snaps')) {
        foreach($group in @('True','False')) {
            $selected = @($matched | Where-Object { $_.$definition -eq $group -and ($label -eq 'all' -or $_.draft_year -eq $label) })
            [pscustomobject]@{
                draft_year=$label; success_definition=$definition; success_group=$group; receivers=$selected.Count
                mean_throw_separation_yards=$(if($selected.Count){($selected | ForEach-Object {[double]$_.separation} | Measure-Object -Average).Average}else{$null})
                mean_catch_or_incompletion_separation_yards=$(if($selected.Count){($selected | ForEach-Object {[double]$_.ngs_catch_or_incompletion_separation_yards} | Measure-Object -Average).Average}else{$null})
            }
        }
    }
})
$summary | Export-Csv (Join-Path $root 'reports/success/wr_success_ngs_groups.csv') -NoTypeInformation
$rows | Group-Object draft_year | ForEach-Object { [pscustomobject]@{draft_year=$_.Name; receivers=$_.Count; ngs_available=@($_.Group | Where-Object ngs_available).Count} } | Format-Table
$summary | Where-Object draft_year -eq 'all' | Format-List
$matched | Where-Object name -eq 'Jaxon Smith-Njigba' | Select-Object name,separation,ngs_catch_or_incompletion_separation_yards,ngs_targets | Format-List
