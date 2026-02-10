package app.tiki.mr

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.android.gms.tasks.Task
import com.google.firebase.pnv.FirebasePhoneNumberVerification
import com.google.firebase.pnv.VerifiedPhoneNumberTokenResult

class MainActivity : FlutterActivity() {
  private val CHANNEL = "tiki/fpnv"

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {

          "isSupported" -> {
            val fpnv = FirebasePhoneNumberVerification.getInstance()
            fpnv.getVerificationSupportInfo()
              .addOnSuccessListener { infoList ->
                val supported = infoList.any { it.isSupported() }
                result.success(supported)
              }
              .addOnFailureListener {
                result.success(false) // fallback
              }
          }

          "getVerifiedPhoneNumber" -> {
            // Supports both SDK signatures:
            // - getVerifiedPhoneNumber()
            // - getVerifiedPhoneNumber(String privacyPolicyUrl)
            val privacyUrl = call.argument<String>("privacyPolicyUrl")?.trim()
            val fpnvWithActivity = FirebasePhoneNumberVerification.getInstance(this)

            try {
              val task = invokeGetVerifiedPhoneNumber(fpnvWithActivity, privacyUrl)
              task
                .addOnSuccessListener { r ->
                  result.success(hashMapOf(
                    "phoneNumber" to r.getPhoneNumber(),
                    "token" to r.getToken()
                  ))
                }
                .addOnFailureListener { e ->
                  result.error("FPNV_ERROR", e.message, e.toString())
                }
            } catch (e: Exception) {
              result.error("FPNV_ERROR", e.message, e.toString())
            }
          }

          else -> result.notImplemented()
        }
      }
  }

  private fun invokeGetVerifiedPhoneNumber(
    fpnv: FirebasePhoneNumberVerification,
    privacyUrl: String?
  ): Task<VerifiedPhoneNumberTokenResult> {
    val cls = fpnv.javaClass

    val methodWithUrl = cls.methods.firstOrNull { m ->
      m.name == "getVerifiedPhoneNumber" &&
        m.parameterTypes.size == 1 &&
        m.parameterTypes[0] == String::class.java
    }

    val methodNoArgs = cls.methods.firstOrNull { m ->
      m.name == "getVerifiedPhoneNumber" && m.parameterTypes.isEmpty()
    }

    val m = when {
      methodWithUrl != null && !privacyUrl.isNullOrBlank() -> methodWithUrl
      methodNoArgs != null -> methodNoArgs
      methodWithUrl != null -> methodWithUrl // last resort (pass empty string)
      else -> throw NoSuchMethodException("getVerifiedPhoneNumber not found on ${cls.name}")
    }

    @Suppress("UNCHECKED_CAST")
    return if (m.parameterTypes.size == 1) {
      m.invoke(fpnv, (privacyUrl ?: "")) as Task<VerifiedPhoneNumberTokenResult>
    } else {
      m.invoke(fpnv) as Task<VerifiedPhoneNumberTokenResult>
    }
  }
}
