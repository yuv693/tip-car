import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  final db = Supabase.instance.client;
  final search = TextEditingController();
  bool loading = true;
  String notice = '';
  List<Map<String, dynamic>> drivers = [];
  List<Map<String, dynamic>> presences = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; notice = ''; });
    try {
      final user = db.auth.currentUser;
      if (user == null) throw Exception('Owner sign-in required.');
      final me = await db.from('profiles').select('role').eq('id', user.id).single();
      if (me['role'] != 'admin') throw Exception('This account is not enabled as Tip Car owner.');
      final rows = await db.from('profiles')
          .select('id,full_name,phone,avatar_url,emergency_contact_phone,created_at')
          .eq('role', 'driver').order('created_at', ascending: false);
      final ids = List<Map<String, dynamic>>.from(rows)
          .map((e) => e['id'].toString()).toList();
      final presenceRows = ids.isEmpty ? <Map<String, dynamic>>[] :
          List<Map<String, dynamic>>.from(await db.from('driver_presence')
              .select('driver_id,vehicle_type,vehicle_name,vehicle_number,online,updated_at')
              .inFilter('driver_id', ids));
      if (!mounted) return;
      setState(() {
        drivers = List<Map<String, dynamic>>.from(rows);
        presences = presenceRows;
      });
    } catch (e) {
      if (mounted) setState(() => notice = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> _presence(String id) {
    for (final row in presences) {
      if (row['driver_id'].toString() == id) return row;
    }
    return <String, dynamic>{};
  }

  Future<void> _edit(Map<String, dynamic> driver) async {
    final id = driver['id'].toString();
    final current = _presence(id);
    final name = TextEditingController(text: driver['full_name']?.toString() ?? '');
    final phone = TextEditingController(text: driver['phone']?.toString() ?? '');
    final emergency = TextEditingController(text: driver['emergency_contact_phone']?.toString() ?? '');
    final avatar = TextEditingController(text: driver['avatar_url']?.toString() ?? '');
    final vehicle = TextEditingController(text: current['vehicle_name']?.toString() ?? '');
    final number = TextEditingController(text: current['vehicle_number']?.toString() ?? '');
    String type = current['vehicle_type']?.toString() ?? 'car';
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit driver details'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Driver name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null),
          TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
          TextFormField(controller: emergency, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Emergency contact')),
          TextFormField(controller: avatar, decoration: const InputDecoration(labelText: 'Profile photo URL')),
          const Divider(height: 26),
          DropdownButtonFormField<String>(value: type, decoration: const InputDecoration(labelText: 'Vehicle type'), items: const [
            DropdownMenuItem(value: 'bike', child: Text('Bike')),
            DropdownMenuItem(value: 'car', child: Text('Car')),
            DropdownMenuItem(value: 'bus', child: Text('Bus')),
          ], onChanged: (v) { if (v != null) type = v; }),
          TextFormField(controller: vehicle, decoration: const InputDecoration(labelText: 'Vehicle name / model')),
          TextFormField(controller: number, decoration: const InputDecoration(labelText: 'Vehicle registration number')),
          if (current.isEmpty) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Vehicle fields will be saved once this driver has an online/presence record.', style: TextStyle(fontSize: 12))),
        ]),
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, formKey.currentState?.validate() == true), child: const Text('Save changes')),
      ],
    ));
    if (save != true) return;
    try {
      await db.from('profiles').update({
        'full_name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'emergency_contact_phone': emergency.text.trim().isEmpty ? null : emergency.text.trim(),
        'avatar_url': avatar.text.trim().isEmpty ? null : avatar.text.trim(),
      }).eq('id', id);
      if (current.isNotEmpty) {
        await db.from('driver_presence').update({
          'vehicle_type': type,
          'vehicle_name': vehicle.text.trim(),
          'vehicle_number': number.text.trim(),
        }).eq('driver_id', id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver details updated.')));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      name.dispose(); phone.dispose(); emergency.dispose(); avatar.dispose(); vehicle.dispose(); number.dispose();
    }
  }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final filtered = drivers.where((d) {
      final q = search.text.trim().toLowerCase();
      return q.isEmpty || ['full_name','phone'].any((k) => (d[k] ?? '').toString().toLowerCase().contains(q));
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tip Car Owner Dashboard'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Icon(Icons.admin_panel_settings, size: 34),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Driver management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('${drivers.length} registered drivers'),
            ])),
          ]))),
          TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search driver name or phone')),
          const SizedBox(height: 12),
          if (notice.isNotEmpty) Text(notice, style: const TextStyle(color: Colors.red)),
          if (filtered.isEmpty && notice.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No driver profiles found.')),
          ...filtered.map((d) {
            final p = _presence(d['id'].toString());
            final photo = d['avatar_url']?.toString() ?? '';
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null, child: photo.isEmpty ? const Icon(Icons.person) : null),
              title: Text(d['full_name']?.toString() ?? 'Driver', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${d['phone'] ?? 'No phone'}\n${p['vehicle_name'] ?? 'Vehicle not set'} · ${p['vehicle_number'] ?? 'No registration'} · ${p['online'] == true ? 'Online' : 'Offline'}'),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(d)),
              onTap: () => _edit(d),
            ));
          }),
        ],
      ),
    );
  }
}
