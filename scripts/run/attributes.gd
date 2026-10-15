class_name Attributes
extends RefCounted
## The five attributes a hero spends level-up points on (DESIGN.md 8.2), like Expedition 33. Each
## raises one stat by a tuned amount per point (tuning "Attributes and critical hits").

enum Kind { VITALITY, MIGHT, AGILITY, DEFENSE, LUCK }

const COUNT: int = 5
const NAMES: Array[String] = ["Vitality", "Might", "Agility", "Defense", "Luck"]
## The stat each attribute raises, as the attributes screen names it.
const STATS: Array[String] = ["Health", "Attack Power", "Speed", "Defense", "Critical Rate"]


## A fresh allocation: no points anywhere.
static func empty() -> Array[int]:
	var values: Array[int] = []
	values.resize(COUNT)
	values.fill(0)
	return values


## Points spent in an allocation.
static func total(values: Array) -> int:
	var sum := 0
	for v: Variant in values:
		sum += int(v)
	return sum


## True if `values` is a usable allocation: COUNT whole numbers, none below 0.
static func is_valid(values: Variant) -> bool:
	if not values is Array or (values as Array).size() != COUNT:
		return false
	for v: Variant in values:
		if typeof(v) != TYPE_INT or int(v) < 0:
			return false
	return true


## What one point of `kind` gives, for the screen ("+3% max HP").
static func per_point_text(kind: int, tuning: Tuning) -> String:
	match kind:
		Kind.VITALITY:
			return "+%d%% max HP" % tuning.attr_vitality_hp_percent
		Kind.MIGHT:
			return "+%d%% damage" % tuning.attr_might_power_percent
		Kind.AGILITY:
			return "+%d speed" % tuning.attr_agility_speed
		Kind.DEFENSE:
			return "+%d%% less hurt" % tuning.attr_defense_percent
		Kind.LUCK:
			return "+%d%% critical rate" % tuning.attr_luck_crit_percent
	return ""
