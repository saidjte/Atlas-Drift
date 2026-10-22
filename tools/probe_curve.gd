extends SceneTree
## Probe the baked centerline: sample spacing + curvature distribution.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var td = load("res://assets/track/centerline.res")
	var n: int = td.n
	var step: float = td.total_len / float(n)
	print("PROBE total_len=%.1f m step=%.2f m samples=%d" % [td.total_len, step, n])
	var kabs: PackedFloat32Array = td.kabs
	var mx := 0.0
	var hist := [0, 0, 0, 0, 0, 0]
	for k in kabs:
		mx = maxf(mx, k)
		if k > 1.0/12.0: hist[0] += 1      # r < 12 m
		elif k > 1.0/20.0: hist[1] += 1    # r < 20 m
		elif k > 1.0/30.0: hist[2] += 1
		elif k > 1.0/45.0: hist[3] += 1
		elif k > 1.0/70.0: hist[4] += 1
		else: hist[5] += 1
	print("PROBE kabs max=%.4f (min radius %.1f m)" % [mx, 1.0/mx])
	print("PROBE samples with radius <12m: %d | <20m: %d | <30m: %d | <45m: %d | <70m: %d | flatter: %d" % hist)
	# Count corner runs above r<25m
	var thr := 1.0/25.0
	var runs: Array = []
	var in_run := false
	var start := 0
	for i in n:
		if kabs[i] > thr and not in_run:
			in_run = true; start = i
		elif kabs[i] <= thr and in_run:
			in_run = false
			runs.append([start, i])
	if in_run: runs.append([start, n])
	var long := 0
	for r in runs:
		if r[1] - r[0] >= 6: long += 1
	print("PROBE runs>%.0fm: %d | runs>=6 samples: %d" % [thr * step, runs.size(), long])
	quit(0)
