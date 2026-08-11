extends RefCounted
class_name CupCollisionModel

const EPSILON := 0.0001

const CLASS_OUTSIDE := 0
const CLASS_SIDE_WALL := 1
const CLASS_INSIDE_VOLUME := 2
const CLASS_TOP_INNER := 3
const CLASS_TOP_RIM_BAND := 4
const CLASS_BOTTOM_CAP := 5

const EVENT_NONE := 0
const EVENT_SCORE_CAPTURE := 1
const EVENT_RIM_CONTACT := 2
const EVENT_SIDE_CONTACT := 3


static func build_parameters(config: Dictionary) -> Dictionary:
	var bottom_y := float(config.get("bottom_y", 0.006))
	var rim_y := float(config.get("rim_y", 0.058))
	if rim_y <= bottom_y + EPSILON:
		rim_y = bottom_y + EPSILON

	return {
		"bottom_y": bottom_y,
		"rim_y": rim_y,
		"bottom_radius": maxf(float(config.get("bottom_radius", 0.030)), EPSILON),
		"rim_radius": maxf(float(config.get("rim_radius", 0.046)), EPSILON),
		"inner_score_radius": maxf(float(config.get("inner_score_radius", 0.036)), 0.0),
		"rim_tube_radius": maxf(float(config.get("rim_tube_radius", 0.012)), 0.0),
		"rim_band_ball_radius_scale": maxf(float(config.get("rim_band_ball_radius_scale", 0.6)), 0.0),
		"min_score_downward_speed": maxf(float(config.get("min_score_downward_speed", 0.15)), 0.0),
		"rim_top_radial_normal_scale": maxf(float(config.get("rim_top_radial_normal_scale", 0.38)), 0.0),
		"rim_top_upward_normal_scale": maxf(float(config.get("rim_top_upward_normal_scale", 0.92)), 0.0),
		"non_score_clearance": maxf(float(config.get("non_score_clearance", 0.012)), 0.0),
	}


static func evaluate_ball_motion(
	previous_local_position: Vector3,
	current_local_position: Vector3,
	local_velocity: Vector3,
	ball_radius: float,
	parameters: Dictionary
) -> Dictionary:
	var safe_radius := maxf(ball_radius, 0.0)
	var snapshot := classify_local_sphere(current_local_position, safe_radius, parameters)
	var result := snapshot.duplicate()
	result["event"] = EVENT_NONE
	result["event_name"] = get_event_name(EVENT_NONE)
	result["event_local_position"] = current_local_position
	result["capture_local_position"] = current_local_position
	result["event_normal_local"] = Vector3.ZERO
	result["reference_signed_distance"] = 0.0
	result["score_crossing_radius"] = get_score_crossing_radius(safe_radius, parameters)

	var top_event := evaluate_top_crossing(
		previous_local_position,
		current_local_position,
		local_velocity,
		safe_radius,
		parameters
	)
	if not top_event.is_empty():
		_apply_event_result(result, top_event)
		return result

	var side_event := evaluate_side_contact(
		previous_local_position,
		current_local_position,
		local_velocity,
		safe_radius,
		parameters
	)
	if not side_event.is_empty():
		_apply_event_result(result, side_event)
		return result

	var current_capture := evaluate_current_score_capture(current_local_position, safe_radius, parameters)
	if not current_capture.is_empty():
		_apply_event_result(result, current_capture)

	return result


static func classify_local_sphere(local_position: Vector3, ball_radius: float, parameters: Dictionary) -> Dictionary:
	var safe_radius := maxf(ball_radius, 0.0)
	var radial_distance := Vector2(local_position.x, local_position.z).length()
	var cross_section_point := Vector2(radial_distance, local_position.y)
	var inside := is_cross_section_point_inside_frustum(cross_section_point, parameters)
	var normal_snapshot := calculate_local_nearest_surface_snapshot(local_position, parameters)
	var closest_feature := StringName(str(normal_snapshot.get("closest_feature", &"inside")))
	var distance := float(normal_snapshot.get("distance_to_surface", 0.0))
	var intersects := inside or distance * distance <= safe_radius * safe_radius + EPSILON

	var rim_radius := get_rim_radius(parameters)
	var rim_y := get_rim_y(parameters)
	var rim_band_width := get_rim_band_width(safe_radius, parameters)
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
		if inside:
			classification = CLASS_INSIDE_VOLUME
		elif closest_feature == &"bottom_cap":
			classification = CLASS_BOTTOM_CAP
		else:
			classification = CLASS_SIDE_WALL

	return {
		"classification": classification,
		"classification_name": get_classification_name(classification),
		"intersects": intersects,
		"inside": inside,
		"top_plane_overlap": top_plane_overlap,
		"rim_band_overlap": rim_band_overlap,
		"top_inner_overlap": top_inner_overlap,
		"rim_band_width": rim_band_width,
		"rim_band_inner_radius": rim_band_inner_radius,
		"rim_band_outer_radius": rim_band_outer_radius,
		"projected_min_radius": projected_min_radius,
		"projected_max_radius": projected_max_radius,
		"ball_radius": safe_radius,
		"ball_local_position": local_position,
		"radial_distance": radial_distance,
		"closest_feature": closest_feature,
		"nearest_local_point": normal_snapshot.get("nearest_local_point", Vector3.ZERO),
		"normal_local": normal_snapshot.get("normal_local", Vector3.UP),
		"signed_center_distance": normal_snapshot.get("signed_center_distance", 0.0),
		"distance_to_frustum": distance,
		"clearance": distance - safe_radius,
	}


static func evaluate_top_crossing(
	previous_local_position: Vector3,
	current_local_position: Vector3,
	local_velocity: Vector3,
	ball_radius: float,
	parameters: Dictionary
) -> Dictionary:
	var rim_y := get_rim_y(parameters)
	if previous_local_position.y <= rim_y or current_local_position.y > rim_y:
		return {}
	if local_velocity.y > -get_min_score_downward_speed(parameters):
		return {}

	var crossing_local := get_y_crossing(previous_local_position, current_local_position, rim_y)
	var crossing_radius := Vector2(crossing_local.x, crossing_local.z).length()
	var rim_radius := get_rim_radius(parameters)
	var rim_band := get_rim_band_width(ball_radius, parameters)
	if absf(crossing_radius - rim_radius) <= rim_band:
		return {
			"event": EVENT_RIM_CONTACT,
			"event_name": get_event_name(EVENT_RIM_CONTACT),
			"event_local_position": crossing_local,
			"event_normal_local": get_flat_top_rim_normal(crossing_local, parameters),
			"classification": CLASS_TOP_RIM_BAND,
			"classification_name": get_classification_name(CLASS_TOP_RIM_BAND),
		}

	if crossing_radius <= get_score_crossing_radius(ball_radius, parameters):
		return {
			"event": EVENT_SCORE_CAPTURE,
			"event_name": get_event_name(EVENT_SCORE_CAPTURE),
			"event_local_position": crossing_local,
			"capture_local_position": current_local_position,
			"event_normal_local": Vector3.DOWN,
			"classification": CLASS_TOP_INNER,
			"classification_name": get_classification_name(CLASS_TOP_INNER),
		}

	return {}


static func evaluate_current_score_capture(
	current_local_position: Vector3,
	ball_radius: float,
	parameters: Dictionary
) -> Dictionary:
	if current_local_position.y > get_rim_y(parameters):
		return {}

	var horizontal_radius := Vector2(current_local_position.x, current_local_position.z).length()
	if horizontal_radius > get_score_crossing_radius(ball_radius, parameters):
		return {}

	return {
		"event": EVENT_SCORE_CAPTURE,
		"event_name": get_event_name(EVENT_SCORE_CAPTURE),
		"event_local_position": current_local_position,
		"capture_local_position": current_local_position,
		"event_normal_local": Vector3.DOWN,
	}


static func evaluate_side_contact(
	previous_local_position: Vector3,
	current_local_position: Vector3,
	local_velocity: Vector3,
	ball_radius: float,
	parameters: Dictionary
) -> Dictionary:
	var bottom_y := get_bottom_y(parameters)
	var rim_y := get_rim_y(parameters)
	if current_local_position.y < bottom_y - ball_radius or current_local_position.y > rim_y + ball_radius:
		return {}

	var current_radial := Vector2(current_local_position.x, current_local_position.z).length()
	if current_radial <= EPSILON:
		return {}

	var current_signed_distance := get_side_signed_distance(current_local_position, parameters)
	var previous_signed_distance := get_side_signed_distance(previous_local_position, parameters)
	var near_wall := absf(current_signed_distance) <= ball_radius
	var crossed_side_surface := (
		previous_signed_distance > EPSILON and current_signed_distance <= EPSILON
	) or (
		previous_signed_distance < -EPSILON and current_signed_distance >= -EPSILON
	)
	var crossed_wall := (
		previous_signed_distance > ball_radius and current_signed_distance < -ball_radius
	) or (
		previous_signed_distance < -ball_radius and current_signed_distance > ball_radius
	)
	if not near_wall and not crossed_wall and not crossed_side_surface:
		return {}

	var reference_signed_distance := previous_signed_distance if crossed_wall or crossed_side_surface else current_signed_distance
	var contact_center_local_position := get_side_contact_sample_position(
		previous_local_position,
		current_local_position,
		previous_signed_distance,
		current_signed_distance,
		ball_radius,
		parameters
	)
	var side_normal_local := get_side_outward_normal(contact_center_local_position, parameters)
	var collision_normal_local := side_normal_local if reference_signed_distance >= 0.0 else -side_normal_local
	if local_velocity.dot(collision_normal_local) >= -0.01:
		if crossed_wall and local_velocity.dot(-collision_normal_local) < -0.01:
			collision_normal_local = -collision_normal_local
		else:
			return {}

	var contact_surface_local_position := get_side_surface_position(contact_center_local_position, parameters)
	var clear_local_position := get_side_clear_position(
		contact_center_local_position,
		collision_normal_local,
		ball_radius,
		parameters
	)

	return {
		"event": EVENT_SIDE_CONTACT,
		"event_name": get_event_name(EVENT_SIDE_CONTACT),
		"event_local_position": contact_surface_local_position,
		"contact_center_local_position": contact_center_local_position,
		"clear_local_position": clear_local_position,
		"event_normal_local": collision_normal_local,
		"reference_signed_distance": reference_signed_distance,
		"current_signed_distance": current_signed_distance,
		"previous_signed_distance": previous_signed_distance,
		"classification": CLASS_SIDE_WALL,
		"classification_name": get_classification_name(CLASS_SIDE_WALL),
	}


static func get_side_contact_sample_position(
	previous_local_position: Vector3,
	current_local_position: Vector3,
	previous_signed_distance: float,
	current_signed_distance: float,
	ball_radius: float,
	parameters: Dictionary
) -> Vector3:
	var target_signed_distance := current_signed_distance
	if previous_signed_distance > ball_radius and current_signed_distance <= ball_radius:
		target_signed_distance = ball_radius
	elif previous_signed_distance < -ball_radius and current_signed_distance >= -ball_radius:
		target_signed_distance = -ball_radius
	elif previous_signed_distance > EPSILON and current_signed_distance <= EPSILON:
		target_signed_distance = 0.0
	elif previous_signed_distance < -EPSILON and current_signed_distance >= -EPSILON:
		target_signed_distance = 0.0
	else:
		return current_local_position

	var signed_delta := current_signed_distance - previous_signed_distance
	if absf(signed_delta) <= EPSILON:
		return current_local_position

	var ratio := clampf((target_signed_distance - previous_signed_distance) / signed_delta, 0.0, 1.0)
	var contact_local := previous_local_position.lerp(current_local_position, ratio)
	contact_local.y = clampf(contact_local.y, get_bottom_y(parameters), get_rim_y(parameters))
	return contact_local


static func get_side_surface_position(local_position: Vector3, parameters: Dictionary) -> Vector3:
	var radial := Vector2(local_position.x, local_position.z)
	var radial_length := radial.length()
	if radial_length <= EPSILON:
		return local_position

	var y := clampf(local_position.y, get_bottom_y(parameters), get_rim_y(parameters))
	var radial_direction := radial / radial_length
	var wall_radius := get_radius_at_y(y, parameters)
	return Vector3(radial_direction.x * wall_radius, y, radial_direction.y * wall_radius)


static func get_side_clear_position(
	local_position: Vector3,
	normal_local: Vector3,
	ball_radius: float,
	parameters: Dictionary
) -> Vector3:
	if normal_local.length_squared() <= EPSILON:
		return local_position

	var surface_local := get_side_surface_position(local_position, parameters)
	return surface_local + normal_local.normalized() * (maxf(ball_radius, 0.0) + get_non_score_clearance(parameters))


static func calculate_local_nearest_surface_snapshot(local_position: Vector3, parameters: Dictionary) -> Dictionary:
	var radial := Vector2(local_position.x, local_position.z)
	var radial_distance := radial.length()
	var radial_direction := Vector2(1.0, 0.0) if radial_distance <= EPSILON else radial / radial_distance
	var cross_section_point := Vector2(radial_distance, local_position.y)
	var closest := get_closest_cross_section_point(cross_section_point, parameters)
	var nearest_cross_section_point: Vector2 = closest.get("point", cross_section_point)
	var nearest_local_point := Vector3(
		radial_direction.x * nearest_cross_section_point.x,
		nearest_cross_section_point.y,
		radial_direction.y * nearest_cross_section_point.x
	)
	var to_ball := local_position - nearest_local_point
	var distance := to_ball.length()
	var closest_feature := StringName(str(closest.get("feature", &"inside")))
	var normal_local := to_ball / distance if distance > EPSILON else get_fallback_normal_for_feature(
		closest_feature,
		nearest_local_point,
		radial_direction,
		parameters
	)
	var inside := is_cross_section_point_inside_frustum(cross_section_point, parameters)

	return {
		"nearest_local_point": nearest_local_point,
		"nearest_cross_section_point": nearest_cross_section_point,
		"normal_local": normal_local,
		"distance_to_surface": distance,
		"signed_center_distance": -distance if inside else distance,
		"closest_feature": closest_feature,
		"inside": inside,
	}


static func get_radius_at_y(local_y: float, parameters: Dictionary) -> float:
	var bottom_y := get_bottom_y(parameters)
	var height := get_height(parameters)
	var y_ratio := clampf((local_y - bottom_y) / height, 0.0, 1.0)
	return lerpf(get_bottom_radius(parameters), get_rim_radius(parameters), y_ratio)


static func get_side_signed_distance(local_position: Vector3, parameters: Dictionary) -> float:
	var y := clampf(local_position.y, get_bottom_y(parameters), get_rim_y(parameters))
	var radial := Vector2(local_position.x, local_position.z).length()
	return radial - get_radius_at_y(y, parameters)


static func get_side_outward_normal(local_position: Vector3, parameters: Dictionary) -> Vector3:
	var radial := Vector2(local_position.x, local_position.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var slope := (get_rim_radius(parameters) - get_bottom_radius(parameters)) / get_height(parameters)
	var radial_direction := radial.normalized()
	return Vector3(radial_direction.x, -slope, radial_direction.y).normalized()


static func get_score_crossing_radius(ball_radius: float, parameters: Dictionary) -> float:
	var rim_inner_limit := get_rim_radius(parameters) - get_rim_band_width(ball_radius, parameters)
	return maxf(0.0, minf(get_inner_score_radius(parameters), rim_inner_limit))


static func get_rim_band_width(ball_radius: float, parameters: Dictionary) -> float:
	return maxf(get_rim_tube_radius(parameters), maxf(ball_radius, 0.0) * get_rim_band_ball_radius_scale(parameters))


static func get_y_crossing(previous_local_position: Vector3, current_local_position: Vector3, y_value: float) -> Vector3:
	var delta_y := current_local_position.y - previous_local_position.y
	if absf(delta_y) <= EPSILON:
		return current_local_position

	var ratio := clampf((y_value - previous_local_position.y) / delta_y, 0.0, 1.0)
	return previous_local_position.lerp(current_local_position, ratio)


static func get_closest_cross_section_point(point: Vector2, parameters: Dictionary) -> Dictionary:
	var bottom_y := get_bottom_y(parameters)
	var rim_y := get_rim_y(parameters)
	var bottom_radius := get_bottom_radius(parameters)
	var rim_radius := get_rim_radius(parameters)
	var bottom_point := get_closest_point_on_segment_2d(point, Vector2(0.0, bottom_y), Vector2(bottom_radius, bottom_y))
	var top_point := get_closest_point_on_segment_2d(point, Vector2(0.0, rim_y), Vector2(rim_radius, rim_y))
	var side_point := get_closest_point_on_segment_2d(point, Vector2(bottom_radius, bottom_y), Vector2(rim_radius, rim_y))
	var best_point := bottom_point
	var best_feature := &"bottom_cap"
	var best_distance_squared := point.distance_squared_to(bottom_point)
	var top_distance_squared := point.distance_squared_to(top_point)
	if top_distance_squared < best_distance_squared:
		best_point = top_point
		best_feature = &"top_cap"
		best_distance_squared = top_distance_squared

	var side_distance_squared := point.distance_squared_to(side_point)
	if side_distance_squared < best_distance_squared:
		best_point = side_point
		best_feature = &"side_wall"

	return {
		"point": best_point,
		"feature": best_feature,
	}


static func get_closest_point_on_segment_2d(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> Vector2:
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= EPSILON:
		return segment_start

	var amount := clampf((point - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return segment_start + segment * amount


static func is_cross_section_point_inside_frustum(point: Vector2, parameters: Dictionary) -> bool:
	if point.y < get_bottom_y(parameters) or point.y > get_rim_y(parameters):
		return false
	return point.x <= get_radius_at_y(point.y, parameters)


static func get_flat_top_rim_normal(sample_local: Vector3, parameters: Dictionary) -> Vector3:
	var torus_normal := get_rim_torus_normal(sample_local, parameters)
	var radial := Vector2(torus_normal.x, torus_normal.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var radial_direction := radial.normalized()
	return Vector3(
		radial_direction.x * get_rim_top_radial_normal_scale(parameters),
		get_rim_top_upward_normal_scale(parameters),
		radial_direction.y * get_rim_top_radial_normal_scale(parameters)
	).normalized()


static func get_rim_torus_normal(sample_local: Vector3, parameters: Dictionary) -> Vector3:
	var radial := Vector2(sample_local.x, sample_local.z)
	if radial.length_squared() <= EPSILON:
		return Vector3.UP

	var radial_direction := radial.normalized()
	var rim_centerline_point := Vector3(
		radial_direction.x * get_rim_radius(parameters),
		get_rim_y(parameters),
		radial_direction.y * get_rim_radius(parameters)
	)
	var normal := sample_local - rim_centerline_point
	if normal.length_squared() <= EPSILON:
		return Vector3(radial_direction.x, 1.0, radial_direction.y).normalized()
	return normal.normalized()


static func get_fallback_normal_for_feature(
	feature: StringName,
	nearest_local_point: Vector3,
	radial_direction: Vector2,
	parameters: Dictionary
) -> Vector3:
	match feature:
		&"side_wall":
			return get_side_outward_normal(nearest_local_point, parameters)
		&"bottom_cap":
			return Vector3.DOWN
		&"top_cap":
			return Vector3.UP

	return Vector3(radial_direction.x, 0.0, radial_direction.y).normalized()


static func get_classification_name(classification: int) -> String:
	match classification:
		CLASS_SIDE_WALL:
			return "side_wall"
		CLASS_INSIDE_VOLUME:
			return "inside_volume"
		CLASS_TOP_INNER:
			return "top_inner"
		CLASS_TOP_RIM_BAND:
			return "top_rim_band"
		CLASS_BOTTOM_CAP:
			return "bottom_cap"
	return "outside"


static func get_event_name(event: int) -> String:
	match event:
		EVENT_SCORE_CAPTURE:
			return "score_capture"
		EVENT_RIM_CONTACT:
			return "rim_contact"
		EVENT_SIDE_CONTACT:
			return "side_contact"
	return "none"


static func get_bottom_y(parameters: Dictionary) -> float:
	return float(parameters.get("bottom_y", 0.006))


static func get_rim_y(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_y", 0.058)), get_bottom_y(parameters) + EPSILON)


static func get_bottom_radius(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("bottom_radius", 0.030)), EPSILON)


static func get_rim_radius(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_radius", 0.046)), EPSILON)


static func get_inner_score_radius(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("inner_score_radius", 0.036)), 0.0)


static func get_rim_tube_radius(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_tube_radius", 0.012)), 0.0)


static func get_rim_band_ball_radius_scale(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_band_ball_radius_scale", 0.6)), 0.0)


static func get_min_score_downward_speed(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("min_score_downward_speed", 0.15)), 0.0)


static func get_rim_top_radial_normal_scale(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_top_radial_normal_scale", 0.38)), 0.0)


static func get_rim_top_upward_normal_scale(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("rim_top_upward_normal_scale", 0.92)), 0.0)


static func get_non_score_clearance(parameters: Dictionary) -> float:
	return maxf(float(parameters.get("non_score_clearance", 0.012)), 0.0)


static func get_height(parameters: Dictionary) -> float:
	return maxf(get_rim_y(parameters) - get_bottom_y(parameters), EPSILON)


static func _apply_event_result(result: Dictionary, event: Dictionary) -> void:
	for key in event.keys():
		result[key] = event[key]
