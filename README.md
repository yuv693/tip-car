# Tip Car & Bus — Website + Android App

A single monorepo containing:
- `web/`: responsive React + Vite website (passenger, driver and admin views)
- `mobile/`: Flutter Android app starter using the same Supabase backend
- `supabase/schema.sql`: database tables, constraints and Row Level Security policies

## Important status
This is a runnable application foundation, not a live production deployment. Google Maps billing/API access,
payment gateway credentials, push credentials, domain hosting, and Play Store signing must be configured by the owner.
The Android app uses a name + mobile-number profile with no SMS OTP; the mobile number is not verified. No real payment is claimed until a
gateway webhook verifies it. Never put service-role keys or payment secrets in client apps.

## Recommended setup
1. Create a project at https://supabase.com
2. Run `supabase/schema.sql` in SQL Editor.
3. In Authentication > Sign In / Providers, enable **Anonymous Sign-Ins** for the Android app. No Phone provider or SMS gateway is needed for Android login.
4. After running `supabase/schema.sql`, apply the SQL files `supabase/migrations/20261121072354_tip_car_bike_vehicle_type.sql` and `supabase/migrations/20261121080317_instant_bike_car_taxi_matching.sql` through `supabase/migrations/20261121080900_limit_active_instant_taxi_requests.sql`, then apply `20261121090000_route_fare_kyc_fcm.sql` and `20261121100000_remove_driver_kyc_gate.sql` in filename order.
5. Apply `supabase/migrations/20261121120000_unified_completed_ride_commission_and_insurance_reward.sql` after the earlier migrations to enable the shared ₹20 completed-ride commission and 1,000-ride reward counter. The `get_my_driver_benefits()` RPC is used by the Android app.
6. Apply all later `20261123*.sql` migrations in filename order. In particular, `20261123160000_allow_no_otp_anonymous_sessions.sql` is required for the no-OTP Android sessions to create rides, go online and share live locations while keeping row ownership and nearby-driver restrictions.
7. Copy the project URL and publishable/anon key.

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
Do this only for your own account; the Android mobile number is not OTP-verified.

## Included foundation
- Android login: enter full name + mobile number, tap Continue; no OTP/SMS. Supabase anonymous Auth creates a persistent app session and the profile stores the entered name, mobile number and role. The mobile number is contact information only and is not verified.
- Passenger/driver profile roles
- Publish bike, car and bus rides with route, date, seats and fare (web + Android)
- Filter ride search by bike, car or bus; bike rides are limited to one passenger and car rides to seven passenger seats
- Instant Bike/Car Taxi: driver online presence, GPS-based 8 km matching, first-driver acceptance, pickup/arrived/start/complete statuses, and live driver coordinates
- Search active rides by origin/destination
- Database-side atomic seat booking
- Booking history and basic admin overview (web)

## Still needs external configuration / production hardening
- Firebase Android app configuration (`google-services.json`), the Supabase `FCM_SERVICE_ACCOUNT_JSON` secret, and a real-device background push test. Until then, the active Realtime inbox is the fallback.
- A production map/routing provider and its API credentials/usage terms; current OpenStreetMap Nominatim and public OSRM demo endpoints are development services.
- A contracted insurance provider and actual policy terms before any driver can receive the 1,000-ride insurance reward.
- Real-device passenger/driver testing, operational monitoring, backups, legal review, abuse/rate-limit controls, security review and release signing.
- Payment gateway intentionally remains out of scope for this build.

Never put Supabase service-role keys or payment secrets in client apps. Test booking and payment flows before accepting money.


## Instant Taxi additions (Nov 2026)
- Destination lookup uses OpenStreetMap Nominatim; road route geometry, distance and ETA use the public OSRM demo endpoint. These public endpoints are rate-limited and are suitable for development, not a guaranteed production SLA.
- Indicative estimates: Bike = ₹25 base + ₹8/km + ₹1.20/min; Car = ₹45 base + ₹14/km + ₹1.80/min. These are provisional display estimates only; no payment is collected and final fare policy must be approved before launch.
- Both ride modes stay available in one app: scheduled ride-sharing (publish/search/book) and instant Bike/Car taxi (request/accept/live status). No KYC upload or admin approval is required by the app.
- Commission rule: ₹20 is accrued only after each successfully completed scheduled booking or instant Bike/Car taxi ride; cancellations do not accrue commission. Driver benefits count completed bookings and instant taxi rides toward the 1,000-ride insurance reward. The policy/provider and coverage still need to be contracted before an insurance policy can be issued.
- Customer fallback: while an instant taxi request is searching, the passenger can open **Find an alternative scheduled ride**, search active scheduled rides to the same destination, and explicitly choose/book one. This is a passenger-selected fallback, not an automatic guarantee that a vehicle will always be available; no ride is booked without the passenger confirming it.
- FCM function `notify-nearby-drivers` is deployed in Supabase. To make Android push delivery live, create/configure the Firebase Android app, add `google-services.json` to `mobile/android/app/`, and set the Supabase Edge Function secret `FCM_SERVICE_ACCOUNT_JSON` to a Firebase service account with Firebase Cloud Messaging send permission. Until the Firebase Android config and secret are installed and a real device push is verified, the app keeps its Realtime inbox fallback and push delivery must be treated as unverified.
- Never commit service-account JSON, private keys, or Firebase Admin credentials to GitHub.


## Safety and production-readiness notes
- The Android app includes an SOS screen: users can call India's emergency number 112, save an optional emergency contact, and open an SMS draft containing their current map location. The user must review/send the SMS; Tip Car does not silently message or dispatch emergency services.
- Apply migrations `20261123130000_add_emergency_contact.sql`, `20261123140000_allow_driver_cancel_before_start.sql`, `20261123150000_fix_driver_cancel_transition_order.sql`, and `20261123160000_allow_no_otp_anonymous_sessions.sql` in filename order before using SOS contact storage, driver cancellation and no-OTP ride workflows.
- Map screens currently use OpenStreetMap tiles with Nominatim place lookup and the public OSRM routing demo. This is a development setup, not a Google Maps integration or production availability guarantee. A production map/routing provider and usage terms must be selected before public scale.
- Scheduled booking cancellation and instant taxi passenger cancellation are available. A formal refund workflow is not active because Tip Car does not collect payments.
- Alternative scheduled-ride fallback is passenger-selected and atomic with cancellation of the still-searching instant taxi request. It is not an automatic guaranteed dispatch service.
- FCM push code and the Supabase Edge Function are present, but push delivery remains unverified until the Firebase Android config and `FCM_SERVICE_ACCOUNT_JSON` secret are configured and a physical-device test succeeds.
