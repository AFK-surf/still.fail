package fail.still.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * A delta (`Op` in client/core/src/delta.rs) applied to a value, as
 * `applyDelta` in web/src/core/client.ts does: only the objects and arrays
 * along each op's path are copied, so unchanged parts stay the same instances
 * and Compose skips them.
 *
 * Ops: `{ path, set }` replaces (path `[]` = the whole value), `{ path, append }`
 * adds items at the end of an array, `{ path, remove: true }` removes a key.
 * Keyed ops (client/core-ts/src/collections.ts; only to a subscription made
 * with `keyed: true`) change one item of the list at `path`, found by its key
 * (`key`: the fields it is made of; the one field's value, or the fields'
 * values in order): `put` (before the item keyed `before`, null at the end;
 * without `before`, in place of the one with its key), `patch` (its own ops),
 * `drop`, `move` (before `before`). Items they do not touch stay the same
 * instances.
 */
fun applyDelta(value: JsonElement, ops: JsonArray): JsonElement =
    ops.fold(value) { current, element ->
        val op = element.jsonObject
        applyOp(current, op, op["path"]?.jsonArray ?: return@fold current, 0)
    }

private fun applyOp(node: JsonElement, op: JsonObject, path: JsonArray, depth: Int): JsonElement {
    if (depth == path.size) {
        val fields = op["key"]
        if (fields is JsonArray) return if (node is JsonArray) applyKeyed(node, op, fields.map { (it as JsonPrimitive).content }) else node
        op["set"]?.let { return it }
        val append = op["append"]
        return if (append is JsonArray && node is JsonArray) JsonArray(node + append) else node
    }
    val key = path[depth] as? JsonPrimitive ?: return node
    if (node is JsonArray) {
        val index = if (key.isString) null else key.intOrNull
        if (index == null || index !in node.indices) return node
        return JsonArray(node.toMutableList().also { it[index] = applyOp(node[index], op, path, depth + 1) })
    }
    if (node !is JsonObject || !key.isString) return node
    val name = key.content
    val last = depth == path.size - 1
    if (last && "remove" in op) return JsonObject(node - name)
    val child = node[name]
    // Nothing there to go into; only a `set` of the key itself can add it.
    if (child == null && !(last && "set" in op)) return node
    return JsonObject(node + (name to applyOp(child ?: op.getValue("set"), op, path, depth + 1)))
}

/** An item's key, as the core writes it: the one field's value, or the fields' values in order. */
private fun keyOf(item: JsonElement, fields: List<String>): JsonElement {
    fun field(f: String) = (item as? JsonObject)?.get(f) ?: JsonNull
    return if (fields.size == 1) field(fields[0]) else JsonArray(fields.map(::field))
}

/** Keys compare as values: a number the core wrote as 1.0 is the 1 an item holds. */
private fun sameKey(a: JsonElement, b: JsonElement): Boolean = when {
    a is JsonArray && b is JsonArray -> a.size == b.size && a.indices.all { sameKey(a[it], b[it]) }
    a is JsonPrimitive && b is JsonPrimitive && !a.isString && !b.isString ->
        a.content == b.content || (a.content.toDoubleOrNull() != null && a.content.toDoubleOrNull() == b.content.toDoubleOrNull())
    else -> a == b
}

private fun applyKeyed(list: JsonArray, op: JsonObject, fields: List<String>): JsonElement {
    val out = list.toMutableList()
    fun find(key: JsonElement) = out.indexOfFirst { sameKey(keyOf(it, fields), key) }
    fun place(item: JsonElement, before: JsonElement?) {
        val at = if (before == null || before is JsonNull) -1 else find(before)
        if (at < 0) out.add(item) else out.add(at, item)
    }
    when {
        "drop" in op -> {
            val i = find(op.getValue("drop"))
            if (i < 0) return list
            out.removeAt(i)
        }
        "patch" in op -> {
            val i = find(op.getValue("patch"))
            val ops = op["ops"] as? JsonArray
            if (i < 0 || ops == null) return list
            out[i] = applyDelta(out[i], ops)
        }
        "move" in op -> {
            val i = find(op.getValue("move"))
            if (i < 0) return list
            place(out.removeAt(i), op["before"])
        }
        "put" in op -> {
            val item = op.getValue("put")
            val i = find(keyOf(item, fields))
            if (i >= 0 && "before" !in op) out[i] = item
            else {
                if (i >= 0) out.removeAt(i)
                place(item, op["before"])
            }
        }
        else -> return list
    }
    return JsonArray(out)
}
