# Third-party notices

## Godot Engine
MIT License — Copyright (c) 2014-present Juan Linietsky, Ariel Manzur and contributors.
https://godotengine.org

## Tajawal font (assets/fonts/Tajawal-Regular.ttf, Tajawal-Bold.ttf)
Copyright (c) 2017 by Boutros International.
Licensed under the SIL Open Font License, Version 1.1.
https://openfontlicense.org

The font files are embedded unmodified; they are not sold or distributed standalone.

## Sedan-sports model (assets/car/sedan-sports.glb + Textures/colormap.png)
From "SRCoder's Simple Car" by Steve Rodkiss (SRCoder).
Licensed under CC0 1.0 Universal (public domain).
https://godotengine.org/asset-library/asset/3610

The model is used unmodified except for the colormap: the two palette tiles
used exclusively by the body paint were recolored gray -> green (v0.3.0).
Wheel roll/steer animation is applied at runtime through VehicleWheel3D.

## SRCoder's Simple Car scripts (addons/srcoder_simplecar/assets/scripts/)
"car.gd" and "follow_camera.gd" by Steve Rodkiss (SRCoder), kept as the
reference implementation of the adopted vehicle architecture.
Licensed under CC0 1.0 Universal (public domain).
https://godotengine.org/asset-library/asset/3610

## Event Audio addon (addons/event_audio/)
"Event Audio for Godot" by Simon Carter (bbbscarter), version 1.0.1.
Licensed under the MIT License.
https://github.com/bbbscarter/event-audio-godot

Vendored unmodified (runtime files only; the example/ folder and the C#
helper are not included). Used as an autoload; the game registers a
runtime-built EAEventBank and plays all discrete SFX through trigger tags.

## GodotCardManager (addons/godot_card_manager/)
"GodotCardManager" by Jack Linhart.
Licensed under the MIT License (see addons/godot_card_manager/LICENSE).
https://github.com/JackLinhart/GodotCardManager

Vendored with minimal Godot 4 compatibility fixes (documented in the file
header): class_name added, sort_custom Callable form, dictionary key
"FACE-UP" in flipCard/setRevealed, fieldExists boolean logic.

## Godot Road Generator (addons/road-generator/)
"Godot Road Generator" by Moo-Ack! Productions (TheDuckCow), version 0.9.5.
Licensed under the MIT License (see addons/road-generator/LICENSE).
https://github.com/TheDuckCow/godot-road-generator

Vendored unmodified. Since v0.4.0 the asphalt ribbon of the touge circuit is
built at runtime from a closed RoadManager > RoadContainer > RoadPoint chain
laid on the game's analytic centerline: trimsheet lane markings, banked
cross-sections, underside slabs and automated trimesh collision come from
the addon's procedural geometry.

## Starter Kit Racing (assets/skr/)
"Starter Kit Racing" by Kenney.
Licensed under the MIT License (Copyright (c) 2023 Kenney).
https://godotengine.org/asset-library/asset/2702

Used since v0.4.0:
  - audio/engine.ogg + audio/skid.ogg: continuous engine and tire loops
    (loop flag applied at runtime), audio/impact.ogg: collision one-shot
    routed through EventAudio.
  - sprites/smoke.png: tire-smoke particles at the rear wheels.
  - models/Library mesh library: the GridMap-built start/finish paddock
    (track slabs, corner, tents, forest decoration cells).
  - models/vehicle-truck-green.glb + vehicle-truck-red.glb: parked paddock
    props.
The kit's arcade-style eased input handling (vehicle.gd) is mirrored in
scripts/car.gd (lerped throttle/steer targets).

## 3D Car With Settingspanel (assets/car3d/ + scripts/settings_panel.gd)
"3D Car With Settingspanel" (3d_car_customizable).
Licensed under CC0 1.0 Universal (public domain dedication).
https://godotengine.org/asset-library/asset/3815

Used since v0.4.0:
  - assets/car3d/car_model.glb: the player car model (body tinted green;
    the importer-generated VehicleWheel3D nodes are adopted directly).
  - The SettingsPanel tuning + preset system (scripts/settings.gd and
    wheelsettings.gd, Godot 3) was ported to Godot 4 as
    scripts/settings_panel.gd with an Arabic UI: engine/brake/steering
    variables, per-wheel tuning with binding, and JSON presets saved to
    user://3d_car_customizable/ — same schema as the original, first preset
    auto-loads on launch. Preset persistence helpers live in
    scripts/car.gd (list/save/load/delete/apply).

## Morning sky panorama (assets/env/kiara_morning.jpg)
"kiara_3_morning" Equirectangular HDR/panorama by Poly Haven (formerly
HDRI Haven), downscaled LDR JPG copy.
Licensed under CC0 1.0 Universal (public domain dedication).
https://polyhaven.com/a/kiara_3_morning

Used since v0.6.0 as the WorldEnvironment PanoramaSkyMaterial. The file was
borrowed from the reference project github.com/Firet/3d-racing-game (the
project itself is GPLv3; only this CC0 texture asset is used, no GPL code).
All other v0.6.0 scenery (mountains, trees, rocks) is generated
procedurally at runtime by scripts/track_gen.gd and is original.
