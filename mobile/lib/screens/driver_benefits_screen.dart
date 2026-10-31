import 'package:flutter/material.dart';

class DriverBenefitsScreen extends StatefulWidget {
  const DriverBenefitsScreen({super.key});

  @override
  State<DriverBenefitsScreen> createState() => _DriverBenefitsScreenState();
}

class _DriverBenefitsScreenState extends State<DriverBenefitsScreen> {
  final from = TextEditingController(text: 'Porbandar');
  final to = TextEditingController();
  int availableSeats = 2;

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
                Row(children: const [
                  CircleAvatar(backgroundColor: Color(0xffe8f0ff), child: Icon(Icons.shield_outlined, color: blue)),
                  SizedBox(width: 12),
                  Expanded(child: Text('Complete 1,000 rides', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  Text('0 / 1,000', style: TextStyle(color: blue, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 16),
                ClipRRect(borderRadius: BorderRadius.circular(20), child: const LinearProgressIndicator(value: 0, minHeight: 10, backgroundColor: Color(0xffe8edf6), color: blue)),
                const SizedBox(height: 12),
                const Text('Reach 1,000 eligible completed rides to qualify for the Tip Car car-insurance reward. Policy, vehicle checks and coverage terms will apply.', style: TextStyle(color: Color(0xff64718a), height: 1.45)),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('ROUTE SEAT MATCH'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Going somewhere? Find passengers travelling your way.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 14),
                TextField(controller: from, decoration: const InputDecoration(labelText: 'Starting point', prefixIcon: Icon(Icons.trip_origin), filled: true)),
                const SizedBox(height: 10),
                TextField(controller: to, decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.location_on_outlined), filled: true)),
                const SizedBox(height: 10),
                Row(children: [
                  const Expanded(child: Text('Empty seats available', style: TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => setState(() => availableSeats = (availableSeats - 1).clamp(1, 8)), icon: const Icon(Icons.remove_circle_outline)),
                  Text('$availableSeats', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => setState(() => availableSeats = (availableSeats + 1).clamp(1, 8)), icon: const Icon(Icons.add_circle_outline)),
                ]),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route matching will activate when the booking backend is connected.'))),
                    icon: const Icon(Icons.groups_2_outlined),
                    label: const Text('Find passengers on my route'),
                    style: FilledButton.styleFrom(backgroundColor: blue, padding: const EdgeInsets.symmetric(vertical: 15)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('SIMPLE COMMISSION'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Row(children: [
                CircleAvatar(backgroundColor: Color(0xffe8f8ef), child: Icon(Icons.currency_rupee, color: Color(0xff16834a))),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('₹20 per new passenger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  SizedBox(height: 4),
                  Text('Charged once for each successful new passenger booking. Cancelled bookings are not charged.', style: TextStyle(color: Color(0xff64718a), height: 1.4)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Preview screen: ride totals, commission collection and insurance eligibility will show verified account data after the backend rules are connected.', style: TextStyle(color: Color(0xff7b879b), fontSize: 12, height: 1.45)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(value, style: const TextStyle(color: Color(0xff77849a), fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
  );
}
