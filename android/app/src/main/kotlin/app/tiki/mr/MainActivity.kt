package app.tiki.mr

import io.flutter.embedding.android.FlutterActivity

/**
 * MainActivity kept minimal for stability & Play Store builds.
 *
 * The project previously included an experimental native bridge for
 * Firebase Phone Number Verification (FPNV) using the MethodChannel 'tiki/fpnv'.
 * That SDK is not part of the current Android dependencies, which caused
 * compilation errors (unresolved reference: com.google.firebase.pnv.*).
 *
 * The app already uses Twilio OTP / password flows, so we remove the FPNV bridge.
 * Any calls from Dart (FpnvPlatform) will fall back safely via try/catch.
 */
class MainActivity : FlutterActivity()
