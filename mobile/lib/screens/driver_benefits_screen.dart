import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverBenefitsScreen extends StatefulWidget {
  final bool configured;
  const DriverBenefitsScreen({super.key, required this.configured});

  @override
  State<DriverBenefitsScreen> createState() => _DriverBenefitsScreenState();
}

class _DriverBenefitsScreenState extends State<DriverBenefitsScreen> {
  final from = TextEditingController(text: 'Porbandar');
  final to = TextEditingController();
  int availableSeats = 2;
  int completedRides = 0;
  double commissionTotal = 0;
  int commissionBookings = 0;
  bool insuranceEligible = false;
  bool loading = false;
  String notice = '';
  List<Map<String, dynamic>> matches = [];

  @override
  void initState() {
    super.initState();
    _loadBenefits();
  }

  Future<void> _loadBenefits() async {
    if (!widget.configured || Supabase.instance.client.auth.currentUser == null) return;
    try {
      final rows = await Supabase.instance.client.rpc('get_my_driver_benefits');
      if (!mounted || (rows as List).isEmpty) return;
      final row = Map<String, dynamic>.from(rows.first as Map);
      setState(() {
        completedRides = (row['completed_rides'] as num?)?.toInt() ?? 0;
        insuranceEligible = row['insurance_eligible'] == true;
        commissionTotal = (row['commission_total'] as num?)?.toDouble() ?? 0;
        commissionBookings = (row['commission_bookings'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) setState(() => notice = 'Benefits data is not available yet. Apply the driver-benefits SQL migration in Supabase.');
    }
  }

  Future<void> _findMatches() async {
    if (!widget.configured || Supabase.instance.client.auth.currentUser == null) {
      setState(() => notice = 'Please sign in to search route matches.');
      return;
    }
    if (from.text.trim().isEmpty || to.text.trim().isEmpty) {
      setState(() => notice = 'Enter both starting point and destination.');
      return;
    }
    setState(() { loading = true; notice = ''; matches = []; });
    try {
      final rows = await Supabase.instance.client.rpc('find_route_matches', params: {
        'p_origin': from.text.trim(),
        'p_destination': to.text.trim(),
        'p_min_seats': availableSeats,
      });
      if (!mounted) return;
      setState(() => matches = List<Map<String, dynamic>>.from(rows as List));
      if (matches.isEmpty) setState(() => notice = 'No exact-route rides with available seats were found.');
    } catch (e) {
      if (mounted) setState(() => notice = 'Route matching is not ready. Apply the driver-benefits SQL migration in Supabase.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xff10234f);
    const blue = Color(0xff246bfe);
    return Scaffold(
      backgroundColor: const Color(0xfff4f7fc),
      appBar: AppBar(
        title: const Text('Driver benefits', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xfff4f7fc),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [navy, blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 34),
              SizedBox(height: 14),
              Text('Drive more. Earn more. Get rewarded.', style: TextStyle(color: Colors.white, fontSize: 23, height: 1.15, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Text('Tip Car rewards drivers for every successful passenger booking.', style: TextStyle(color: Colors.white70, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 18),
          _sectionTitle('YOUR INSURANCE REWARD'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const CircleAvatar(backgroundColor: Color(0xffe8f0ff), child: Icon(Icons.shield_outlined, color: blue)),
                  SizedBox(width: 12),
                  Expanded(child: Text('Complete 1,000 rides', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  Text('$completedRides / 1,000', style: TextStyle(color: blue, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 16),
                ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: (completedRides / 1000).clamp(0.0, 1.0).toDouble(), minHeight: 10, backgroundColor: const Color(0xffe8edf6), color: blue)),
                const SizedBox(height: 12),
                Text(insuranceEligible ? 'Congratulations! You have reached the 1,000 completed-ride milestone. Insurance verification and policy terms still apply.' : 'Reach 1,000 eligible completed rides to qualify for the Tip Car car-insurance reward. Current progress: $completedRides rides. Policy, vehicle checks and coverage terms will apply.', style: const TextStyle(color: Color(0xff64718a), height: 1.45)),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('ROUTE RIDE MATCH'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Search active rides on your exact route and require enough seats for your passengers.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 14),
                TextField(controller: from, decoration: const InputDecoration(labelText: 'Starting point', prefixIcon: Icon(Icons.trip_origin), filled: true)),
                const SizedBox(height: 10),
                TextField(controller: to, decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.location_on_outlined), filled: true)),
                const SizedBox(height: 10),
                Row(children: [
                  const Expanded(child: Text('Minimum seats needed', style: TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => setState(() => availableSeats = (availableSeats - 1).clamp(1, 8).toInt()), icon: const Icon(Icons.remove_circle_outline)),
                  Text('$availableSeats', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => setState(() => availableSeats = (availableSeats + 1).clamp(1, 8).toInt()), icon: const Icon(Icons.add_circle_outline)),
                ]),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : _findMatches,
                    icon: const Icon(Icons.groups_2_outlined),
                    label: Text(loading ? 'Searching…' : 'Find matching rides'),
                    style: FilledButton.styleFrom(backgroundColor: blue, padding: const EdgeInsets.symmetric(vertical: 15)),
                  ),
                ),
              ]),
            ),
          ),
          if (matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...matches.map((m) => Card(elevation: 0, child: ListTile(leading: const Icon(Icons.directions_car_filled_outlined), title: Text('${m['origin']} → ${m['destination']}'), subtitle: Text('${m['vehicle_name']} · ${m['available_seats']} seats available · ₹${m['fare_per_seat']} per seat'),))),
          ],
          if (notice.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(notice, style: const TextStyle(color: Color(0xffa45a00)))),
          const SizedBox(height: 18),
          _sectionTitle('SIMPLE COMMISSION'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                CircleAvatar(backgroundColor: Color(0xffe8f8ef), child: Icon(Icons.currency_rupee, color: Color(0xff16834a))),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('₹20 per new passenger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  SizedBox(height: 4),
                  Text('₹20 becomes due only after the driver marks a confirmed passenger booking as completed. Cancelled bookings do not incur commission.', style: TextStyle(color: Color(0xff64718a), height: 1.4)),
                  SizedBox(height: 8),
                  Text('Commission due: ₹$commissionTotal · $commissionBookings completed bookings', style: TextStyle(color: Color(0xff16834a), fontWeight: FontWeight.w700)),
                ])),
              ]),
            ),
          ),
          if (commissionTotal > 0)
            Card(
              color: const Color(0xfffff4e5),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Your driver account is locked for new customer bookings while commission is due. Pay Tip Car using the official payment instructions and contact an admin for verification. Your account unlocks only after the admin marks the payment verified. Do not treat a UPI screenshot or app-opening as payment confirmation.', style: TextStyle(color: Color(0xff8a4b08), height: 1.45, fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 14),
          const Text('Route matching currently checks exact starting point and destination. Insurance reward requires verification of completed rides, vehicle and policy terms.', style: TextStyle(color: Color(0xff7b879b), fontSize: 12, height: 1.45)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(value, style: const TextStyle(color: Color(0xff77849a), fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
  );
}
