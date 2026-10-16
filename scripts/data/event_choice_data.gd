class_name EventChoiceData
extends Resource
## One choice of an event (DESIGN.md 8.7). Taking it pays and gives its deal (a ZoneOfferData:
## gold, HP, heal, XP, team gauge, an item or a find). With risk_percent, that often the risk_deal
## happens too (seeded by the run, so it is the same on every machine).

@export var text: String = ""
@export_multiline var detail: String = ""
@export var deal: ZoneOfferData
@export_range(0, 100, 1, "suffix:%") var risk_percent: int = 0
@export var risk_deal: ZoneOfferData
## What the scene says after the choice (and after the risk struck).
@export_multiline var done_text: String = ""
@export_multiline var risk_text: String = ""
