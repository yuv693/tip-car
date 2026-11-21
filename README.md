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
4. After running `supabase/schema.sql`, apply the SQL files `supabase/migrations/20261121072354_tip_car_bike_vehicle_type.sql` and `supabase/migrations/20261121080317_instant_bike_car_taxi_matching.sql` through `supabase/migrations/20261121080503_enforce_instant_taxi_request_transitions.sql` in filename order.
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
- Publish bike, car and bus rides with route, date, seats and fare (web + Android)
- Filter ride search by bike, car or bus; bike rides are limited to one passenger and car rides to seven passenger seats
- Instant Bike/Car Taxi: driver online presence, GPS-based 8 km matching, first-driver acceptance, pickup/arrived/start/complete statuses, and live driver coordinates
- Search active rides by origin/destination
- Database-side atomic seat booking
- Booking history and basic admin overview (web)

## Still needs external configuration / production hardening
- Google Maps, Places autocomplete and live GPS tracking
- Razorpay/other payment gateway and signed webhook verification
- Push notifications (FCM) for incoming requests when the driver app is backgrounded or closed; the current instant request inbox uses an active Realtime connection
- SMS provider
- Driver KYC/document upload and manual verification
- SOS dispatch/contact workflow
- Cancellation, refund and dispute workflows
- Legal review, rate limiting, audit logs, monitoring, backups, security testing and Play Store signing

Never put Supabase service-role keys or payment secrets in client apps. Verify drivers, vehicle documents,
permits and insurance before public launch. Test booking and payment flows before accepting money.
