// Firebase entry point: wraps the API handlers as callable functions.
// Both the iOS and Android apps call these with the Firebase Functions SDK
// (callables carry the player's Firebase Auth ID token automatically).

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/https";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/scheduler";
import * as api from "./api/handlers";
import { GameError } from "./rules/engine";
import { FirestoreStore } from "./store/firestore";

initializeApp();
const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });
const env: api.Env = { store: new FirestoreStore(db) };

// One region for everything keeps latency and cost predictable. maxInstances caps runaway spend.
setGlobalOptions({ region: "us-central1", maxInstances: 20, memory: "256MiB" });

// Turn on once App Check is set up in both apps (blocks calls that don't come from your real apps).
const ENFORCE_APP_CHECK = false;

function callable<T>(fn: (uid: string, data: any, req: CallableRequest) => Promise<T>) {
  return onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first (anonymous sign-in is fine)");
    try {
      return await fn(uid, req.data ?? {}, req);
    } catch (e) {
      if (e instanceof GameError) throw new HttpsError(e.code, e.message);
      logger.error("Unhandled error", { uid, error: e });
      throw new HttpsError("internal", "Something went wrong");
    }
  });
}

export const bootstrap = callable((uid, data) => api.bootstrap(env, uid, data));
export const act = callable((uid, data) => api.act(env, uid, data));
export const importLegacySave = callable((uid, data) => api.importLegacySave(env, uid, data));
export const getCatalog = callable(() => api.getCatalog(env));
export const registerDevice = callable((uid, data) => api.registerDevice(env, uid, data));
export const unregisterDevice = callable((uid, data) => api.unregisterDevice(env, uid, data));
export const exportMyData = callable((uid) => api.exportMyData(env, uid));
export const deleteAccount = callable(async (uid) => {
  await api.deleteMyData(env, uid);
  await getAuth().deleteUser(uid);
  return { ok: true };
});

export const hungryReminders = onSchedule({ schedule: "every 30 minutes", timeoutSeconds: 300 }, async () => {
  const result = await api.sendDueReminders(env, async (tokens, msg) => {
    const res = await getMessaging().sendEachForMulticast({ tokens, notification: msg, apns: { payload: { aps: { sound: "default" } } } });
    const invalidTokens = res.responses
      .map((r, i) => (!r.success && r.error?.code === "messaging/registration-token-not-registered" ? tokens[i] : null))
      .filter((t): t is string => !!t);
    return { invalidTokens };
  });
  logger.info("Hungry reminders", result);
});
