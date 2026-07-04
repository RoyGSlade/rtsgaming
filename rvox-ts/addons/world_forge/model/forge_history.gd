@tool
class_name ForgeHistory
extends RefCounted

signal changed

const MAX_ENTRIES := 100

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func record(label: String, before: Dictionary, after: Dictionary) -> void:
	if before == after:
		return
	_undo.append({"label": label, "before": before.duplicate(true), "after": after.duplicate(true)})
	if _undo.size() > MAX_ENTRIES:
		_undo.pop_front()
	_redo.clear()
	changed.emit()


func undo(document: ForgeDocument) -> String:
	if _undo.is_empty():
		return ""
	var entry: Dictionary = _undo.pop_back()
	_redo.append(entry)
	document.restore_snapshot(entry["before"])
	changed.emit()
	return str(entry["label"])


func redo(document: ForgeDocument) -> String:
	if _redo.is_empty():
		return ""
	var entry: Dictionary = _redo.pop_back()
	_undo.append(entry)
	document.restore_snapshot(entry["after"])
	changed.emit()
	return str(entry["label"])


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_label() -> String:
	return str(_undo.back().get("label", "")) if not _undo.is_empty() else ""


func redo_label() -> String:
	return str(_redo.back().get("label", "")) if not _redo.is_empty() else ""


func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()
