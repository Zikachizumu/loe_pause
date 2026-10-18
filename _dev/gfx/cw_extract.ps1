param(
    [string]$Gta = 'D:\SteamLibrary\steamapps\common\Grand Theft Auto V',
    [bool]$Gen9 = $false,
    [string]$Pattern = 'scaleform_frontend\.rpf\\pause_menu.*\.gfx$|scaleform_generic\.rpf\\pause_menu.*\.gfx$',
    [string]$Out = 'C:\Users\yasin\AppData\Local\Temp\claude\C--Users-yasin-Desktop-FiveM-VPS\e489275e-1190-4654-af8b-be45eb9c4afd\scratchpad\gfx'
)
$sp = 'C:\Users\yasin\AppData\Local\Temp\claude\C--Users-yasin-Desktop-FiveM-VPS\e489275e-1190-4654-af8b-be45eb9c4afd\scratchpad\cw'
$asm = [Reflection.Assembly]::LoadFrom("$sp\CodeWalker.Core.dll")
Set-Location $sp
$asm.GetType('CodeWalker.GameFiles.GTA5Keys').GetMethod('LoadFromPath').Invoke($null, @($Gta, $Gen9, $null))
$rm = $asm.CreateInstance('CodeWalker.GameFiles.RpfManager')
$rm.Init($Gta, $Gen9, [Action[string]]{ param($s) }, [Action[string]]{ param($s) }, $false, $true)
New-Item -ItemType Directory -Force $Out | Out-Null
# update.rpf sürümü varsa onu tercih et (aynı dosya adı için sonuncusu kazanır: update en sona sıralanır)
$keys = $rm.EntryDict.Keys | Where-Object { $_ -match $Pattern } | Sort-Object { if ($_ -like 'update*') { 1 } else { 0 } }
foreach ($k in $keys) {
    $data = $rm.GetFileData($k)
    if ($data) {
        $name = Split-Path $k -Leaf
        [IO.File]::WriteAllBytes((Join-Path $Out $name), $data)
        "{0}  {1} bytes  <- {2}" -f $name, $data.Length, $k
    } else { "FAIL $k" }
}
