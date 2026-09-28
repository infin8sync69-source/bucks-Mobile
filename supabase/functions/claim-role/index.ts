// claim-role: marks a Firebase user so Supabase accepts their token (custom claim role = "authenticated").
// The same job as firebase/functions (setSupabaseRole), without needing Firebase's Blaze plan: the app calls this once,
// right after sign-in, when its token has no role claim yet, then refreshes the token.
//
// Deploy:  supabase functions deploy claim-role --no-verify-jwt   (the caller's Firebase ID token is verified here)
// Secret:  FCM_SERVICE_ACCOUNT = the Firebase service-account JSON (Project settings > Service accounts > Generate new private key).
//          The same secret later sends push notifications (functions/notify). FIREBASE_SERVICE_ACCOUNT also works.
// No dependencies: RS256 verify and sign through WebCrypto.

type ServiceAccount = { client_email: string; private_key: string; project_id: string; token_uri?: string };
type Jwk = JsonWebKey & { kid?: string };

const SA_JSON = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") || Deno.env.get("FCM_SERVICE_ACCOUNT") || "";
const JWKS_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const b64url = (data: string | ArrayBuffer) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = ""; for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const fromB64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));
const pemToDer = (pem: string) => Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));

let jwks: { keys: Jwk[]; until: number } | null = null;
async function googleKeys(): Promise<Jwk[]> {
  if (jwks && jwks.until > Date.now()) return jwks.keys;
  const r = await fetch(JWKS_URL);
  if (!r.ok) throw new Error(`Google keys: ${r.status}`);
  const body = await r.json() as { keys: Jwk[] };
  jwks = { keys: body.keys, until: Date.now() + 3_600_000 };
  return body.keys;
}

/** A Firebase ID token for this project, signed by Google and in date; returns the user's uid. */
async function verifyFirebaseToken(token: string, projectId: string): Promise<string> {
  const [h, p, s] = token.split(".");
  if (!h || !p || !s) throw new Error("malformed token");
  const header = JSON.parse(new TextDecoder().decode(fromB64url(h)));
  const claims = JSON.parse(new TextDecoder().decode(fromB64url(p)));
  if (header.alg !== "RS256") throw new Error("unexpected algorithm");
  const jwk = (await googleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("unknown signing key");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, fromB64url(s), new TextEncoder().encode(`${h}.${p}`));
  const now = Math.floor(Date.now() / 1000);
  if (!ok) throw new Error("bad signature");
  if (claims.aud !== projectId || claims.iss !== `https://securetoken.google.com/${projectId}`) throw new Error("token is for another project");
  if (typeof claims.exp !== "number" || claims.exp < now - 60 || (claims.iat ?? 0) > now + 60) throw new Error("token expired");
  if (typeof claims.sub !== "string" || !claims.sub) throw new Error("no user");
  return claims.sub;
}

/** OAuth2 access token for the service account (a self-signed JWT exchanged at Google's token endpoint). */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const tokenUri = sa.token_uri || "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/cloud-platform", aud: tokenUri, iat: now, exp: now + 3600 }));
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const r = await fetch(tokenUri, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${header}.${claims}.${b64url(signature)}` }) });
  if (!r.ok) throw new Error(`Google token: ${r.status} ${await r.text()}`);
  return (await r.json()).access_token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!SA_JSON) return json(500, { error: "FCM_SERVICE_ACCOUNT secret is not set" });
  let sa: ServiceAccount;
  try { sa = JSON.parse(SA_JSON); } catch { return json(500, { error: "FCM_SERVICE_ACCOUNT is not valid JSON" }); }
  const token = (req.headers.get("x-firebase-token") || req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
  let uid: string;
  try { uid = await verifyFirebaseToken(token, sa.project_id); } catch (e) { return json(401, { error: `not signed in: ${(e as Error).message}` }); }
  try {
    const r = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${sa.project_id}/accounts:update`, {
      method: "POST", headers: { Authorization: `Bearer ${await accessToken(sa)}`, "Content-Type": "application/json" },
      body: JSON.stringify({ localId: uid, customAttributes: JSON.stringify({ role: "authenticated" }) }),
    });
    if (!r.ok) return json(502, { error: `Firebase: ${r.status} ${await r.text()}` });
    return json(200, { ok: true });
  } catch (e) {
    return json(502, { error: (e as Error).message });
  }
});
