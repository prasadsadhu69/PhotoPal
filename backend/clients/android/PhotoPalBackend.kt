// PhotoPal backend client for Android (starting point for the Android app).
//
// build.gradle.kts (app):
//   implementation(platform("com.google.firebase:firebase-bom:<latest>"))
//   implementation("com.google.firebase:firebase-auth")
//   implementation("com.google.firebase:firebase-functions")
//   implementation("com.google.firebase:firebase-messaging")
//   implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:<latest>")
// Add google-services.json from the Firebase console.
//
// Same API as iOS (backend/docs/API.md). Photo IDs and images never leave the phone;
// only counts and byte totals are sent.

package com.photopal.backend

import com.google.firebase.Firebase
import com.google.firebase.auth.auth
import com.google.firebase.functions.functions
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.util.TimeZone

@Serializable data class Look(val species: String, val paletteId: String, val custom: Palette? = null)
@Serializable data class Palette(val id: String, val name: String, val main: List<Double>, val accent: List<Double>, val belly: List<Double>, val blaze: Boolean, val price: Int)
@Serializable data class Pal(
    val id: String, val name: String, val look: Look, val born: Double, val stage: String, val xp: Int,
    val careMistakes: Int, val food: Double, val joy: Double, val energy: Double, val sick: Boolean,
    val hatId: String? = null, val neckId: String? = null,
)
@Serializable data class Daily(val kind: String, val target: Int, val progress: Int, val reward: Int, val day: String, val paid: Boolean)
@Serializable data class Decor(val id: String, val itemId: String, val x: Double, val y: Double)
@Serializable data class State(
    val timezone: String, val onboarded: Boolean, val pal: Pal, val otherPals: List<Pal>, val tickets: Int,
    val clean: Double, val sleeping: Boolean, val coins: Int, val inventory: Map<String, Int>,
    val wardrobe: List<String>, val palettesOwned: List<String>, val photoMatchUnlocked: Boolean,
    val decorOwned: Map<String, Int>, val placed: List<Decor>, val itemsTossed: Int, val bytesFreed: Long,
    val cleanups: Int, val poops: Int, val streak: Int, val daily: Daily? = null, val milestones: List<String>, val hasFed: Boolean,
)
@Serializable data class Condition(val sleeping: Boolean, val sick: Boolean, val dirty: Boolean)
@Serializable data class Derived(
    val mood: String, val level: Int, val levelProgress: Double, val nextStage: String? = null, val xpToNextStage: Int,
    val growthProgress: Double, val cozy: Int, val condition: Condition, val buildUnlocked: Boolean,
    val canDigToday: Boolean, val ageDays: Int, val speciesToAdopt: List<String>, val today: String,
)
@Serializable data class Milestone(val id: String, val title: String, val bytes: Long, val coins: Int, val gift: String? = null)
@Serializable data class Reward(
    val kind: String, val count: Int, val bytes: Long, val coins: Int, val firstTodayBonus: Int,
    val streakBonus: Int, val dailyBonus: Int, val milestones: List<Milestone>, val total: Int,
)
@Serializable data class Events(val grewTo: String? = null, val coinsDelta: Int? = null, val reward: Reward? = null)
@Serializable data class GameResponse(
    val state: State, val derived: Derived, val rev: Int, val catalogVersion: Int, val events: Events,
    val isNew: Boolean? = null, val canImportLegacySave: Boolean? = null,
)

class PhotoPalBackend {
    private val functions = Firebase.functions("us-central1")
    private val json = Json { ignoreUnknownKeys = true }
    private val _game = MutableStateFlow<GameResponse?>(null)
    val game: StateFlow<GameResponse?> = _game

    suspend fun start() {
        if (Firebase.auth.currentUser == null) Firebase.auth.signInAnonymously().await()
        _game.value = call("bootstrap", mapOf("timezone" to TimeZone.getDefault().id))
    }

    /** Sends one action from the table in API.md, e.g. act("feed", mapOf("itemId" to "kibble")). */
    suspend fun act(action: String, params: Map<String, Any> = emptyMap()): Events {
        val response = call("act", mapOf("action" to action, "params" to params))
        _game.value = response
        return response.events
    }

    /** After a MediaStore scan: counts and bytes per kind only. */
    suspend fun reportScan(counts: Map<String, Int>, bytes: Map<String, Long>, totalAssets: Int) =
        act("reportScan", mapOf("counts" to counts, "bytes" to bytes, "totalAssets" to totalAssets))

    /** After MediaStore.createTrashRequest succeeded. */
    suspend fun claimCleanup(kind: String, count: Int, bytes: Long) =
        act("claimCleanup", mapOf("kind" to kind, "count" to count, "bytes" to bytes))

    suspend fun registerPushToken(token: String, reminders: Boolean = true) {
        functions.getHttpsCallable("registerDevice").call(mapOf("token" to token, "platform" to "android", "reminders" to reminders)).await()
    }

    suspend fun deleteAccount() {
        functions.getHttpsCallable("deleteAccount").call().await()
        Firebase.auth.signOut()
        _game.value = null
    }

    private suspend fun call(name: String, data: Map<String, Any>): GameResponse {
        val result = functions.getHttpsCallable(name).call(data).await()
        val element = toJson(result.getData())
        return json.decodeFromJsonElement(GameResponse.serializer(), element as JsonObject)
    }

    private fun toJson(value: Any?): kotlinx.serialization.json.JsonElement = when (value) {
        null -> kotlinx.serialization.json.JsonNull
        is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to toJson(v) })
        is List<*> -> kotlinx.serialization.json.JsonArray(value.map { toJson(it) })
        is Boolean -> kotlinx.serialization.json.JsonPrimitive(value)
        is Number -> kotlinx.serialization.json.JsonPrimitive(value)
        else -> kotlinx.serialization.json.JsonPrimitive(value.toString())
    }
}
