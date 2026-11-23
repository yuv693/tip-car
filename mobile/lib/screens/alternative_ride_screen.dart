import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Passenger-controlled fallback: search existing scheduled rides to the same
/// destination and let the passenger explicitly choose whether to book.
class AlternativeRideScreen extends StatefulWidget {
  final String pickup;
  final String destination;
  final String? instantRequestId;
  const AlternativeRideScreen({
    super.key,
    required this.pickup,
    required this.destination,
    this.instantRequestId,
  });

  @override
  State<AlternativeRideScreen> createState() => _AlternativeRideScreenState();
}

class _AlternativeRideScreenState extends State<AlternativeRideScreen> {
  final _db = Supabase.instance.client;
  late final TextEditingController _from;
  late final TextEditingController _to;
  List<Map<String, dynamic>> _rides = [];
  bool _loading = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _from = TextEditingController(text: widget.pickup);
    _to = TextEditingController(text: widget.destination);
    _search();
  }

  Future<void> _search() async {
    if (_to.text.trim().isEmpty) {
      setState(() => _message = 'Enter your destination to search alternative rides.');
      return;
    }
    setState(() { _loading = true; _message = ''; _rides = []; });
    try {
      var query = _db.from('rides').select()
          .eq('status', 'active')
          .ilike('destination', '%${_to.text.trim()}%')
          .gt('available_seats', 0)
          .gte('departure_at', DateTime.now().toUtc().toIso8601String());
      final origin = _from.text.trim();
      if (origin.isNotEmpty &&
          origin.toLowerCase() != 'my current location' &&
          origin.toLowerCase() != 'current location') {
        query = query.ilike('origin', '%$origin%');
      }
      final rows = await query.order('departure_at').limit(30);
      if (!mounted) return;
      setState(() {
        _rides = List<Map<String, dynamic>>.from(rows);
        if (_rides.isEmpty) {
          _message = 'No matching scheduled rides are available right now. Try a nearby pickup point or check again later. Tip Car has not confirmed an alternative vehicle.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not search alternative rides: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _book(Map<String, dynamic> ride) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      setState(() => _message = 'Please sign in before booking.');
      return;
    }
    final seats = (ride['available_seats'] as num?)?.toInt() ?? 0;
    if (seats < 1) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Book this alternative ride?'),
        content: Text(
          '${ride['origin']} → ${ride['destination']}\n'
          '${ride['vehicle_name']} · ${ride['vehicle_type']}\n'
          'One seat · ₹${ride['fare_per_seat']}\n\n'
          'Payment is not collected in Tip Car. Pay the driver directly.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm booking')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final bookingId = await _db.rpc('create_booking', params: {
        'p_ride_id': ride['id'],
        'p_seats': 1,
      }) as String;
      await _db.rpc('set_my_booking_payment_method', params: {
        'p_booking_id': bookingId,
        'p_method': 'cash',
      });
      final requestId = widget.instantRequestId;
      if (requestId != null) {
        await _db.from('ride_requests').update({
          'status': 'cancelled',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', requestId).eq('passenger_id', user.id).eq('status', 'searching');
      }
      if (!mounted) return;
      setState(() => _message = 'Alternative ride booking created. Pay the driver directly; the driver must confirm the booking.');
      await _search();
    } catch (e) {
      if (mounted) setState(() => _message = 'Booking failed: $e. Refresh and try again.');
      await _search();
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find an alternative ride')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'We will look for scheduled rides going to your destination. You choose and confirm any ride; nothing is booked automatically.',
          style: TextStyle(color: Colors.blueGrey),
        ),
        const SizedBox(height: 12),
        TextField(controller: _from, decoration: const InputDecoration(labelText: 'Pickup / nearby town')),
        TextField(controller: _to, decoration: const InputDecoration(labelText: 'Destination')),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _loading ? null : _search,
          icon: const Icon(Icons.search),
          label: Text(_loading ? 'Searching…' : 'Search scheduled rides'),
        ),
        if (_loading) const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        ..._rides.map((ride) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ride['origin']} → ${ride['destination']}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 5),
              Text('${ride['vehicle_type']} · ${ride['vehicle_name']} · ${ride['vehicle_number']}'),
              Text('${ride['available_seats']} seats available · ₹${ride['fare_per_seat']} per seat'),
              Text('Departure: ${DateTime.parse(ride['departure_at']).toLocal()}'),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: () => _book(ride),
                child: const Text('Choose this ride'),
              )),
            ]),
          ),
        )),
        if (_message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message, style: const TextStyle(color: Colors.blueGrey)),
          ),
      ],
    ),
  );
}
