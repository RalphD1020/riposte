class_name ImpactPresentationProfile
extends RefCounted

## Shared semantic profile for one contact class. Defines the game's feedback
## language: every contact type has one profile that sets the baseline shake,
## hitstop, particles, and audio category. WeaponPresentationKit may override
## cosmetic aspects (audio family, spark look) but MUST NOT redefine semantics.
##
## See also: /docs/architecture/presentation-feedback.md

var shake_profile: CameraShakeRequest.Profile = CameraShakeRequest.Profile.BODY
## Shake intensity = severity × scale.
var shake_scale: float = 50.0
## Hitstop band selector: which kit band to use.
var hitstop_band: HitstopBand = HitstopBand.BLADE
var spark_count_min: int = 3
var spark_count_max: int = 12
var spark_speed_min: float = 1.8
var spark_speed_max: float = 4.5
var audio_category: StringName = &""  ## Reserved: per-contact-class audio routing for WeaponPresentationKit overrides.


enum HitstopBand { BLADE, BODY, DEVASTATING }


## Blade↔blade clash: short, high-frequency, metallic.
static func clash() -> ImpactPresentationProfile:
	var p := ImpactPresentationProfile.new()
	p.shake_profile = CameraShakeRequest.Profile.BLADE
	p.shake_scale = 25.0
	p.hitstop_band = HitstopBand.BLADE
	p.spark_count_min = 3
	p.spark_count_max = 12
	p.spark_speed_min = 1.8
	p.spark_speed_max = 4.5
	return p


## Slash body hit: lower-frequency, heavier, directional.
static func slash() -> ImpactPresentationProfile:
	var p := ImpactPresentationProfile.new()
	p.shake_profile = CameraShakeRequest.Profile.BODY
	p.shake_scale = 50.0
	p.hitstop_band = HitstopBand.BODY
	p.spark_count_min = 3
	p.spark_count_max = 8
	p.spark_speed_min = 1.5
	p.spark_speed_max = 3.0
	return p


## Poke: narrow directional jab.
static func poke() -> ImpactPresentationProfile:
	var p := ImpactPresentationProfile.new()
	p.shake_profile = CameraShakeRequest.Profile.POKE
	p.shake_scale = 35.0
	p.hitstop_band = HitstopBand.BODY
	p.spark_count_min = 2
	p.spark_count_max = 5
	p.spark_speed_min = 1.2
	p.spark_speed_max = 2.5
	return p


## Thrust: strong forward-axis impact.
static func thrust() -> ImpactPresentationProfile:
	var p := ImpactPresentationProfile.new()
	p.shake_profile = CameraShakeRequest.Profile.THRUST
	p.shake_scale = 60.0
	p.hitstop_band = HitstopBand.BODY
	p.spark_count_min = 3
	p.spark_count_max = 7
	p.spark_speed_min = 1.5
	p.spark_speed_max = 3.5
	return p


## Graze: minimal everything.
static func graze() -> ImpactPresentationProfile:
	var p := ImpactPresentationProfile.new()
	p.shake_profile = CameraShakeRequest.Profile.BODY
	p.shake_scale = 10.0
	p.hitstop_band = HitstopBand.BODY
	p.spark_count_min = 1
	p.spark_count_max = 3
	p.spark_speed_min = 1.0
	p.spark_speed_max = 2.0
	return p


## Kill: override to 100, devastating band.
static func kill() -> ImpactPresentationProfile:
	var p := ImpactPresentationProfile.new()
	p.shake_profile = CameraShakeRequest.Profile.KILL
	p.shake_scale = 100.0
	p.hitstop_band = HitstopBand.DEVASTATING
	p.spark_count_min = 8
	p.spark_count_max = 16
	p.spark_speed_min = 2.5
	p.spark_speed_max = 5.0
	return p
