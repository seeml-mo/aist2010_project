param([string]$Map = 'res://maps/demo.json', [switch]$Editor, [switch]$Test)
$engine = Join-Path $PSScriptRoot '..\tools\godot_4.5.2\Godot_v4.5.2-stable_win64_console.exe'
if (!(Test-Path -LiteralPath $engine)) {
    $found = Get-Command godot -ErrorAction SilentlyContinue
    if (!$found) { throw 'Install Godot 4.5+ and add godot to PATH, or import project.godot manually.' }
    $engine = $found.Source
}
if ($Editor) { & $engine --path $PSScriptRoot --editor }
elseif ($Test) { & $engine --headless --path $PSScriptRoot --script res://tests/smoke.gd }
else { & $engine --path $PSScriptRoot -- "--map=$Map" }
exit $LASTEXITCODE
