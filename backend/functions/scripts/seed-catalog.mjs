// Uploads src/rules/catalog.data.json to Firestore (config/catalog).
// Running functions pick it up within 5 minutes, without a redeploy, and the apps read it too.
//
// Edit prices, items or tuning in catalog.data.json, bump "version", then:
//   gcloud auth application-default login     (once)
//   npm run seed:catalog
import { readFileSync } from "node:fs";
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const rc = JSON.parse(readFileSync(new URL("../../.firebaserc", import.meta.url), "utf8"));
const projectId = process.env.GCLOUD_PROJECT || rc.projects.default;
if (!projectId || projectId.startsWith("YOUR-")) throw new Error("Set your project ID in backend/.firebaserc first");

const catalog = JSON.parse(readFileSync(new URL("../src/rules/catalog.data.json", import.meta.url), "utf8"));
initializeApp({ credential: applicationDefault(), projectId });
await getFirestore().collection("config").doc("catalog").set({ data: catalog, updatedAt: Date.now() });
console.log(`Uploaded catalog v${catalog.version} (${catalog.items.length} items) to ${projectId}`);
