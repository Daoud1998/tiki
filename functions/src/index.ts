// functions/src/index.ts
// WhatsApp OTP via WhatsApp Cloud API + Firebase Custom Token.
// Style: eslint-config-google (double quotes, max-len 80, require-jsdoc).
//
// NOTE:
// Cloud Functions loads environment variables from functions/.env automaticaly.
// Read values via process.env.*.

import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {HttpsError, onCall} from "firebase-functions/v2/https";

admin.initializeApp();

const REGION = process.env.FUNCTIONS_REGION || "us-central1";

const WHATSAPP_TOKEN = process.env.WHATSAPP_TOKEN || "";
const WHATSAPP_PHONE_NUMBER_ID = process.env.WHATSAPP_PHONE_NUMBER_ID || "";
const WHATSAPP_TEMPLATE_NAME = process.env.WHATSAPP_TEMPLATE_NAME || "";
const OTP_SALT = process.env.OTP_SALT || "";

const OTP_TTL_SECONDS = parseInt(process.env.OTP_TTL_SECONDS || "300", 10);
const OTP_COOLDOWN_SECONDS = parseInt(
  process.env.OTP_COOLDOWN_SECONDS || "45",
  10
);

/**
 * Throws if required environment variables are missing.
 */
function assertConfigured() {
  if (WHATSAPP_TOKEN && WHATSAPP_PHONE_NUMBER_ID &&
      WHATSAPP_TEMPLATE_NAME && OTP_SALT) {
    return;
  }

  const msg = "Missing env vars. Put them in functions/.env: " +
    "WHATSAPP_TOKEN, WHATSAPP_PHONE_NUMBER_ID, " +
    "WHATSAPP_TEMPLATE_NAME, OTP_SALT.";
  throw new HttpsError("failed-precondition", msg);
}

/**
 * Normalizes and minimally validates an E.164 phone number.
 * @param {string} raw Raw phone number input.
 * @return {string} Normalized E.164 phone number.
 */
function normalizeE164(raw: string): string {
  const s = (raw || "").trim().replace(/\s+/g, "");
  if (!s.startsWith("+")) {
    throw new HttpsError(
      "invalid-argument",
      "phoneE164 must start with + and be in E.164 format."
    );
  }
  if (s.length < 8 || s.length > 20) {
    throw new HttpsError("invalid-argument", "phoneE164 seems invalid.");
  }
  return s;
}

/**
 * Generates a 6-digit OTP.
 * @return {string} OTP code.
 */
function randomOtp(): string {
  const n = Math.floor(Math.random() * 1000000);
  return n.toString().padStart(6, "0");
}

/**
 * Computes SHA-256 hex digest for input.
 * @param {string} input Text to hash.
 * @return {string} Hex digest.
 */
function sha256Hex(input: string): string {
  return crypto.createHash("sha256").update(input).digest("hex");
}

/**
 * Timing-safe compare between two hex strings.
 * @param {string} aHex First hex string.
 * @param {string} bHex Second hex string.
 * @return {boolean} True if equal.
 */
function timingSafeEqualHex(aHex: string, bHex: string): boolean {
  const a = Buffer.from(aHex, "hex");
  const b = Buffer.from(bHex, "hex");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Sends a WhatsApp template message containing the OTP.
 * @param {{toE164: string, languageCode: string, otp: string}} params Params.
 * @return {Promise<string>} Raw response text.
 */
async function sendWhatsAppTemplate(params: {
  toE164: string;
  languageCode: string;
  otp: string;
}): Promise<string> {
  const url = "https://graph.facebook.com/v19.0/" +
    WHATSAPP_PHONE_NUMBER_ID + "/messages";

  const payload = {
    messaging_product: "whatsapp",
    to: params.toE164,
    type: "template",
    template: {
      name: WHATSAPP_TEMPLATE_NAME,
      language: {code: params.languageCode || "ar"},
      components: [
        {
          type: "body",
          parameters: [{type: "text", text: params.otp}],
        },
      ],
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + WHATSAPP_TOKEN,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  if (!res.ok) {
    const msg = "WhatsApp API error: " + res.status + " " + text;
    throw new HttpsError("internal", msg);
  }
  return text;
}

/**
 * Firestore doc for OTP storage per phone.
 * @param {string} phoneE164 Phone number.
 * @return {FirebaseFirestore.DocumentReference} Doc ref.
 */
function otpDocRef(phoneE164: string) {
  return admin.firestore().collection("whatsappOtps").doc(phoneE164);
}

/**
 * Firestore doc for phone -> uid mapping.
 * @param {string} phoneE164 Phone number.
 * @return {FirebaseFirestore.DocumentReference} Doc ref.
 */
function phoneIndexRef(phoneE164: string) {
  return admin.firestore().collection("phoneIndex").doc(phoneE164);
}

/**
 * Callable: send WhatsApp OTP.
 */
export const sendWhatsappOtp = onCall({region: REGION}, async (request) => {
  assertConfigured();

  const phoneE164 = normalizeE164(request.data?.phoneE164);
  const languageCode = (request.data?.languageCode || "ar").toString();

  const ref = otpDocRef(phoneE164);
  const snap = await ref.get();
  const nowMs = Date.now();

  if (snap.exists) {
    const lastSentAtMs = (snap.data()?.lastSentAtMs as number) || 0;
    const cooldownMs = OTP_COOLDOWN_SECONDS * 1000;
    if (lastSentAtMs > 0 && nowMs - lastSentAtMs < cooldownMs) {
      const waitMs = cooldownMs - (nowMs - lastSentAtMs);
      const wait = Math.ceil(waitMs / 1000);
      return {ok: false, message: "Please wait " + wait + "s."};
    }
  }

  const otp = randomOtp();
  const otpHash = sha256Hex(OTP_SALT + "|" + phoneE164 + "|" + otp);
  const expiresAtMs = nowMs + OTP_TTL_SECONDS * 1000;

  await ref.set(
    {
      phoneE164,
      otpHash,
      expiresAtMs,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSentAtMs: nowMs,
      attempts: 0,
    },
    {merge: true}
  );

  await sendWhatsAppTemplate({toE164: phoneE164, languageCode, otp});
  return {ok: true};
});

/**
 * Callable: verify WhatsApp OTP and return a Firebase custom token.
 */
export const verifyWhatsappOtp = onCall({region: REGION}, async (request) => {
  assertConfigured();

  const phoneE164 = normalizeE164(request.data?.phoneE164);
  const code = (request.data?.code || "").toString().trim();

  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Code must be 6 digits.");
  }

  const ref = otpDocRef(phoneE164);
  const snap = await ref.get();
  if (!snap.exists) {
    return {ok: false, message: "No OTP request found. Request a new code."};
  }

  const data = snap.data() || {};
  const expiresAtMs = (data.expiresAtMs as number) || 0;
  const attempts = (data.attempts as number) || 0;

  if (expiresAtMs > 0 && Date.now() > expiresAtMs) {
    await ref.delete().catch(() => null);
    return {ok: false, message: "Code expired. Request a new code."};
  }

  if (attempts >= 8) {
    return {ok: false, message: "Too many attempts. Request a new code."};
  }

  const expectedHash = (data.otpHash as string) || "";
  const providedHash = sha256Hex(OTP_SALT + "|" + phoneE164 + "|" + code);
  const match = expectedHash ? timingSafeEqualHex(expectedHash, providedHash) :
    false;

  await ref.set({attempts: attempts + 1}, {merge: true});

  if (!match) {
    return {ok: false, message: "Invalid code."};
  }

  await ref.delete().catch(() => null);

  let userRecord: admin.auth.UserRecord | null = null;
  try {
    userRecord = await admin.auth().getUserByPhoneNumber(phoneE164);
  } catch {
    userRecord = null;
  }

  if (!userRecord) {
    const idxSnap = await phoneIndexRef(phoneE164).get();
    const mappedUid = (idxSnap.data()?.uid as string) || "";

    if (mappedUid) {
      try {
        userRecord = await admin.auth().getUser(mappedUid);
      } catch {
        userRecord = null;
      }
    }

    if (!userRecord) {
      userRecord = await admin.auth().createUser({phoneNumber: phoneE164});
    }
  }

  const uid = userRecord.uid;

  await phoneIndexRef(phoneE164).set(
    {uid, phoneE164, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
    {merge: true}
  );

  await admin.firestore().collection("users").doc(uid).set(
    {uid, phoneE164, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
    {merge: true}
  );

  const customToken = await admin.auth().createCustomToken(uid, {
    authProvider: "whatsapp",
  });

  return {ok: true, uid, customToken};
});
