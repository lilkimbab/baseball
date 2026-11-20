class_name Air
extends RefCounted
## Air density from the weather and the park's elevation (A. Nathan's trajectory calculator,
## baseball.physics.illinois.edu, after the standard barometric and vapour-pressure
## formulas). Thinner air (warm, humid, high) carries the ball farther: a hundred-mph fly
## goes about 5 % farther at Denver's elevation than at sea level.

## Pressure falls with elevation as exp(-BETA * metres).
const BETA := 1.217e-4
const SEA_LEVEL_MMHG := 760.0


## Density in kg/m^3 for a temperature (C), elevation (m), relative humidity (%) and
## barometric pressure at sea level (mm Hg).
static func density(temp_c: float, elevation_m: float = 0.0, humidity_pct: float = 50.0, pressure_mmhg: float = SEA_LEVEL_MMHG) -> float:
	var vapour := saturation_vapour_pressure(temp_c) * humidity_pct / 100.0
	var pressure := pressure_mmhg * exp(-BETA * elevation_m)
	return 1.2929 * (273.0 / (temp_c + 273.0)) * (pressure - 0.3783 * vapour) / SEA_LEVEL_MMHG


## Saturation vapour pressure of water (mm Hg) at a temperature (C).
static func saturation_vapour_pressure(temp_c: float) -> float:
	return 4.5841 * exp((18.687 - temp_c / 234.5) * temp_c / (257.14 + temp_c))


## A copy of the physics with the air of this day and park.
static func config_for(base: PhysicsConfig, temp_c: float, elevation_m: float = 0.0, humidity_pct: float = 50.0) -> PhysicsConfig:
	var cfg := base.duplicate_config()
	cfg.air_density = density(temp_c, elevation_m, humidity_pct)
	cfg.finalize()
	return cfg
