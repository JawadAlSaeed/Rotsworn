class_name SkillTreeData
extends Resource
## A hero's skill tree (DESIGN.md 8.4, card #136): branches side by side, each a line of skills
## from the top down. The first skill of every branch is known from the start of a run; each next
## one costs tuning.skill_tier_costs[its place] skill points and needs the one above it. Before a
## fight the player picks which known skills to bring (tuning.skill_slots).

@export var branches: Array[SkillBranchData] = []


## Every skill in the tree, branch by branch, top down.
func all_skills() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	for branch: SkillBranchData in branches:
		if branch == null:
			continue
		for skill: AbilityData in branch.skills:
			if skill != null:
				list.append(skill)
	return list


## The skills known at the start of a run (the top of each branch).
func starters() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	for branch: SkillBranchData in branches:
		if branch != null and not branch.skills.is_empty() and branch.skills[0] != null:
			list.append(branch.skills[0])
	return list


## Where a skill sits: Vector2i(branch, tier), or (-1, -1) if it is not in this tree.
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
