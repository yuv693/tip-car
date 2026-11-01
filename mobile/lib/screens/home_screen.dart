import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_benefits_screen.dart';

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
  int tab = 0;
  int authMethod = 0;

  SupabaseClient? get db =>
      widget.configured ? Supabase.instance.client : null;

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
      if (user != null) await _ensureProfile(user);
      if (mounted) setState(() => message = 'Signed in with phone.');
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
      if (mounted) setState(() => message = 'Signed in with email.');
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
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
      if (mounted) {
        setState(() => rides = List<Map<String, dynamic>>.from(result));
      }
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

  Future<void> book(String rideId) async {
    try {
      await db!.rpc(
        'create_booking',
        params: {'p_ride_id': rideId, 'p_seats': 1},
      );
      if (mounted) {
        setState(() => message =
            'Booking request created. Payment has not been collected.');
      }
      await search();
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
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
          title: const Text('🚗 TIP CAR'),
          actions: [
            if (db?.auth.currentUser != null)
              IconButton(
                tooltip: 'Sign out',
                onPressed: () async {
                  await db!.auth.signOut();
                  if (mounted) setState(() => message = 'Signed out.');
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
                    'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY using --dart-define, then run again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Color(0xff092b66), Color(0xff075de8)],
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RIDE SHARING MADE SIMPLE',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Every journey starts together.',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                          ),
                        ),
                        Text(
                          'Find a seat. Share a ride.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xffe8f0ff),
                        child: Icon(
                          Icons.emoji_events_outlined,
                          color: Color(0xff075de8),
                        ),
                      ),
                      title: const Text(
                        'Driver Benefits',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        '₹20 per new passenger · Insurance reward at 1,000 rides',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DriverBenefitsScreen(
                            configured: widget.configured,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (db!.auth.currentSession == null) _buildAuthCard(),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Find rides')),
                      ButtonSegment(value: 1, label: Text('Publish ride')),
                    ],
                    selected: {tab},
                    onSelectionChanged: (selection) =>
                        setState(() => tab = selection.first),
                  ),
                  const SizedBox(height: 12),
                  if (tab == 0) ..._buildRideSearch(),
                  if (tab == 1) ..._buildPublishRide(),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ),
                ],
              ),
      );

  Widget _buildAuthCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Join Tip Car',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 10),
              const Text('I want to use Tip Car as'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'passenger',
                    label: Text('Passenger'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: 'driver',
                    label: Text('Driver'),
                    icon: Icon(Icons.directions_car_outlined),
                  ),
                ],
                selected: {selectedRole},
                onSelectionChanged: (selection) =>
                    setState(() => selectedRole = selection.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Phone OTP')),
                  ButtonSegment(value: 1, label: Text('Email')),
                ],
                selected: {authMethod},
                onSelectionChanged: (selection) =>
                    setState(() => authMethod = selection.first),
              ),
              const SizedBox(height: 10),
              if (authMethod == 0) ...[
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number with country code',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: sendOtp,
                  child: const Text('Send OTP'),
                ),
                TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'SMS OTP'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: verifyOtp,
                  child: const Text('Verify OTP'),
                ),
              ] else ...[
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (minimum 6 characters)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: signInWithEmail,
                  child: const Text('Sign in with email'),
                ),
                OutlinedButton(
                  onPressed: createEmailAccount,
                  child: const Text('Create email account'),
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                'Existing accounts keep their saved role. The selected role is used only when a new profile is created.',
                style: TextStyle(fontSize: 11, color: Color(0xff718096)),
              ),
            ],
          ),
        ),
      );

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
        ...rides.map(
          (ride) => Card(
            child: ListTile(
              leading: const Icon(Icons.directions_car),
              title: Text('${ride['origin']} → ${ride['destination']}'),
              subtitle: Text(
                '${ride['vehicle_name']} · ${ride['available_seats']} seats · '
                '${DateFormat.yMMMd().add_jm().format(DateTime.parse(ride['departure_at']).toLocal())}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('₹${ride['fare_per_seat']}'),
                  TextButton(
                    onPressed: () => book(ride['id'] as String),
                    child: const Text('Book'),
                  ),
                ],
              ),
            ),
          ),
        ),
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
