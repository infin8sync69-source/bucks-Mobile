// Supabase trusts Firebase sign-ins only when the token carries role=authenticated.
// Deploy once: `cd firebase/functions && npm i firebase-functions@^6 firebase-admin@^12 && firebase deploy --only functions`
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
admin.initializeApp();

exports.setSupabaseRole = functions.region("asia-south1").auth.user().onCreate((user) =>
  admin.auth().setCustomUserClaims(user.uid, { role: "authenticated" }));
