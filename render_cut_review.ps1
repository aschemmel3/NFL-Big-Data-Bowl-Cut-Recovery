param([string]$DrillName='', [switch]$FirstExample)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$out=Join-Path $PSScriptRoot 'reports/cuts'
$examples=Get-Content (Join-Path $out 'review_examples.json') -Raw | ConvertFrom-Json
if($DrillName){$examples=@($examples|Where-Object drill -eq $DrillName)}
if($FirstExample){$examples=@($examples|Select-Object -First 1)}
$font=[System.Drawing.Font]::new('Arial',10)
$title=[System.Drawing.Font]::new('Arial',13,[System.Drawing.FontStyle]::Bold)
$blue=[System.Drawing.Pen]::new([System.Drawing.Color]::SteelBlue,2)
$gray=[System.Drawing.Pen]::new([System.Drawing.Color]::LightGray,1)
$orange=[System.Drawing.Pen]::new([System.Drawing.Color]::DarkOrange,3)
foreach($group in ($examples | Group-Object drill)){
 $bmp=[System.Drawing.Bitmap]::new(1400,(80+300*$group.Count))
 $g=[System.Drawing.Graphics]::FromImage($bmp);$g.Clear([System.Drawing.Color]::White)
 $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
 $g.DrawString($group.Name,$title,[System.Drawing.Brushes]::Black,15,10)
 $g.DrawString('Development only | green=start, red=end, orange=turn windows | speed: blue=smoothed, dotted=90% entry', $font,[System.Drawing.Brushes]::Black,15,35)
 $row=0
 foreach($e in $group.Group){
  $top=80+300*$row;$row++
  $g.DrawString("$($e.name) $($e.year) | $($e.event_id) | $($e.cuts.Count) provisional cuts",$font,[System.Drawing.Brushes]::Black,15,($top-15))
  $f=@($e.frames);$xmin=($f|Measure-Object x -Minimum).Minimum;$xmax=($f|Measure-Object x -Maximum).Maximum
  $ymin=($f|Measure-Object y -Minimum).Minimum;$ymax=($f|Measure-Object y -Maximum).Maximum
  $scale=210/[math]::Max(1,[math]::Max($xmax-$xmin,$ymax-$ymin))
  $pts=[System.Drawing.PointF[]]@($f|ForEach-Object{[System.Drawing.PointF]::new((35+($_.x-$xmin)*$scale),($top+225-($_.y-$ymin)*$scale))})
  $g.DrawLines($blue,$pts)
  $g.FillEllipse([System.Drawing.Brushes]::Green,($pts[0].X-4),($pts[0].Y-4),8,8)
  $g.FillEllipse([System.Drawing.Brushes]::Red,($pts[-1].X-4),($pts[-1].Y-4),8,8)
  $g.DrawString(('Path extent: {0:F1} x {1:F1} yd' -f ($xmax-$xmin),($ymax-$ymin)),$font,[System.Drawing.Brushes]::Black,15,($top+240))
  $duration=$f[-1].t;$maxSpeed=[math]::Ceiling(($f|Measure-Object s -Maximum).Maximum+1)
  $sx=650/[math]::Max(.1,$duration);$sy=200/$maxSpeed
  for($v=0;$v -le $maxSpeed;$v+=2){$y=$top+225-$v*$sy;$g.DrawLine($gray,450,$y,1100,$y);$g.DrawString("$v",$font,[System.Drawing.Brushes]::Black,425,($y-7))}
  for($t=0;$t -le $duration;$t+=2){$x=450+$t*$sx;$g.DrawLine($gray,$x,($top+20),$x,($top+225));$g.DrawString("$t",$font,[System.Drawing.Brushes]::Black,$x,($top+230))}
  $g.DrawString('Speed (yd/s) vs elapsed seconds',$font,[System.Drawing.Brushes]::Black,670,($top+246))
  $sp=[System.Drawing.PointF[]]@($f|ForEach-Object{[System.Drawing.PointF]::new((450+$_.t*$sx),($top+225-$_.smooth*$sy))});$g.DrawLines($blue,$sp)
  foreach($cut in $e.cuts){
    $cf=@($f|Where-Object{$_.t -ge $cut.turn_start_s -and $_.t -le $cut.turn_end_s})
    if($cf.Count -gt 1){$cp=[System.Drawing.PointF[]]@($cf|ForEach-Object{[System.Drawing.PointF]::new((35+($_.x-$xmin)*$scale),($top+225-($_.y-$ymin)*$scale))});$g.DrawLines($orange,$cp)}
    foreach($t in @($cut.turn_start_s,$cut.turn_end_s)){$x=450+$t*$sx;$g.DrawLine($orange,$x,($top+20),$x,($top+225))}
    $g.FillEllipse([System.Drawing.Brushes]::Purple,(446+$cut.minimum_time_s*$sx),($top+221-$cut.minimum_speed_yd_s*$sy),8,8)
    $threshold=[System.Drawing.Pen]::new([System.Drawing.Color]::DarkGreen,1);$threshold.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dot
    $g.DrawLine($threshold,(450+$cut.minimum_time_s*$sx),($top+225-.9*$cut.entry_speed_yd_s*$sy),(450+($cut.minimum_time_s+$cut.followup_s)*$sx),($top+225-.9*$cut.entry_speed_yd_s*$sy));$threshold.Dispose()
    $g.DrawString(('#{0}: {1:F0}deg; loss {2:P0}; {3}' -f $cut.cut_index,$cut.angle_deg,$cut.speed_loss_fraction,$cut.recovery_status),$font,[System.Drawing.Brushes]::Black,450,($top+260+14*($cut.cut_index-1)))
    if($null -ne $cut.entry_window_start_s){
      $g.DrawLine([System.Drawing.Pens]::Green,(450+$cut.entry_window_start_s*$sx),($top+225-$cut.entry_speed_yd_s*$sy),(450+$cut.entry_window_end_s*$sx),($top+225-$cut.entry_speed_yd_s*$sy))
    }
  }
 }
 $suffix=if($FirstExample){'_example'}else{''}
 $bmp.Save((Join-Path $out "$($group.Name)$suffix.png"),[System.Drawing.Imaging.ImageFormat]::Png)
 $g.Dispose();$bmp.Dispose()
}
$font.Dispose();$title.Dispose();$blue.Dispose();$gray.Dispose();$orange.Dispose()
Write-Output "Rendered $(@($examples | Group-Object drill).Count) drill review images."
