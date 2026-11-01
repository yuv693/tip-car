import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
            : IndexedStack(
                index: tab,
                children: [
                  _buildHomeTab(),
                  _buildRidesTab(),
                  const BookingHistoryScreen(),
                  _buildProfileTab(),
                ],
              ),
        bottomNavigationBar: widget.configured
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
              colors: [Color(0xff102a56), Color(0xff174d91), Color(0xff087b78)],
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
          const Expanded(child: Text('Where are you going?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xff102a56)))),
          TextButton.icon(onPressed: _showRolePicker, icon: const Icon(Icons.swap_horiz, size: 17), label: Text(selectedRole == 'driver' ? 'Driver' : 'Passenger')),
        ]),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xffe8edf4))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  const SizedBox(height: 15, child: Icon(Icons.radio_button_checked, color: Color(0xff138a50), size: 17)),
                  Container(width: 2, height: 38, color: const Color(0xffd5deea)),
                  const SizedBox(height: 15, child: Icon(Icons.location_on, color: Color(0xfff28c28), size: 19)),
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
                style: FilledButton.styleFrom(backgroundColor: const Color(0xfff28c28), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: () { setState(() { selectedRole = 'passenger'; tab = 1; }); search(); },
                icon: const Icon(Icons.search_rounded), label: const Text('SEARCH RIDES', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
              )),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Explore Tip Car', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff102a56))),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: _featureTile(Icons.search_rounded, 'Find a ride', 'Travel your way', const Color(0xffeaf2ff), const Color(0xff174d91), () { setState(() { selectedRole = 'passenger'; tab = 1; }); })),
          const SizedBox(width: 10),
          Expanded(child: _featureTile(Icons.add_road_rounded, 'Offer a ride', 'Share empty seats', const Color(0xfffff1e5), const Color(0xffd97706), () { setState(() { selectedRole = 'driver'; tab = 1; }); })),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _featureTile(Icons.receipt_long_rounded, 'My bookings', 'Your trip activity', const Color(0xffe8f7f0), const Color(0xff138a50), () => setState(() => tab = 2))),
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
          decoration: BoxDecoration(color: const Color(0xff102a56), borderRadius: BorderRadius.circular(20)),
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xffe8edf4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: fg, size: 21)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xff102a56))),
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
              colors: [Color(0xff102a56), Color(0xff246bfe)],
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
        ),
        const SizedBox(height: 18),
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
    final accountLabel = user?.email ?? user?.phone ?? 'Guest account';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: const LinearGradient(
              colors: [Color(0xff102a56), Color(0xff087b78)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 29,
              backgroundColor: Colors.white.withValues(alpha: .16),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your Tip Car account', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(accountLabel, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xffeaf1ff), child: Icon(Icons.badge_outlined, color: Color(0xff246bfe))),
            title: Text(accountLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Account mode: ${selectedRole == 'driver' ? 'Driver' : 'Passenger'}'),
          ),
        ),
        if (user == null) _buildAuthCard(),
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
