import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/tip_car_brand.dart';

import 'driver_benefits_screen.dart';
import 'booking_history_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool configured;

  const HomeScreen({super.key, required this.configured});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final from = TextEditingController(text: 'Porbandar');
  final to = TextEditingController();
  final phone = TextEditingController();
  final otp = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final vehicle = TextEditingController();
  final number = TextEditingController();
  final fare = TextEditingController(text: '300');
  final seats = TextEditingController(text: '3');

  DateTime departure = DateTime.now().add(const Duration(days: 1));
  List<Map<String, dynamic>> rides = [];
  String message = '';
  String selectedRole = 'passenger';
  bool loading = false;
  bool photoUploading = false;
  String? avatarUrl;
  int tab = 0;
  int authMethod = 0;

  SupabaseClient? get db =>
      widget.configured ? Supabase.instance.client : null;


  Future<void> _registerGuest() async {
    if (name.text.trim().isEmpty ||
        phone.text.trim().replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
      setState(() => message = 'Enter your name and a valid mobile number.');
      return;
    }
    if (!widget.configured || db == null) {
      setState(() => message = 'Tip Car server setup is not connected yet.');
      return;
    }

    setState(() { loading = true; message = ''; });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Please allow location permission to continue.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final fullName = name.text.trim();
      final mobile = phone.text.trim();
      final response = await db!.auth.signInAnonymously(data: {
        'full_name': fullName,
        'role': selectedRole,
        'phone': mobile,
        'last_latitude': position.latitude,
        'last_longitude': position.longitude,
      });
      final user = response.user ?? db!.auth.currentUser;
      if (user == null) throw Exception('Could not create your Tip Car account.');
      await db!.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName,
        'role': selectedRole,
        'phone': mobile,
      }, onConflict: 'id');
      await _loadAvatar();
      if (mounted) {
        setState(() {
          message = 'Welcome to Tip Car!';
          tab = 0;
        });
      }
    } catch (error) {
      if (mounted) setState(() => message = 'Registration failed: $error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _buildRegistrationScreen() => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TipCarBrand(),
                  const SizedBox(height: 18),
                  const Text('Welcome to Tip Car',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: tipCarNavy)),
                  const SizedBox(height: 6),
                  const Text('Enter your details and allow location to get started.',
                    style: TextStyle(color: Color(0xff718096))),
                  const SizedBox(height: 18),
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Mobile number'),
                  ),
                  const SizedBox(height: 14),
                  const Text('I want to use Tip Car as'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'passenger', label: Text('Passenger'), icon: Icon(Icons.person_outline)),
                      ButtonSegment(value: 'driver', label: Text('Driver'), icon: Icon(Icons.directions_car_outlined)),
                    ],
                    selected: {selectedRole},
                    onSelectionChanged: (selection) => setState(() => selectedRole = selection.first),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: loading ? null : _registerGuest,
                    icon: loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location),
                    label: Text(loading ? 'Please wait...' : 'Allow Location & Continue'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tipCarNavy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('No OTP, email or password required. Your mobile number is not verified.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xff718096))),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(message, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _loadAvatar() async {
    if (!widget.configured || db!.auth.currentUser == null) return;
    try {
      final row = await db!.from('profiles').select('avatar_url')
          .eq('id', db!.auth.currentUser!.id).maybeSingle();
      if (mounted) setState(() => avatarUrl = row?['avatar_url']?.toString());
    } catch (_) {
      // Profile image is optional; do not block the rest of the app.
    }
  }

  Future<void> _uploadDriverPhoto() async {
    final user = db?.auth.currentUser;
    if (user == null) {
      setState(() => message = 'Please sign in before uploading your driver photo.');
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (picked == null) return;
      setState(() { photoUploading = true; message = ''; });
      final extension = picked.path.split('.').last.toLowerCase();
      final safeExtension = ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ? extension : 'jpg';
      final contentType = safeExtension == 'png' ? 'image/png' : (safeExtension == 'webp' ? 'image/webp' : 'image/jpeg');
      final path = '${user.id}/avatar.$safeExtension';
      await db!.storage.from('driver-avatars').upload(
        path,
        File(picked.path),
        fileOptions: FileOptions(
          upsert: true,
          contentType: contentType,
          cacheControl: '3600',
        ),
      );
      final url = '${db!.storage.from('driver-avatars').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await db!.from('profiles').update({'avatar_url': url}).eq('id', user.id);
      if (mounted) {
        setState(() {
          avatarUrl = url;
          message = 'Profile photo uploaded successfully.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => message = 'Photo upload failed: $error');
    } finally {
      if (mounted) setState(() => photoUploading = false);
    }
  }

  Future<void> _ensureProfile(dynamic user) async {
    final metadata = user.userMetadata as Map<String, dynamic>? ?? {};
    final metadataRole = metadata['role'];
    final role = metadataRole == 'driver' ? 'driver' : selectedRole;
    final fullName = name.text.trim().isNotEmpty
        ? name.text.trim()
        : (metadata['full_name'] as String? ?? '');
    final profile = <String, dynamic>{
      'id': user.id,
      'full_name': fullName,
      'role': role,
    };
    final phoneNumber = user.phone as String?;
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      profile['phone'] = phoneNumber;
    }

    // Do not overwrite an existing driver's role every time they sign in.
    await db!.from('profiles').upsert(
      profile,
      onConflict: 'id',
      ignoreDuplicates: true,
    );
  }

  Future<void> sendOtp() async {
    if (phone.text.trim().isEmpty) {
      setState(() => message = 'Enter your mobile number with country code.');
      return;
    }
    try {
      await db!.auth.signInWithOtp(phone: phone.text.trim());
      if (mounted) setState(() => message = 'OTP sent by SMS.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> verifyOtp() async {
    if (otp.text.trim().isEmpty) {
      setState(() => message = 'Enter the SMS OTP.');
      return;
    }
    try {
      await db!.auth.verifyOTP(
        phone: phone.text.trim(),
        token: otp.text.trim(),
        type: OtpType.sms,
      );
      final user = db!.auth.currentUser;
      if (user != null) {
        await _ensureProfile(user);
      }
      await _loadAvatar();
      if (mounted) setState(() => message = 'Signed in with phone.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> sendEmailOtp() async {
    if (email.text.trim().isEmpty) {
      setState(() => message = 'Enter your email address.');
      return;
    }
    try {
      await db!.auth.signInWithOtp(
        email: email.text.trim(),
        shouldCreateUser: false,
      );
      if (mounted) setState(() => message = 'Email login code sent. Check your inbox and spam folder.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> verifyEmailOtp() async {
    if (email.text.trim().isEmpty || otp.text.trim().isEmpty) {
      setState(() => message = 'Enter your email address and the code from your email.');
      return;
    }
    try {
      await db!.auth.verifyOTP(
        email: email.text.trim(),
        token: otp.text.trim(),
        type: OtpType.email,
      );
      final user = db!.auth.currentUser;
      if (user != null) await _ensureProfile(user);
      await _loadAvatar();
      if (mounted) setState(() => message = 'Signed in with email code.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> signInWithEmail() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => message = 'Enter your email and password.');
      return;
    }
    try {
      await db!.auth.signInWithPassword(
        email: email.text.trim(),
        password: password.text,
      );
      final user = db!.auth.currentUser;
      if (user != null) await _ensureProfile(user);
      await _loadAvatar();
      if (mounted) setState(() => message = 'Signed in with email and password.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> sendLinkedEmailCode() async {
    if (email.text.trim().isEmpty) {
      setState(() => message = 'Enter the email address you want to add.');
      return;
    }
    try {
      await db!.auth.updateUser(UserAttributes(email: email.text.trim()));
      if (mounted) setState(() => message = 'Verification code sent to the new email. Your current sign-in stays active until verification.');
    } catch (error) {
      if (mounted) setState(() => message = 'Could not add email: $error');
    }
  }

  Future<void> sendLinkedPhoneCode() async {
    if (phone.text.trim().isEmpty) {
      setState(() => message = 'Enter the mobile number with country code.');
      return;
    }
    try {
      await db!.auth.updateUser(UserAttributes(phone: phone.text.trim()));
      if (mounted) setState(() => message = 'SMS verification code sent to the new number.');
    } catch (error) {
      if (mounted) setState(() => message = 'Could not add phone: $error');
    }
  }

  Future<void> verifyLinkedEmailCode() async {
    if (email.text.trim().isEmpty || otp.text.trim().isEmpty) {
      setState(() => message = 'Enter the new email and its verification code.');
      return;
    }
    try {
      await db!.auth.verifyOTP(
        email: email.text.trim(),
        token: otp.text.trim(),
        type: OtpType.emailChange,
      );
      await _loadAvatar();
      if (mounted) setState(() => message = 'Email verified and added to this Tip Car account.');
    } catch (error) {
      if (mounted) setState(() => message = 'Email verification failed: $error');
    }
  }

  Future<void> verifyLinkedPhoneCode() async {
    if (phone.text.trim().isEmpty || otp.text.trim().isEmpty) {
      setState(() => message = 'Enter the new mobile number and its SMS code.');
      return;
    }
    try {
      await db!.auth.verifyOTP(
        phone: phone.text.trim(),
        token: otp.text.trim(),
        type: OtpType.phoneChange,
      );
      await _loadAvatar();
      if (mounted) setState(() => message = 'Phone verified and added to this Tip Car account.');
    } catch (error) {
      if (mounted) setState(() => message = 'Phone verification failed: $error');
    }
  }

  Future<void> createEmailAccount() async {
    if (name.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        password.text.length < 6) {
      setState(() => message =
          'Enter your name, email and a password of at least 6 characters.');
      return;
    }
    try {
      final response = await db!.auth.signUp(
        email: email.text.trim(),
        password: password.text,
        data: {
          'full_name': name.text.trim(),
          'role': selectedRole,
        },
      );
      if (response.user != null && response.session != null) {
        await _ensureProfile(response.user);
        await _loadAvatar();
      }
      if (!mounted) return;
      setState(() => message = response.session == null
          ? 'Account created. Confirm your email, then sign in.'
          : 'Account created and signed in.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> search() async {
    if (from.text.trim().isEmpty || to.text.trim().isEmpty) {
      setState(() => message = 'Enter both starting point and destination.');
      return;
    }
    setState(() {
      loading = true;
      message = '';
    });
    try {
      final result = await db!
          .from('rides')
          .select()
          .inFilter('status', ['active', 'full'])
          .ilike('origin', '%${from.text.trim()}%')
          .ilike('destination', '%${to.text.trim()}%')
          .gte('departure_at', DateTime.now().toUtc().toIso8601String())
          .order('departure_at');
      final rideRows = List<Map<String, dynamic>>.from(result);
      final driverIds = rideRows.map((ride) => ride['driver_id']?.toString()).whereType<String>().toSet().toList();
      final publicDrivers = driverIds.isEmpty ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(await db!.rpc('search_driver_public_profiles', params: {'p_driver_ids': driverIds}));
      final driversById = {for (final driver in publicDrivers) driver['id'].toString(): driver};
      for (final ride in rideRows) { ride['driver_public_profile'] = driversById[ride['driver_id']?.toString()] ?? <String, dynamic>{}; }
      if (mounted) { setState(() => rides = rideRows); }
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> publish() async {
    if (db?.auth.currentUser == null) {
      setState(() => message = 'Please sign in first.');
      return;
    }
    final totalSeats = int.tryParse(seats.text);
    final farePerSeat = double.tryParse(fare.text);
    if (vehicle.text.trim().isEmpty ||
        number.text.trim().isEmpty ||
        from.text.trim().isEmpty ||
        to.text.trim().isEmpty ||
        totalSeats == null ||
        totalSeats < 1 ||
        totalSeats > 60 ||
        farePerSeat == null ||
        farePerSeat < 0) {
      setState(() => message = 'Check vehicle, route, seat and fare details.');
      return;
    }

    try {
      final profile = await db!
          .from('profiles')
          .select('role')
          .eq('id', db!.auth.currentUser!.id)
          .single();
      if (!['driver', 'admin'].contains(profile['role'])) {
        setState(() => message =
            'Your account is a passenger. Create or use a driver account to publish a ride.');
        return;
      }
      await db!.from('rides').insert({
        'driver_id': db!.auth.currentUser!.id,
        'vehicle_type': 'car',
        'vehicle_name': vehicle.text.trim(),
        'vehicle_number': number.text.trim(),
        'origin': from.text.trim(),
        'destination': to.text.trim(),
        'departure_at': departure.toUtc().toIso8601String(),
        'total_seats': totalSeats,
        'available_seats': totalSeats,
        'fare_per_seat': farePerSeat,
      });
      if (mounted) setState(() => message = 'Ride published.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  Future<void> book(Map<String, dynamic> ride) async {
    final rideId = ride['id'] as String;
    final availableSeats = (ride['available_seats'] as num?)?.toInt() ?? 0;
    if (availableSeats < 1) {
      setState(() => message = 'Sorry, all seats on this ride are booked.');
      return;
    }
    final vpa = TextEditingController();
    int selectedSeats = 1;
    String method = 'cash';
    final farePerSeat = (num.tryParse(ride['fare_per_seat'].toString()) ?? 0).toDouble();    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Book your seats'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$availableSeats seat(s) available', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
                const SizedBox(height: 10),
                const Text('How many seats do you need?'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: selectedSeats > 1 ? () => setDialogState(() => selectedSeats--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$selectedSeats', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: selectedSeats < availableSeats ? () => setDialogState(() => selectedSeats++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Text('Total fare: ₹${(farePerSeat * selectedSeats).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                const Divider(height: 22),
                RadioGroup<String>(
                  groupValue: method,
                  onChanged: (value) {
                    if (value != null) setDialogState(() => method = value);
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const RadioListTile<String>(value: 'cash', title: Text('Cash to driver'), contentPadding: EdgeInsets.zero),
                    const RadioListTile<String>(value: 'upi', title: Text('UPI app'), contentPadding: EdgeInsets.zero),
                  ]),
                ),
                if (method == 'upi') ...[
                  TextField(
                    controller: vpa,
                    decoration: const InputDecoration(labelText: 'Tip Car UPI ID (VPA)', hintText: 'yourname@bank'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'UPI intent opens your payment app. Payment remains unverified until a gateway/merchant confirmation is connected.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
          ],
        ),
      ),
    );
    if (choice != true) {
      vpa.dispose();
      return;
    }
    if (method == 'upi' &&
        !RegExp(r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$').hasMatch(vpa.text.trim())) {
      vpa.dispose();
      if (mounted) setState(() => message = 'Enter a valid Tip Car UPI ID before continuing.');
      return;
    }
    try {
      // The database RPC locks the ride row and rechecks remaining seats,
      // so two passengers cannot reserve the same final seat simultaneously.
      final bookingId = await db!.rpc(
        'create_booking',
        params: {'p_ride_id': rideId, 'p_seats': selectedSeats},
      ) as String;
      await db!.rpc('set_my_booking_payment_method', params: {
        'p_booking_id': bookingId,
        'p_method': method,
      });
      if (method == 'upi') {
        final amount = (farePerSeat * selectedSeats).toStringAsFixed(2);
        final uri = Uri(
          scheme: 'upi',
          path: 'pay',
          queryParameters: {
            'pa': vpa.text.trim(),
            'pn': 'Tip Car',
            'am': amount,
            'cu': 'INR',
            'tn': 'Tip Car booking $bookingId',
          },
        );
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          setState(() => message = opened
              ? 'UPI app opened for $selectedSeats seat(s), total ₹$amount. Payment is NOT verified or marked paid.'
              : 'Booking saved, but no UPI app could open. Payment is still unpaid.');
        }
      } else if (mounted) {
        setState(() => message =
            '$selectedSeats seat(s) requested. Total ₹${(farePerSeat * selectedSeats).toStringAsFixed(2)}. Pay the driver directly; booking is pending confirmation.');
      }
      await search();
    } catch (error) {
      if (mounted) setState(() => message = 'Booking failed: $error. Please refresh seats and try again.');
      await search();
    } finally {
      vpa.dispose();
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    phone.dispose();
    otp.dispose();
    name.dispose();
    email.dispose();
    password.dispose();
    vehicle.dispose();
    number.dispose();
    fare.dispose();
    seats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const TipCarBrand(compact: true),
          actions: [
            if (db?.auth.currentUser != null)
              IconButton(
                tooltip: 'Sign out',
                onPressed: () async {
                  await db!.auth.signOut();
                  if (mounted) {
                    setState(() {
                      message = 'Signed out.';
                      tab = 0;
                    });
                  }
                },
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
        body: !widget.configured
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Tip Car setup is incomplete. Please configure the Supabase connection.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : db!.auth.currentUser == null
                ? _buildRegistrationScreen()
                : IndexedStack(
                    index: tab,
                    children: [
                      _buildHomeTab(),
                      _buildRidesTab(),
                      const BookingHistoryScreen(),
                      _buildProfileTab(),
                    ],
                  ),
        bottomNavigationBar: widget.configured && db!.auth.currentUser != null
            ? NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (index) => setState(() {
                  tab = index;
                  message = '';
                }),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Rides'),
                  NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'My Rides'),
                  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
                ],
              )
            : null,
      );

  Widget _buildHomeTab() {
    final signedIn = db?.auth.currentUser != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff0b1530), Color(0xff174d91), Color(0xff15b5b3)],
            ),
            boxShadow: const [BoxShadow(color: Color(0x24102a56), blurRadius: 22, offset: Offset(0, 10))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 25),
                ),
                const SizedBox(width: 10),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TIP CAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
                  Text('SHARE THE RIDE. SAVE THE JOURNEY.', style: TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: .7)),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(30)),
                  child: const Row(children: [Icon(Icons.verified_user_outlined, color: Colors.white, size: 14), SizedBox(width: 5), Text('Travel together', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))]),
                ),
              ]),
              const SizedBox(height: 25),
              Text(signedIn ? 'Ready for your\nnext journey?' : 'Your journey,\nmade easier.', style: const TextStyle(color: Colors.white, fontSize: 30, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -.6)),
              const SizedBox(height: 9),
              const Text('Find a seat. Share your route. Go further together.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 20),
              Row(children: [
                _heroPill(Icons.people_alt_outlined, 'Shared rides'),
                const SizedBox(width: 8),
                _heroPill(Icons.savings_outlined, 'Save money'),
                const SizedBox(width: 8),
                _heroPill(Icons.route_rounded, 'Your route'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Text('Where are you going?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xff0b1530)))),
          TextButton.icon(onPressed: _showRolePicker, icon: const Icon(Icons.swap_horiz, size: 17), label: Text(selectedRole == 'driver' ? 'Driver' : 'Passenger')),
        ]),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xffe5eaf2))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  const SizedBox(height: 15, child: Icon(Icons.radio_button_checked, color: Color(0xff15b5b3), size: 17)),
                  Container(width: 2, height: 38, color: const Color(0xffd5deea)),
                  const SizedBox(height: 15, child: Icon(Icons.location_on, color: Color(0xffffb02e), size: 19)),
                ]),
                const SizedBox(width: 12),
                Expanded(child: Column(children: [
                  TextField(controller: from, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Pickup location', hintText: 'Where from?', isDense: true, border: InputBorder.none)),
                  const Divider(height: 1),
                  TextField(controller: to, textInputAction: TextInputAction.search, onSubmitted: (_) => search(), decoration: const InputDecoration(labelText: 'Destination', hintText: 'Where to?', isDense: true, border: InputBorder.none)),
                ])),
              ]),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, height: 52, child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xffffb02e), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: () { setState(() { selectedRole = 'passenger'; tab = 1; }); search(); },
                icon: const Icon(Icons.search_rounded), label: const Text('SEARCH RIDES', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
              )),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Explore Tip Car', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff0b1530))),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: _featureTile(Icons.search_rounded, 'Find a ride', 'Travel your way', const Color(0xffeaf2ff), const Color(0xff174d91), () { setState(() { selectedRole = 'passenger'; tab = 1; }); })),
          const SizedBox(width: 10),
          Expanded(child: _featureTile(Icons.add_road_rounded, 'Offer a ride', 'Share empty seats', const Color(0xfffff1e5), const Color(0xffd97706), () { setState(() { selectedRole = 'driver'; tab = 1; }); })),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _featureTile(Icons.receipt_long_rounded, 'My bookings', 'Your trip activity', const Color(0xffe8f7f0), const Color(0xff15b5b3), () => setState(() => tab = 2))),
          const SizedBox(width: 10),
          Expanded(
            child: _featureTile(
              Icons.emoji_events_rounded,
              'Driver benefits',
              'Rewards & progress',
              const Color(0xfff2edff),
              const Color(0xff7052a3),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverBenefitsScreen(configured: widget.configured),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xff0b1530), borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const Icon(Icons.shield_moon_outlined, color: Color(0xffffb45f), size: 30),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('A smarter way to travel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              SizedBox(height: 3),
              Text('Connect with people going your way.', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 15),
          ]),
        ),
        if (message.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(message, style: const TextStyle(color: Colors.blue))),
      ],
    );
  }

  Widget _heroPill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 13), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))]),
  );

  Widget _featureTile(IconData icon, String title, String subtitle, Color bg, Color fg, VoidCallback onTap) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xffe5eaf2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: fg, size: 21)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xff0b1530))),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: Color(0xff718096))),
        ]),
      ),
    ),
  );

  Future<void> _showRolePicker() async {
    final role = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Use Tip Car as', style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Passenger'), onTap: () => Navigator.pop(context, 'passenger')),
            ListTile(leading: const Icon(Icons.directions_car_outlined), title: const Text('Driver'), onTap: () => Navigator.pop(context, 'driver')),
          ],
        ),
      ),
    );
    if (role != null && mounted) {
      setState(() {
        selectedRole = role;
        tab = 1;
        message = 'Mode changed to ${role == 'driver' ? 'Driver' : 'Passenger'}. Your account permissions still follow your saved profile role.';
      });
    }
  }

  Widget _buildRidesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: const LinearGradient(
              colors: [Color(0xff0b1530), Color(0xff15b5b3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selectedRole == 'driver' ? 'Driver dashboard' : 'Find your next ride',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text(selectedRole == 'driver'
                ? 'Share your journey and manage your ride details.'
                : 'Find a seat and travel together for less.',
                style: const TextStyle(color: Colors.white70, height: 1.35)),
            ])),
            const SizedBox(width: 10),
            const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 38),
          ]),
        ),        const SizedBox(height: 18),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Find rides'), icon: Icon(Icons.search)),
            ButtonSegment(value: 1, label: Text('Publish ride'), icon: Icon(Icons.add_road)),
          ],
          selected: {tab == 1 && selectedRole == 'driver' ? 1 : 0},
          onSelectionChanged: (selection) => setState(() {
            selectedRole = selection.first == 1 ? 'driver' : 'passenger';
            message = '';
          }),
        ),
        const SizedBox(height: 12),
        if (selectedRole == 'passenger') ..._buildRideSearch(),
        if (selectedRole == 'driver') ..._buildPublishRide(),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(message, style: const TextStyle(color: Colors.blue)),
          ),
      ],
    );
  }

  Widget _buildProfileTab() {
    final user = db?.auth.currentUser;
    final metadata = user?.userMetadata ?? <String, dynamic>{};
    final profileName = (metadata['full_name'] ?? '').toString().trim();
    final profilePhone = (metadata['phone'] ?? '').toString().trim();
    final accountLabel = profileName.isNotEmpty ? profileName : 'Tip Car member';
    final phoneLabel = profilePhone.isNotEmpty ? profilePhone : 'Mobile number not added';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: const LinearGradient(
              colors: [Color(0xff0b1530), Color(0xff15b5b3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 29,
              backgroundColor: Colors.white.withValues(alpha: .16),
              backgroundImage: (avatarUrl?.isNotEmpty ?? false) ? NetworkImage(avatarUrl!) : null,
              child: (avatarUrl?.isNotEmpty ?? false) ? null : const Icon(Icons.person_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your Tip Car account', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(accountLabel, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 7),
              InkWell(onTap: photoUploading ? null : _uploadDriverPhoto, child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(photoUploading ? Icons.hourglass_top : Icons.add_a_photo_outlined, color: Colors.white, size: 15),
                const SizedBox(width: 6),
                Text(photoUploading ? 'Uploading photo...' : 'Add / change profile photo', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ])),
            ])),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xffeaf1ff), child: Icon(Icons.badge_outlined, color: Color(0xff15b5b3))),
            title: Text(accountLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${selectedRole == 'driver' ? 'Driver' : 'Passenger'} - $phoneLabel'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Driver Benefits'),
            subtitle: const Text('View driver rewards and eligibility details'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DriverBenefitsScreen(configured: widget.configured),
            )),
          ),
        ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(message, style: const TextStyle(color: Colors.blue)),
          ),
      ],
    );
  }

  List<Widget> _buildRideSearch() => [
        TextField(
          controller: from,
          decoration: const InputDecoration(labelText: 'From'),
        ),
        TextField(
          controller: to,
          decoration: const InputDecoration(labelText: 'To'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: loading ? null : search,
          child: const Text('Search rides'),
        ),
        if (loading) const Center(child: CircularProgressIndicator()),
        ...rides.map((ride) {
          final driver = ride['driver_public_profile'] is Map ? Map<String, dynamic>.from(ride['driver_public_profile'] as Map) : <String, dynamic>{};
          final photoUrl = driver['avatar_url']?.toString() ?? '';
          final driverName = driver['full_name']?.toString().trim();
          return Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${ride['origin']} → ${ride['destination']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 7),
            Text('${ride['vehicle_name']} · ${ride['vehicle_number']}'),
            Row(children: [const Icon(Icons.event_seat_outlined, size: 18, color: Colors.green), const SizedBox(width: 6), Text('${ride['available_seats']} of ${ride['total_seats']} seats available', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green))]),
            Text(DateFormat.yMMMd().add_jm().format(DateTime.parse(ride['departure_at']).toLocal())),
            const Divider(height: 20),
            Row(children: [CircleAvatar(radius: 23, backgroundColor: const Color(0xffeaf1ff), backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(Icons.person, color: Color(0xff15b5b3)) : null), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text((driverName == null || driverName.isEmpty) ? 'Tip Car driver' : driverName, style: const TextStyle(fontWeight: FontWeight.w700)), const Text('Driver profile', style: TextStyle(fontSize: 12, color: Colors.blueGrey))])), Text('₹${ride['fare_per_seat']}', style: const TextStyle(fontWeight: FontWeight.w800))]),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: ((ride['available_seats'] as num?)?.toInt() ?? 0) > 0 ? () => book(ride) : null, child: Text(((ride['available_seats'] as num?)?.toInt() ?? 0) > 0 ? 'Select seats & book' : 'Sold out'))),
          ])));
        })
      ];

  List<Widget> _buildPublishRide() => [
        TextField(
          controller: vehicle,
          decoration: const InputDecoration(labelText: 'Vehicle name'),
        ),
        TextField(
          controller: number,
          decoration: const InputDecoration(labelText: 'Vehicle number'),
        ),
        TextField(
          controller: fare,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Fare per seat (₹)'),
        ),
        TextField(
          controller: seats,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Total seats'),
        ),
        ListTile(
          title: Text(
            'Departure: ${DateFormat.yMMMd().add_jm().format(departure)}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: departure,
              );
              if (date != null && mounted) {
                setState(
                  () => departure = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    departure.hour,
                    departure.minute,
                  ),
                );
              }
            },
          ),
        ),
        FilledButton(
          onPressed: publish,
          child: const Text('Publish ride'),
        ),
      ];
}