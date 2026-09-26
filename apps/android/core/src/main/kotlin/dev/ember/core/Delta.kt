package dev.ember.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
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
 */
fun applyDelta(value: JsonElement, ops: JsonArray): JsonElement =
    ops.fold(value) { current, element ->
        val op = element.jsonObject
        applyOp(current, op, op["path"]?.jsonArray ?: return@fold current, 0)
    }

private fun applyOp(node: JsonElement, op: JsonObject, path: JsonArray, depth: Int): JsonElement {
    if (depth == path.size) {
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
