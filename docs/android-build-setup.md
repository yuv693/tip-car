# Android build setup

The Flutter mobile checks workflow builds a debug APK for the Tip Car Supabase project. It uses only the Supabase publishable/anon key, which is intended for client apps; never use a service-role key in Android.

## Build and download the debug APK

1. Open the Tip Car repository: https://github.com/yuv693/tip-car
2. Open Actions → Flutter mobile checks.
3. Choose Run workflow on branch tipcarbus-starter, or open the latest successful run.
4. Download the artifact named tip-car-debug-apks.
5. Extract the ZIP and install the APK matching your Android device CPU architecture. Most recent Android phones use ARM64.

The workflow also uploads tip-car-android-project, which contains the Flutter/Android project source.

## Firebase push notification setup

Push notifications are optional for the app to operate: the active Realtime ride inbox remains the fallback. To enable FCM:

1. Create an Android app in Firebase Console using the exact Android application ID from the generated Android project.
2. Download google-services.json and add it at mobile/android/app/google-services.json in the tipcarbus-starter branch. This file contains client configuration, not the Firebase Admin private key. Do not upload a service-account JSON here.
3. In Firebase Console, enable Cloud Messaging for the project.
4. Create a Firebase service account with permission to send Firebase Cloud Messaging messages. Keep its JSON private.
5. In Supabase Dashboard → Edge Functions → Secrets, add FCM_SERVICE_ACCOUNT_JSON with the full service-account JSON.
6. Run Flutter mobile checks again. The workflow detects google-services.json and enables the Google Services Gradle plugin automatically.
7. Install the resulting APK on two Android phones. Sign in as a driver on one and passenger on the other; test a nearby matching request while the driver app is backgrounded.

Never commit the Firebase service-account JSON, private key, Supabase service-role key, or payment credentials to GitHub. Push is not considered verified until a real-device background notification test succeeds.

## No-OTP login

Android login uses Supabase Anonymous Sign-Ins. The user enters a name and mobile number; no SMS provider or Phone Auth OTP is used. The number is saved as unverified contact information. Keep database migration 20261123160000_allow_no_otp_anonymous_sessions.sql applied so ownership-scoped ride policies permit these sessions.

## Security

The Supabase publishable/anon key may be included in a client app. Database access must be enforced by Row Level Security and ownership checks. Never place passwords, database credentials, service-role keys, Firebase Admin private keys, or payment secrets in the app.
