$ErrorActionPreference='Stop'
$data=Join-Path $PSScriptRoot 'nfl-big-data-bowl-2027/nfl-big-data-bowl-2027'
$players=@{};$games=@{};$routes=@{};$cushion=@{}
Import-Csv (Join-Path $data 'players.csv')|Where-Object nfl_position -eq WR|ForEach-Object{$players[$_.nfl_id]=$_}
Import-Csv (Join-Path $data 'games.csv')|ForEach-Object{$games[$_.game_id]=$_}
Import-Csv (Join-Path $data 'player_play.csv')|ForEach-Object{
 if($players.ContainsKey($_.nfl_id) -and $games.ContainsKey($_.game_id) -and $_.route_ran -notin @('','NA') -and $_.play_nullified_by_penalty -eq 'N'){
  $p=$players[$_.nfl_id];$g=$games[$_.game_id]
  if($g.season -eq $p.draft_year -and $g.season_type -eq 'REG'){
   $key="$($p.draft_year)|$($_.route_ran)"
   if(-not $routes.ContainsKey($key)){$routes[$key]=[pscustomobject]@{draft_year=$p.draft_year;route=$_.route_ran;routes=0;players=[System.Collections.Generic.HashSet[string]]::new()}}
   $routes[$key].routes++;[void]$routes[$key].players.Add($_.nfl_id)
   $year=$p.draft_year
   if(-not $cushion.ContainsKey($year)){$cushion[$year]=[ordered]@{draft_year=$year;routes=0;cushion_present=0;cushion_le_1=0;cushion_le_2=0;le_2_man_no_motion=0}}
   $cushion[$year].routes++
   $distance=0.0
   if([double]::TryParse($_.cushion,[System.Globalization.NumberStyles]::Float,[cultureinfo]::InvariantCulture,[ref]$distance)){
    $cushion[$year].cushion_present++
    if($distance -le 1){$cushion[$year].cushion_le_1++}
    if($distance -le 2){
     $cushion[$year].cushion_le_2++
     if($_.team_coverage_man_zone -eq 'MAN_COVERAGE' -and $_.in_motion_at_ball_snap -eq 'False'){$cushion[$year].le_2_man_no_motion++}
    }
   }
  }
 }
}
$out=Join-Path $PSScriptRoot 'reports/cuts'
$routes.Values|Sort-Object draft_year,route|ForEach-Object{[pscustomobject]@{draft_year=$_.draft_year;route=$_.route;routes=$_.routes;players=$_.players.Count}}|Export-Csv (Join-Path $out 'rookie_route_label_coverage.csv') -NoTypeInformation
$cushion.Values|ForEach-Object{[pscustomobject]$_}|Sort-Object draft_year|Export-Csv (Join-Path $out 'rookie_cushion_coverage.csv') -NoTypeInformation
Get-Content (Join-Path $out 'rookie_route_label_coverage.csv')
Get-Content (Join-Path $out 'rookie_cushion_coverage.csv')
Import-Csv (Join-Path $data 'combine_results.csv')|Where-Object{$players.ContainsKey($_.nfl_id)}|Group-Object draft_year|ForEach-Object{[pscustomobject]@{year=$_.Name;ten_yd_split=@($_.Group|Where-Object ten_yd_split -NotIn @('','NA')).Count;vertical=@($_.Group|Where-Object vertical -NotIn @('','NA')).Count;broad_jump=@($_.Group|Where-Object broad_jump -NotIn @('','NA')).Count}}|Format-Table
