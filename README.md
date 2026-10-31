# Tip Car & Bus — Website + Android App

A single monorepo containing:
- `web/`: responsive React + Vite website (passenger, driver and admin views)
- `mobile/`: Flutter Android app starter using the same Supabase backend
- `supabase/schema.sql`: database tables, constraints and Row Level Security policies

## Important status
This is a runnable application foundation, not a live production deployment. Real OTP delivery,
Google Maps billing/API access, payment gateway credentials, SMS/push credentials, domain hosting,
and Play Store signing must be configured by the owner. No real payment is claimed until a
gateway webhook verifies it. Never put service-role keys or payment secrets in client apps.

## Recommended setup
1. Create a project at https://supabase.com
2. Run `supabase/schema.sql` in SQL Editor.
3. Enable Phone in Authentication > Providers and configure an SMS provider.
4. Copy the project URL and anon/public key.

### Website
```bash
cd web
cp .env.example .env
# Fill VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

### Android app
Install Flutter SDK and Android Studio, then:
```bash
cd mobile
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

### First admin
After registering your account, run in Supabase SQL Editor (replace the phone):
```sql
update public.profiles set role = 'admin' where phone = '+91XXXXXXXXXX';
```
Do this only for your own verified admin account.

## Included foundation
- Phone OTP sign-in through Supabase Auth
- Passenger/driver profile roles
- Publish car/bus rides with route, date, seats and fare (web)
- Search active rides by origin/destination
- Database-side atomic seat booking
- Booking history and basic admin overview (web)

## Still needs external configuration / production hardening
- Google Maps, Places autocomplete and live GPS tracking
- Razorpay/other payment gateway and signed webhook verification
- Push notifications (FCM) and SMS provider
- Driver KYC/document upload and manual verification
- SOS dispatch/contact workflow
- Cancellation, refund and dispute workflows
- Legal review, rate limiting, audit logs, monitoring, backups, security testing and Play Store signing

Never put Supabase service-role keys or payment secrets in client apps. Verify drivers, vehicle documents,
permits and insurance before public launch. Test booking and payment flows before accepting money.
