extends RefCounted
class_name ConicFrustumCollision

const EPSILON := 0.0001

const CLASS_OUTSIDE := "outside"
const CLASS_SIDE_WALL := "side_wall"
const CLASS_INSIDE_VOLUME := "inside_volume"
const CLASS_TOP_INNER := "top_inner"
const CLASS_TOP_RIM_BAND := "top_rim_band"
const CLASS_BOTTOM_CAP := "bottom_cap"

const FEATURE_INSIDE := "inside"
const FEATURE_SIDE_WALL := "side_wall"
const FEATURE_TOP_CAP := "top_cap"
const FEATURE_BOTTOM_CAP := "bottom_cap"


static func build_parameters(config := {}) -> Dictionary:
	var bottom_y := float(config.get("bottom_y", 0.006))
	var rim_y := float(config.get("rim_y", 0.058))
	if rim_y <= bottom_y + EPSILON:
		rim_y = bottom_y + EPSILON

	return {
		"bottom_y": bottom_y,
		"rim_y": rim_y,
		"bottom_radius": maxf(float(config.get("bottom_radius", 0.030)), EPSILON),
		"rim_radius": maxf(float(config.get("rim_radius", 0.046)), EPSILON),
		"rim_band_ball_radius_scale": maxf(float(config.get("rim_band_ball_radius_scale", 0.6)), 0.0),
	}


static func calculate_world_sphere_frustum_intersection(
	cup_transform: Transform3D,
	ball_world_position: Vector3,
	ball_radius: float,
	parameters: Dictionary
) -> Dictionary:
	var local_position := cup_transform.affine_inverse() * ball_world_position
	return calculate_local_sphere_frustum_intersection(
		local_position,
		ball_radius,
		parameters,
		cup_transform
	)


static func calculate_local_sphere_frustum_intersection(
	local_position: Vector3,
	ball_radius: float,
	parameters: Dictionary,
	cup_transform := Transform3D.IDENTITY
) -> Dictionary:
	var safe_parameters := build_parameters(parameters)
	var safe_radius := maxf(ball_radius, 0.0)
	var radial_distance := Vector2(local_position.x, local_position.z).length()
	var cross_section_point := Vector2(radial_distance, local_position.y)
	var inside := is_cross_section_point_inside_frustum(cross_section_point, safe_parameters)
	var normal_snapshot := calculate_local_nearest_surface_snapshot(
		local_position,
		safe_parameters,
		cup_transform
	)
	var closest_cross_section_point: Vector2 = normal_snapshot.get("nearest_cross_section_point", cross_section_point)
	var closest_feature := str(normal_snapshot.get("closest_feature", FEATURE_INSIDE))
	var distance := float(normal_snapshot.get("distance_to_surface", 0.0))
	var intersects := inside or distance * distance <= safe_radius * safe_radius + EPSILON
	var classification_snapshot := classify_local_sphere_frustum_overlap(
		local_position,
		safe_radius,
		intersects,
		closest_feature,
		safe_parameters
	)

	return {
		"intersects": intersects,
		"inside": inside,
		"classification": classification_snapshot.get("classification", CLASS_OUTSIDE),
		"top_plane_overlap": classification_snapshot.get("top_plane_overlap", false),
		"rim_band_overlap": classification_snapshot.get("rim_band_overlap", false),
		"top_inner_overlap": classification_snapshot.get("top_inner_overlap", false),
		"rim_band_width": classification_snapshot.get("rim_band_width", 0.0),
		"rim_band_inner_radius": classification_snapshot.get("rim_band_inner_radius", 0.0),
		"rim_band_outer_radius": classification_snapshot.get("rim_band_outer_radius", 0.0),
		"projected_min_radius": classification_snapshot.get("projected_min_radius", 0.0),
		"projected_max_radius": classification_snapshot.get("projected_max_radius", 0.0),
		"ball_radius": safe_radius,
		"ball_local_position": local_position,
		"radial_distance": radial_distance,
		"closest_feature": closest_feature,
		"closest_cross_section_point": closest_cross_section_point,
		"nearest_local_point": normal_snapshot.get("nearest_local_point", Vector3.ZERO),
		"nearest_world_point": normal_snapshot.get("nearest_world_point", cup_transform.origin),
		"normal_local": normal_snapshot.get("normal_local", Vector3.UP),
		"normal_world": normal_snapshot.get("normal_world", Vector3.UP),
		"signed_center_distance": normal_snapshot.get("signed_center_distance", 0.0),
		"distance_to_frustum": distance,
		"clearance": distance - safe_radius,
		"parameters": safe_parameters.duplicate(true),
	}


static func classify_local_sphere_frustum_overlap(
	local_position: Vector3,
	ball_radius: float,
	intersects: bool,
	closest_feature: String,
	parameters: Dictionary
) -> Dictionary:
	var safe_parameters := build_parameters(parameters)
	var safe_radius := maxf(ball_radius, 0.0)
	var radial_distance := Vector2(local_position.x, local_position.z).length()
	var rim_radius := get_rim_radius(safe_parameters)
	var rim_y := get_rim_y(safe_parameters)
	var rim_band_width := get_rim_band_width(safe_radius, safe_parameters)
	var rim_band_inner_radius := maxf(0.0, rim_radius - rim_band_width)
	var rim_band_outer_radius := rim_radius + rim_band_width
	var projected_min_radius := maxf(0.0, radial_distance - safe_radius)
	var projected_max_radius := radial_distance + safe_radius
	var top_plane_overlap := absf(local_position.y - rim_y) <= safe_radius + EPSILON
	var rim_band_overlap := (
		top_plane_overlap
		and projected_max_radius >= rim_band_inner_radius - EPSILON
		and projected_min_radius <= rim_band_outer_radius + EPSILON
	)
	var top_inner_overlap := (
		top_plane_overlap
		and not rim_band_overlap
		and projected_max_radius < rim_band_inner_radius - EPSILON
	)
	var classification := CLASS_OUTSIDE

	if rim_band_overlap:
		classification = CLASS_TOP_RIM_BAND
	elif top_inner_overlap:
		classification = CLASS_TOP_INNER
	elif intersects:
		if is_cross_section_point_inside_frustum(Vector2(radial_distance, local_position.y), safe_parameters):
			classification = CLASS_INSIDE_VOLUME
		elif closest_feature == FEATURE_BOTTOM_CAP:
			classification = CLASS_BOTTOM_CAP
		else:
			classification = CLASS_SIDE_WALL

	return {
		"classification": classification,
		"top_plane_overlap": top_plane_overlap,
		"rim_band_overlap": rim_band_overlap,
		"top_inner_overlap": top_inner_overlap,
		"rim_band_width": rim_band_width,
		"rim_band_inner_radius": rim_band_inner_radius,
		"rim_band_outer_radius": rim_band_outer_radius,
		"projected_min_radius": projected_min_radius,
		"projected_max_radius": projected_max_radius,
	}


static func calculate_local_nearest_surface_snapshot(
	local_position: Vector3,
	parameters: Dictionary,
	cup_transform := Transform3D.IDENTITY
) -> Dictionary:
	var safe_parameters := build_parameters(parameters)
	var radial := Vector2(local_position.x, local_position.z)
	var radial_distance := radial.length()
	var radial_direction := Vector2(1.0, 0.0) if radial_distance <= EPSILON else radial / radial_distance
	var cross_section_point := Vector2(radial_distance, local_position.y)
	var closest := get_closest_cross_section_point(cross_section_point, safe_parameters)
	var nearest_cross_section_point: Vector2 = closest.get("point", cross_section_point)
	var nearest_local_point := Vector3(
		radial_direction.x * nearest_cross_section_point.x,
		nearest_cross_section_point.y,
		radial_direction.y * nearest_cross_section_point.x
	)
	var to_ball := local_position - nearest_local_point
	var distance := to_ball.length()
	var closest_feature := str(closest.get("feature", FEATURE_INSIDE))
	var normal_local := to_ball / distance if distance > EPSILON else get_fallback_normal_for_feature(
		closest_feature,
		nearest_local_point,
		radial_direction,
		safe_parameters
	)
	var inside := is_cross_section_point_inside_frustum(cross_section_point, safe_parameters)

	return {
		"nearest_local_point": nearest_local_point,
		"nearest_world_point": cup_transform * nearest_local_point,
		"nearest_cross_section_point": nearest_cross_section_point,
		"normal_local": normal_local,
		"normal_world": to_world_normal(cup_transform, normal_local),
		"distance_to_surface": distance,
		"signed_center_distance": -distance if inside else distance,
		"closest_feature": closest_feature,
		"inside": inside,
	}


static func get_radius_at_y(local_y: float, parameters: Dictionary) -> float:
	var safe_parameters := build_parameters(parameters)
	var y_ratio := clampf(
		(local_y - get_bottom_y(safe_parameters)) / get_height(safe_parameters),
		0.0,
		1.0
	)
	return lerpf(get_bottom_radius(safe_parameters), get_rim_radius(safe_parameters), y_ratio)


static func is_local_point_inside_frustum(local_position: Vector3, parameters: Dictionary) -> bool:
	var safe_parameters := build_parameters(parameters)
	if local_position.y < get_bottom_y(safe_parameters) or local_position.y > get_rim_y(safe_parameters):
		return false

	var horizontal_radius := Vector2(local_position.x, local_position.z).length()
	return horizontal_radius <= get_radius_at_y(local_position.y, safe_parameters)


static func is_cross_section_point_inside_frustum(point: Vector2, parameters: Dictionary) -> bool:
	var safe_parameters := build_parameters(parameters)
	if point.y < get_bottom_y(safe_parameters) or point.y > get_rim_y(safe_parameters):
		return false
	return point.x <= get_radius_at_y(point.y, safe_parameters)


static func get_side_normal_at_local_position(local_position: Vector3, parameters: Dictionary) -> Vector3:
	var radial := Vector2(local_position.x, local_position.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var safe_parameters := build_parameters(parameters)
	var slope := (get_rim_radius(safe_parameters) - get_bottom_radius(safe_parameters)) / get_height(safe_parameters)
	var radial_direction := radial.normalized()
	return Vector3(radial_direction.x, -slope, radial_direction.y).normalized()


static func get_closest_cross_section_point(point: Vector2, parameters: Dictionary) -> Dictionary:
	var safe_parameters := build_parameters(parameters)
	var bottom_y := get_bottom_y(safe_parameters)
	var rim_y := get_rim_y(safe_parameters)
	var bottom_radius := get_bottom_radius(safe_parameters)
	var rim_radius := get_rim_radius(safe_parameters)
	var candidates: Array[Dictionary] = [
		{
			"point": get_closest_point_on_segment_2d(
				point,
				Vector2(0.0, bottom_y),
				Vector2(bottom_radius, bottom_y)
			),
			"feature": FEATURE_BOTTOM_CAP,
		},
		{
			"point": get_closest_point_on_segment_2d(
				point,
				Vector2(0.0, rim_y),
				Vector2(rim_radius, rim_y)
			),
			"feature": FEATURE_TOP_CAP,
		},
		{
			"point": get_closest_point_on_segment_2d(
				point,
				Vector2(bottom_radius, bottom_y),
				Vector2(rim_radius, rim_y)
			),
			"feature": FEATURE_SIDE_WALL,
		},
	]

	var best := candidates[0]
	var best_distance_squared: float = point.distance_squared_to(best["point"] as Vector2)
	for candidate in candidates:
		var candidate_point := candidate["point"] as Vector2
		var distance_squared := point.distance_squared_to(candidate_point)
		if distance_squared < best_distance_squared:
			best = candidate
			best_distance_squared = distance_squared
	return best


static func get_fallback_normal_for_feature(
	feature: String,
	nearest_local_point: Vector3,
	radial_direction: Vector2,
	parameters: Dictionary
) -> Vector3:
	match feature:
		FEATURE_SIDE_WALL:
			return get_side_normal_at_local_position(nearest_local_point, parameters)
		FEATURE_BOTTOM_CAP:
			return Vector3.DOWN
		FEATURE_TOP_CAP:
			return Vector3.UP

	var fallback := Vector3(radial_direction.x, 0.0, radial_direction.y)
	return fallback.normalized() if fallback.length_squared() > EPSILON else Vector3.UP


static func get_closest_point_on_segment_2d(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> Vector2:
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= EPSILON:
		return segment_start

	var amount := clampf((point - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return segment_start + segment * amount


static func get_rim_band_width(ball_radius: float, parameters: Dictionary) -> float:
	return maxf(maxf(ball_radius, 0.0) * get_rim_band_ball_radius_scale(parameters), EPSILON)


static func to_world_normal(cup_transform: Transform3D, local_normal: Vector3) -> Vector3:
	if local_normal.length_squared() <= EPSILON:
		return Vector3.UP
	return (cup_transform.basis * local_normal).normalized()


static func get_bottom_y(parameters: Dictionary) -> float:
	return float(parameters.get("bottom_y", 0.006))


static func get_rim_y(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_y", 0.058)), get_bottom_y(parameters) + EPSILON)


static func get_bottom_radius(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("bottom_radius", 0.030)), EPSILON)


static func get_rim_radius(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_radius", 0.046)), EPSILON)


static func get_rim_band_ball_radius_scale(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_band_ball_radius_scale", 0.6)), 0.0)


static func get_height(parameters: Dictionary) -> float:
	return maxf(get_rim_y(parameters) - get_bottom_y(parameters), EPSILON)
