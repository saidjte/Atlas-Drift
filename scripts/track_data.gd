class_name TrackData
extends Resource
## v0.7.0: the analytic centerline of the Atlas touge circuit, BAKED ONCE by
## tools/bake_world.gd and shipped as a binary resource
## (res://assets/track/centerline.res). At runtime the game only LOADS this
## file — no Laplacian smoothing, resampling or banking math ever runs on the
## phone anymore ("الغي التوليد البرمجي وقت التشغيل").
##
## Arrays are indexed by the same N uniform arc-length samples the old
## runtime generator produced, so every consumer (car respawn, lap logic,
## HUD progress, smoke tests) keeps working unchanged.

@export var n := 880                    # sample count around the closed loop
@export var total_len := 0.0            # loop length in meters (~2.3 km)
@export var pts := PackedVector3Array()      # centerline positions
@export var tans := PackedVector3Array()     # unit tangents
@export var rgts := PackedVector3Array()     # rolled (banked) right vectors
@export var rgts_flat := PackedVector3Array() # flat right vectors (no banking)
@export var ups := PackedVector3Array()      # banked up vectors
@export var roll := PackedFloat32Array()     # banking roll per sample
@export var kabs := PackedFloat32Array()     # |horizontal curvature| (1/m)
@export var road_idxs := PackedInt32Array()  # RoadPoint sample indices
# v0.8.0 (A Few Roads): sample indices of the apexes that got chevron
# boards + curbs in the bake. Smoke tests use them to run rail-scrape
# checks on clean straights; future HUD hooks can warn "hairpin ahead".
@export var dressed_apexes := PackedInt32Array() # corner-apex samples
