extends RefCounted
class_name ThrowMotionSampler

const DEFAULT_MAX_SAMPLES := 6

var _max_samples := DEFAULT_MAX_SAMPLES
var _positions: Array[Vector3] = []
var _deltas: Array[float] = []


func _init(max_samples := DEFAULT_MAX_SAMPLES) -> void:
	_max_samples = max(2, max_samples)


func reset() -> void:
	_positions.clear()
	_deltas.clear()


func sample(global_transform: Transform3D, delta: float) -> void:
	if delta <= 0.0:
		return

	_positions.append(global_transform.origin)
	_deltas.append(delta)

	while _positions.size() > _max_samples:
		_positions.pop_front()
		_deltas.pop_front()


func get_linear_velocity() -> Vector3:
	if _positions.size() < 2:
		return Vector3.ZERO

	var weighted_velocity := Vector3.ZERO
	var total_weight := 0.0

	for index in range(1, _positions.size()):
		var step_delta := _deltas[index]
		if step_delta <= 0.0:
			continue

		var step_velocity := (_positions[index] - _positions[index - 1]) / step_delta
		var weight := float(index)
		weighted_velocity += step_velocity * weight
		total_weight += weight

	if total_weight <= 0.0:
		return Vector3.ZERO

	return weighted_velocity / total_weight
