# Android build setup

The Android APK is configured from GitHub Actions secrets. Do not commit Supabase keys into the Flutter source code.

## Add the two repository secrets

1. Open the Tip Car repository: https://github.com/yuv693/tip-car
2. Go to **Settings → Secrets and variables → Actions**.
3. Under **Repository secrets**, choose **New repository secret**.
4. Add these two secrets:

| Secret name | Value |
|---|---|
| `SUPABASE_URL` | Your Supabase project's Project URL |
| `SUPABASE_ANON_KEY` | Your project's publishable/anon key |

Find both values in the Supabase dashboard under **Project Settings → API** (the exact label may be **Publishable key** or **anon/public key**, depending on the dashboard version).

**Important:** Use only the publishable/anon key. Never use the `service_role` key in a mobile app or GitHub build.

## Create a configured APK

After both secrets are saved:

1. Open the repository's **Actions** tab.
2. Select **Flutter mobile checks**.
3. Choose **Run workflow** on branch `tipcarbus-starter`.
4. Wait for all steps to finish successfully.
5. Download the `tip-car-debug-apk` artifact from that run. The APK inside is `app-debug.apk`.

The workflow also uploads `tip-car-android-project`, containing the Android project source.

Pull-request checks intentionally do not require repository secrets. The build on the protected project branch and a manually started workflow verify that both secrets are present and inject them at build time.

## Security note

The app uses Supabase Row Level Security and authenticated RPC permissions for data access. The publishable/anon key is designed to be present in client apps; database security must be enforced by RLS and server-side policies. Do not put passwords, OTPs, database passwords, or the service-role key in these secrets.
