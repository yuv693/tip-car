import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'live_ride_map_screen.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  bool loading = true;
  String notice = '';
  List<Map<String, dynamic>> bookings = [];

  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; notice = ''; });
    try {
      final rows = await db
          .from('bookings')
          .select('id, ride_id, passenger_id, seats, total_amount, status, payment_status, created_at, rides(origin, destination, departure_at, vehicle_name, driver_id)')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => bookings = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) setState(() => notice = 'Could not load bookings: $error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _act(Map<String, dynamic> booking, String action) async {
    try {
      if (action == 'cancel') {
        await db.rpc('cancel_my_booking', params: {'p_booking_id': booking['id']});
      } else if (action == 'complete') {
        await db.rpc('driver_complete_booking', params: {'p_booking_id': booking['id']});
      } else {
        await db.rpc('driver_respond_booking', params: {
          'p_booking_id': booking['id'],
          'p_decision': action,
        });
      }
      if (!mounted) return;
      setState(() => notice = action == 'confirmed'
          ? 'Booking confirmed.'
          : action == 'complete'
              ? 'Ride marked completed. ₹20 Tip Car commission is now due.'
              : 'Booking updated.');
      await _load();
    } catch (error) {
      if (mounted) setState(() => notice = 'Action failed: $error');
    }
  }

  Future<void> _showDriverContact(Map<String, dynamic> booking) async {
    try {
      final rows = await db.rpc('get_confirmed_ride_driver_contact', params: {'p_ride_id': booking['ride_id']});
      if (!mounted) return;
      final contacts = List<Map<String, dynamic>>.from(rows);
      if (contacts.isEmpty) {
        setState(() => notice = 'Driver contact is available only after booking confirmation.');
        return;
      }
      final driver = contacts.first;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Driver contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 30, backgroundImage: (driver['avatar_url']?.toString().isNotEmpty ?? false) ? NetworkImage(driver['avatar_url'].toString()) : null, child: (driver['avatar_url']?.toString().isNotEmpty ?? false) ? null : const Icon(Icons.person, size: 30)),
          const SizedBox(height: 12),
          Text(driver['full_name']?.toString().isNotEmpty == true ? driver['full_name'].toString() : 'Tip Car driver', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SelectableText(driver['phone']?.toString().isNotEmpty == true ? driver['phone'].toString() : 'Phone number not added'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } catch (error) {
      if (mounted) setState(() => notice = 'Could not load driver contact: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = db.auth.currentUser?.id;
    return Scaffold(
      backgroundColor: const Color(0xfff4f7fc),
      appBar: AppBar(
        backgroundColor: const Color(0xfff4f7fc),
        elevation: 0,
        title: const Text('My journeys', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xff10234f))),
        actions: [
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Color(0xff10234f), Color(0xff246bfe)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your trips, all in one place',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                              SizedBox(height: 6),
                              Text('Track bookings, confirm requests and follow your ride.',
                                style: TextStyle(color: Colors.white70, height: 1.35)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 27,
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          child: const Icon(Icons.route_rounded, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),
                  if (notice.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(notice, style: const TextStyle(color: Colors.blue)),
                    ),
                  if (bookings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text('No bookings yet. Your passenger requests and driver bookings will appear here.'),
                    ),
                  ...bookings.map((booking) {
                    final ride = booking['rides'] is Map
                        ? Map<String, dynamic>.from(booking['rides'] as Map)
                        : <String, dynamic>{};
                    final isDriver = ride['driver_id'] == userId;
                    final status = booking['status']?.toString() ?? 'unknown';
                    final departure = DateTime.tryParse(ride['departure_at']?.toString() ?? '');
                    final route = '${ride['origin'] ?? 'Route'} → ${ride['destination'] ?? ''}';
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xffe8edf5)),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(route, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                Chip(
                                  label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                                  backgroundColor: status == 'confirmed' ? const Color(0xffe8f8ef) : const Color(0xffeef3ff),
                                  side: BorderSide.none,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('${ride['vehicle_name'] ?? 'Vehicle'} · ${booking['seats']} seat(s)'),
                            if (departure != null)
                              Text(DateFormat.yMMMd().add_jm().format(departure.toLocal())),
                            Text('Total: ₹${booking['total_amount']} · Payment: ${booking['payment_status']}'),
                            const SizedBox(height: 8),
                            if (!isDriver && status == 'confirmed')
                              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                                onPressed: () => _showDriverContact(booking),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Driver details & phone'),
                              )),
                            if (status == 'confirmed')
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => LiveRideMapScreen(
                                        rideId: booking['ride_id'].toString(),
                                        isDriver: isDriver,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.map_outlined),
                                  label: const Text('Live ride map'),
                                ),
                              ),
                            if (isDriver && status == 'confirmed')
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _act(booking, 'complete'),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Mark ride completed'),
                                ),
                              ),
                            if (isDriver && status == 'pending')
                              Row(
                                children: [
                                  Expanded(child: OutlinedButton(
                                    onPressed: () => _act(booking, 'cancelled'),
                                    child: const Text('Decline'),
                                  )),
                                  const SizedBox(width: 8),
                                  Expanded(child: FilledButton(
                                    onPressed: () => _act(booking, 'confirmed'),
                                    child: const Text('Confirm booking'),
                                  )),
                                ],
                              )
                            else if (!isDriver && booking['passenger_id'] == userId && (status == 'pending' || status == 'confirmed'))
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => _act(booking, 'cancel'),
                                  child: const Text('Cancel booking'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Cash/UPI fare collection is not verified in Tip Car yet. Driver commission is ₹20 per completed passenger booking; outstanding commission blocks new bookings until an admin verifies payment.',
                      style: TextStyle(fontSize: 12, color: Color(0xff718096)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
