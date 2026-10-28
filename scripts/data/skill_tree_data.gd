class_name SkillTreeData
extends Resource
## A hero's skill tree (DESIGN.md 8.4, card #136): branches side by side, each a line of skills
## from the top down. The first skill of every branch is known from the start of a run; each next
## one costs tuning.skill_tier_costs[its place] skill points and needs the one above it. Before a
## fight the player picks which known skills to bring (tuning.skill_slots).
## `start_skills` sit outside the branches: known from the start of a run and free (card #338,
## DESIGN.md 8.25: each hero starts with one 3-AP skill so early turns have a big spend).

@export var branches: Array[SkillBranchData] = []
## Skills known from the start of a run that belong to no branch (nothing above or below them).
@export var start_skills: Array[AbilityData] = []
## The head of the start skills' column on the Skills tab.
@export var start_name: String = "Signature"


## Every skill in the tree, branch by branch, top down, then the start skills.
func all_skills() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	for branch: SkillBranchData in branches:
		if branch == null:
			continue
		for skill: AbilityData in branch.skills:
			if skill != null:
				list.append(skill)
	for skill: AbilityData in start_skills:
		if skill != null and not list.has(skill):
			list.append(skill)
	return list


## The skills known at the start of a run: the top of each branch, then the start skills.
func starters() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	for branch: SkillBranchData in branches:
		if branch != null and not branch.skills.is_empty() and branch.skills[0] != null:
			list.append(branch.skills[0])
	for skill: AbilityData in start_skills:
		if skill != null and not list.has(skill):
			list.append(skill)
	return list


## True if `ability_id` is one of the start skills (outside the branches).
func is_start_skill(ability_id: String) -> bool:
	for skill: AbilityData in start_skills:
		if skill != null and skill.id == ability_id:
			return true
	return false


## True if `ability_id` is anywhere in the tree (a branch or the start skills).
func has_skill(ability_id: String) -> bool:
	return find(ability_id) != null


## The skill with this id in the tree (null if it is not there).
func find(ability_id: String) -> AbilityData:
	for skill: AbilityData in all_skills():
		if skill.id == ability_id:
			return skill
	return null


## Where a skill sits in the branches: Vector2i(branch, tier), or (-1, -1) if it is in no branch
## (a start skill, or a skill not in the tree).
func place_of(ability_id: String) -> Vector2i:
	for b: int in branches.size():
		if branches[b] == null:
			continue
		for t: int in branches[b].skills.size():
			var skill := branches[b].skills[t]
			if skill != null and skill.id == ability_id:
				return Vector2i(b, t)
	return Vector2i(-1, -1)


## The skill one above `ability_id` in its branch (null for a starter or a skill not in the tree).
func parent_of(ability_id: String) -> AbilityData:
	var at := place_of(ability_id)
	if at.y <= 0:
		return null
	return branches[at.x].skills[at.y - 1]
