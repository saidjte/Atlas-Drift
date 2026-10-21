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
