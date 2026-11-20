class_name ReportIO
extends RefCounted
## Batch reports to and from JSON, so batches run in separate processes can be added up.
## Copies every script variable (not those starting with "_") of the report and of the lines
## and tallies inside it.


static func save(report: BatchReport, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(to_dict(report)))


static func load_report(path: String) -> BatchReport:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var report := BatchReport.new()
	if data is Dictionary:
		fill(report, data)
	return report


static func to_dict(o: Object) -> Dictionary:
	var d := {}
	for prop: Dictionary in o.get_property_list():
		var name: String = prop["name"]
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or name.begins_with("_"):
			continue
		var v: Variant = o.get(name)
		if v is Object:
			d[name] = to_dict(v)
		elif v is PackedInt32Array or v is PackedFloat64Array:
			d[name] = Array(v)
		elif v is Dictionary:
			var copy := {}
			for k: Variant in v:
				copy[str(k)] = v[k]
			d[name] = copy
		elif v is int or v is float or v is String or v is StringName or v is bool:
			d[name] = v
	return d


static func fill(o: Object, d: Dictionary) -> void:
	for name: String in d:
		var current: Variant = o.get(name)
		var v: Variant = d[name]
		if current is Object and v is Dictionary:
			fill(current, v)
		elif current == null and v is Dictionary and name == "tally":
			var t := PitchTally.new()
			fill(t, v)
			o.set(name, t)
		elif current is PackedInt32Array:
			o.set(name, PackedInt32Array(v))
		elif current is PackedFloat64Array:
			o.set(name, PackedFloat64Array(v))
		elif current is Dictionary:
			var target: Dictionary = current
			for k: String in v:
				target[StringName(k)] = int(v[k])
		elif current is int:
			o.set(name, int(v))
		elif current is float:
			o.set(name, float(v))
		else:
			o.set(name, v)
