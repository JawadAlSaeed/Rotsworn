class_name GlossaryData
extends Resource
## The glossary's content (DESIGN.md 7.12): the topics in reading order and every term. Edit
## data/glossary/glossary.tres; tools/bootstrap_glossary.gd wrote the first version.

## Topic ids and their names, in order (the two lists are the same length).
@export var topic_ids: PackedStringArray = PackedStringArray()
@export var topic_names: PackedStringArray = PackedStringArray()
## Every term; the order here is the order in its topic's list.
@export var entries: Array[GlossaryEntry] = []


## The terms of one topic, in order.
func topic_entries(topic_id: String) -> Array[GlossaryEntry]:
	var list: Array[GlossaryEntry] = []
	for entry: GlossaryEntry in entries:
		if entry.topic == topic_id:
			list.append(entry)
	return list


## The term with this id, or null.
func find(entry_id: String) -> GlossaryEntry:
	for entry: GlossaryEntry in entries:
		if entry.id == entry_id:
			return entry
	return null


## Where a topic stands in the order (-1: unknown).
func topic_index(topic_id: String) -> int:
	return topic_ids.find(topic_id)
