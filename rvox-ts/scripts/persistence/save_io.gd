class_name SaveIO
extends RefCounted

## Atomic, backed-up JSON save/load (DEMO_PLAN.md §8). Every write goes to a
## temp file first and is renamed into place, so a crash mid-write can never
## corrupt the live save. The previous good file is kept as `.bak`; if the live
## file is later found unparseable, the backup is used to recover. All static —
## the stores call these; there's no state to hold.

const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"


## Atomically write `data` as JSON to `path` (a user:// path). Returns true on
## success. Keeps the prior contents as `path.bak`.
static func write_json(path: String, data: Dictionary) -> bool:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveIO: cannot open %s for writing (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	# Preserve the current good file as a backup before replacing it.
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + BAK_SUFFIX)

	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("SaveIO: rename %s -> %s failed (%d)" % [tmp, path, err])
		return false
	return true


## Parse the JSON at `path`. On missing or corrupt file, tries `path.bak`, and
## finally returns `fallback` (duplicated) so callers always get a usable dict.
static func read_json(path: String, fallback: Dictionary = {}) -> Dictionary:
	var parsed: Variant = _try_parse(path)
	if parsed != null:
		return parsed
	var backup: Variant = _try_parse(path + BAK_SUFFIX)
	if backup != null:
		push_warning("SaveIO: recovered %s from backup" % path)
		return backup
	return fallback.duplicate(true)


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BAK_SUFFIX)


## Remove the save, its backup, and any stray temp file.
static func remove(path: String) -> void:
	for p in [path, path + BAK_SUFFIX, path + TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _try_parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	# JSON.new().parse() returns an error code without printing to the console,
	# unlike JSON.parse_string — so a corrupt save recovers quietly instead of
	# spamming errors (the recovery is expected behaviour, not a fault).
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if json.data is Dictionary:
		return json.data
	return null # wrong shape -> treat as corrupt
