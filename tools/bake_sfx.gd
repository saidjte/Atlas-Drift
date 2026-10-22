extends SceneTree
## v0.7.0 SFX BAKER — replaces ALL runtime WAV synthesis with files.
##
##   godot --headless --path . -s res://tools/bake_sfx.gd
##
## The old AudioSynth class generated every sound buffer in GDScript loops on
## the phone at startup. This tool runs the exact same synthesis ONCE here and
## saves real WAV files into res://assets/audio/sfx/ — at runtime the game
## just load()s them like any other asset.

const RATE := 22050
const OUT := "res://assets/audio/sfx/"


func _initialize() -> void:
        _run.call_deferred()


func _run() -> void:
        DirAccess.make_dir_recursive_absolute(OUT)
        var items := {
                "ui_countdown": beep(392.0, 0.16, 0.55),
                "ui_go": beep(784.0, 0.5, 0.6),
                "race_checkpoint": beep(660.0, 0.2, 0.5),
                "race_lap": chime(),
                "race_best": fanfare(),
                "race_card": beep(880.0, 0.3, 0.35),
                "race_wrong": wrong_buzz(),
                "car_thud": thud(),
        }
        var ok := true
        for k: String in items:
                var ws: AudioStreamWAV = items[k]
                var path := OUT + k + ".wav"
                var err := ws.save_to_wav(path)
                if err != OK:
                        push_error("BAKE sfx: %s failed (%d)" % [path, err])
                        ok = false
                else:
                        print("BAKE sfx: %s (%d frames)" % [path, ws.data.size() / 2])
        if ok:
                print("BAKE_SFX_OK")
                quit(0)
        else:
                quit(1)


# ---- the exact synthesis code that used to run on the phone (moved from
# scripts/audio_synth.gd, unchanged formulas) ----

func beep(freq: float, dur: float, vol := 0.6) -> AudioStreamWAV:
        var frames := int(RATE * dur)
        var data := PackedByteArray()
        data.resize(frames * 2)
        for i in frames:
                var t := float(i) / float(RATE)
                var fade := 1.0
                if i > frames - RATE / 20:
                        fade = float(frames - i) / float(RATE / 20)
                var v := sin(TAU * freq * t) * vol * fade
                data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
        return _wav(data, false)


func chime() -> AudioStreamWAV:
        var dur := 0.55
        var frames := int(RATE * dur)
        var data := PackedByteArray()
        data.resize(frames * 2)
        for i in frames:
                var t := float(i) / float(RATE)
                var v := 0.0
                if t < 0.28:
                        v += sin(TAU * 523.0 * t) * 0.5
                if t > 0.16:
                        var t2 := t - 0.16
                        v += sin(TAU * 784.0 * t2) * 0.5
                var fade := clampf((dur - t) / 0.12, 0.0, 1.0)
                data.encode_s16(i * 2, int(clampf(v * fade, -1.0, 1.0) * 30000.0))
        return _wav(data, false)


func fanfare() -> AudioStreamWAV:
        var notes := [523.0, 659.0, 784.0]
        var dur := 0.9
        var frames := int(RATE * dur)
        var data := PackedByteArray()
        data.resize(frames * 2)
        for i in frames:
                var t := float(i) / float(RATE)
                var v := 0.0
                for k in notes.size():
                        var t0 := float(k) * 0.22
                        if t >= t0:
                                var tk := t - t0
                                var env := clampf(1.0 - tk / 0.42, 0.0, 1.0)
                                v += sin(TAU * notes[k] * tk) * 0.42 * env
                data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
        return _wav(data, false)


func thud() -> AudioStreamWAV:
        var dur := 0.22
        var frames := int(RATE * dur)
        var data := PackedByteArray()
        data.resize(frames * 2)
        var prev := 0.0
        for i in frames:
                var t := float(i) / float(RATE)
                var env := exp(-t * 16.0)
                var n := _dnoise(i * 11 + 5)
                prev = prev * 0.9 + n * 0.1
                var v := (sin(TAU * 85.0 * t) * 0.8 + prev * 1.6) * env * 0.8
                data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
        return _wav(data, false)


func wrong_buzz() -> AudioStreamWAV:
        var dur := 0.42
        var frames := int(RATE * dur)
        var data := PackedByteArray()
        data.resize(frames * 2)
        for i in frames:
                var t := float(i) / float(RATE)
                var gate := 1.0 if fmod(t, 0.24) < 0.15 else 0.0
                var v := (sin(TAU * 196.0 * t) + sin(TAU * 233.0 * t)) * 0.32 * gate
                data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
        return _wav(data, false)


func _dnoise(i: int) -> float:
        var v := sin(float(i) * 12.9898) * 43758.5453
        return (v - floor(v)) * 2.0 - 1.0


func _wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
        var ws := AudioStreamWAV.new()
        ws.format = AudioStreamWAV.FORMAT_16_BITS
        ws.mix_rate = RATE
        ws.stereo = false
        ws.data = data
        if loop:
                ws.loop_mode = AudioStreamWAV.LOOP_FORWARD
                ws.loop_begin = 0
                ws.loop_end = data.size() / 2
        return ws
