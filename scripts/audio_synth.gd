class_name AudioSynth
extends Object
## Runtime-synthesized sounds (no audio files shipped).

const RATE := 22050


static func engine_loop() -> AudioStreamWAV:
        var frames := RATE / 2 # 0.5 s seamless-ish loop
        var data := PackedByteArray()
        data.resize(frames * 2)
        for i in frames:
                var t := float(i) / float(RATE)
                var v := 0.0
                v += 0.50 * _saw(t * 50.0)
                v += 0.28 * _saw(t * 100.0 + 0.13)
                v += 0.12 * sin(TAU * 25.0 * t)
                v += 0.14 * _dnoise(i)
                data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
        return _wav(data, true)


static func skid_loop() -> AudioStreamWAV:
        var frames := RATE * 2 / 5 # 0.4 s
        var data := PackedByteArray()
        data.resize(frames * 2)
        var prev := 0.0
        for i in frames:
                var n := _dnoise(i * 7 + 13)
                prev = prev * 0.82 + n * 0.18 # cheap low-pass
                data.encode_s16(i * 2, int(clampf(prev * 2.4, -1.0, 1.0) * 26000.0))
        return _wav(data, true)


static func beep(freq: float, dur: float, vol := 0.6) -> AudioStreamWAV:
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


static func _saw(cycles: float) -> float:
        return fmod(cycles, 1.0) * 2.0 - 1.0


static func _dnoise(i: int) -> float:
        var v := sin(float(i) * 12.9898) * 43758.5453
        return (v - floor(v)) * 2.0 - 1.0


static func _wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
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
