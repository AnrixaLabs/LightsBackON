extends RefCounted
## Interactable selection (blueprint p.8): a center ray of ray_length_cm plus a small aim-assist cone.
## Pure geometry so the host can re-run it to validate a client's claimed target. Distances are in meters
## (engine units, 1 unit = 1 m); tuning comes from content/interaction.json.
##
## Rule: among candidates within reach, a candidate the center ray actually hits (ray passes within its radius)
## wins; otherwise the candidate with the smallest angle inside the assist cone. Ties go to the nearer one, then
## the lower ID, so the result never depends on candidate order.


## candidates: Array of {"id": String, "position": Vector3, "radius": float}. Returns the selected id or "".
static func select(origin: Vector3, forward: Vector3, candidates: Array, ray_length_m: float, cone_deg: float) -> String:
	var dir: Vector3 = forward.normalized()
	var best_id: String = ""
	var best_key: Array = []
	for c: Dictionary in candidates:
		var to: Vector3 = (c["position"] as Vector3) - origin
		var along: float = to.dot(dir)
		var radius: float = c.get("radius", 0.0)
		if along <= 0.0 or to.length() - radius > ray_length_m:
			continue
		var miss: float = (to - dir * along).length()  # distance from the ray to the candidate center
		# a hit counts only if the ray enters the candidate's sphere before its end point (finite 2.3 m ray)
		var hit: bool = miss <= radius and along - sqrt(radius * radius - miss * miss) <= ray_length_m
		var angle: float = rad_to_deg(dir.angle_to(to))
		if not hit and angle > cone_deg:
			continue
		# lower key wins: ray hits before cone matches, then smaller angle, then nearer, then ID
		var key: Array = [0 if hit else 1, 0.0 if hit else angle, along, str(c["id"])]
		if best_key.is_empty() or _less(key, best_key):
			best_key = key
			best_id = str(c["id"])
	return best_id


static func _less(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
