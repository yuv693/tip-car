import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const ink = Color(0xff090f20);
const panel = Color(0xff141e34);
const muted = Color(0xff9aa8c2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const TipCarOwnerApp());
}

class TipCarOwnerApp extends StatelessWidget {
  const TipCarOwnerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tip Car Owner',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: ink, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff5478ff), brightness: Brightness.dark), appBarTheme: const AppBarTheme(backgroundColor: ink, foregroundColor: Colors.white, elevation: 0)),
    home: const OwnerGate(),
  );
}

class OwnerGate extends StatefulWidget {
  const OwnerGate({super.key});
  @override
  State<OwnerGate> createState() => _OwnerGateState();
}

class _OwnerGateState extends State<OwnerGate> {
  final code = TextEditingController();
  bool busy = false, checking = true, activated = false;
  String error = '';
  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() { super.initState(); _start(); }

  Future<void> _start() async {
    try {
      if (db.auth.currentUser == null) await db.auth.signInAnonymously();
      final user = db.auth.currentUser;
      if (user == null) throw Exception('Owner session could not start.');
      final row = await db.from('profiles').select('role').eq('id', user.id).maybeSingle();
      if (mounted && row?['role'] == 'admin') setState(() => activated = true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _activate() async {
    if (code.text.trim().isEmpty) { setState(() => error = 'Please enter your owner activation code.'); return; }
    setState(() { busy = true; error = ''; });
    try {
      final user = db.auth.currentUser;
      if (user == null) throw Exception('Owner session expired. Reopen the app.');
      await db.from('profiles').upsert({'id': user.id, 'full_name': 'Tip Car Owner', 'role': 'passenger'}, onConflict: 'id');
      await db.rpc('claim_tipcar_owner', params: {'p_activation_code': code.text.trim()});
      if (mounted) setState(() => activated = true);
    } catch (e) {
      if (mounted) setState(() => error = 'Activation failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (activated) return const OwnerDashboard();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff172747), ink, Color(0xff070b16)])),
        child: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: checking
            ? const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 18), Text('Preparing secure owner access...')])
            : Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(color: panel.withValues(alpha: .94), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: .09)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 30, offset: const Offset(0, 14))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const CircleAvatar(radius: 34, backgroundColor: Color(0xff243c72), child: Icon(Icons.admin_panel_settings_rounded, size: 36, color: Colors.white)),
                const SizedBox(height: 18),
                const Text('TIP CAR', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff91aaff), fontWeight: FontWeight.w800, letterSpacing: 3)),
                const SizedBox(height: 6),
                const Text('Owner Access', textAlign: TextAlign.center, style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text('Sign in to your private management dashboard. This app is separate from the Customer and Driver app.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.5)),
                const SizedBox(height: 24),
                TextField(controller: code, obscureText: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Owner activation code', prefixIcon: const Icon(Icons.key_rounded), filled: true, fillColor: ink, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: .12))))),
                const SizedBox(height: 16),
                SizedBox(height: 52, child: FilledButton(onPressed: busy ? null : _activate, style: FilledButton.styleFrom(backgroundColor: const Color(0xff5478ff), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ACTIVATE OWNER APP', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .6)))),
                if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error, style: const TextStyle(color: Color(0xffff8585), fontSize: 12))),
              ]),
            ),
        )))),
      ),
    );
  }
}

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});
  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final search = TextEditingController();
  List<Map<String, dynamic>> drivers = [];
  bool busy = false;
  String error = '';
  int onlineDrivers = 0, completedRides = 0;
  double commissionTotal = 0;
  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { busy = true; error = ''; });
    try {
      final results = await Future.wait([
        db.from('profiles').select('id,full_name,phone,avatar_url,emergency_contact_phone,created_at').eq('role', 'driver').order('created_at', ascending: false),
        db.from('rides').select('id,status').eq('status', 'completed'),
        db.from('ride_requests').select('id,status').eq('status', 'completed'),
        db.from('driver_commissions').select('amount,status').neq('status', 'reversed'),
      ]);
      final list = List<Map<String, dynamic>>.from(results[0] as List);
      final ridesCount = (results[1] as List).length + (results[2] as List).length;
      final commissions = List<Map<String, dynamic>>.from(results[3] as List);
      final total = commissions.fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
      var online = 0;
      if (list.isNotEmpty) {
        final ids = list.map((e) => e['id'].toString()).toList();
        final presence = await db.from('driver_presence').select('driver_id,vehicle_type,vehicle_name,vehicle_number,online').inFilter('driver_id', ids);
        final byId = {for (final p in List<Map<String,dynamic>>.from(presence)) p['driver_id'].toString(): p};
        for (final d in list) {
          d['presence'] = byId[d['id'].toString()];
          if ((d['presence'] as Map<String,dynamic>?)?['online'] == true) online++;
        }
      }
      if (mounted) setState(() { drivers = list; onlineDrivers = online; completedRides = ridesCount; commissionTotal = total; });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load dashboard data: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _edit(Map<String,dynamic> d) async {
    final p = d['presence'] as Map<String,dynamic>?;
    final name = TextEditingController(text: d['full_name']?.toString() ?? '');
    final phone = TextEditingController(text: d['phone']?.toString() ?? '');
    final emergency = TextEditingController(text: d['emergency_contact_phone']?.toString() ?? '');
    final vehicle = TextEditingController(text: p?['vehicle_name']?.toString() ?? '');
    final number = TextEditingController(text: p?['vehicle_number']?.toString() ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit driver details'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Driver name')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'Mobile number'), keyboardType: TextInputType.phone),
        TextField(controller: emergency, decoration: const InputDecoration(labelText: 'Emergency contact'), keyboardType: TextInputType.phone),
        TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'Vehicle name / model')),
        TextField(controller: number, decoration: const InputDecoration(labelText: 'Vehicle registration')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Save changes'))],
    ));
    if (ok != true) return;
    try {
      await db.from('profiles').update({'full_name':name.text.trim(),'phone':phone.text.trim(),'emergency_contact_phone':emergency.text.trim()}).eq('id',d['id']);
      if (p != null) await db.from('driver_presence').update({'vehicle_name':vehicle.text.trim(),'vehicle_number':number.text.trim()}).eq('driver_id',d['id']);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver details updated.')));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.trim().toLowerCase();
    final shown = drivers.where((d) => ('${d['full_name']} ${d['phone']}').toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.directions_car_filled_rounded, color: Color(0xff89a5ff)), SizedBox(width: 10), Text('TIP CAR OWNER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.2))]),
        actions: [IconButton(onPressed: busy ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh dashboard'), const SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: const Color(0xff5478ff),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff294a91), Color(0xff172849), Color(0xff111b30)]), border: Border.all(color: Colors.white.withValues(alpha: .1))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('OVERVIEW', style: TextStyle(color: Color(0xffb9caff), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
                const SizedBox(height: 9),
                const Text('Good to see you, Owner', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Your Tip Car business at a glance.', style: TextStyle(color: Color(0xffc0cce2))),
                const SizedBox(height: 18),
                Row(children: [
                  const Icon(Icons.shield_moon_rounded, size: 17, color: Color(0xff9db5ff)),
                  const SizedBox(width: 7),
                  const Text('Private management panel', style: TextStyle(color: Color(0xffdce5ff), fontSize: 12)),
                  const Spacer(),
                  if (busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ]),
            ),
            const SizedBox(height: 22),
            const Text('BUSINESS INSIGHTS', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.42,
              children: [
                _StatCard(title: 'Total Drivers', value: '${drivers.length}', change: 'Registered on Tip Car', icon: Icons.groups_rounded, colors: const [Color(0xff3568df), Color(0xff233d82)]),
                _StatCard(title: 'Online Drivers', value: '$onlineDrivers', change: 'Available right now', icon: Icons.wifi_tethering_rounded, colors: const [Color(0xff159b81), Color(0xff126657)]),
                _StatCard(title: 'Completed Rides', value: '$completedRides', change: 'Successfully completed', icon: Icons.route_rounded, colors: const [Color(0xff9a61db), Color(0xff613b9c)]),
                _StatCard(title: 'Commission', value: '₹${commissionTotal.toStringAsFixed(0)}', change: 'Net recorded · ₹20 per ride', icon: Icons.account_balance_wallet_rounded, colors: const [Color(0xffd18a35), Color(0xff89521e)]),
              ],
            ),
            if (error.isNotEmpty) Container(margin: const EdgeInsets.only(top: 14), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xff4a2028), borderRadius: BorderRadius.circular(14)), child: Text(error, style: const TextStyle(color: Color(0xffffb5b5), fontSize: 12))),
            const SizedBox(height: 26),
            Row(children: [
              const Expanded(child: Text('Driver management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xff1b2944), borderRadius: BorderRadius.circular(20)), child: Text('${drivers.length} drivers', style: const TextStyle(color: Color(0xffb8c9f2), fontSize: 11, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: search, onChanged: (_) => setState((){}), decoration: InputDecoration(hintText: 'Search by driver name or phone', prefixIcon: const Icon(Icons.search_rounded), filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: .06))))),
            const SizedBox(height: 12),
            if (shown.isEmpty && !busy) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18)), child: const Column(children: [Icon(Icons.person_search_rounded, size: 34, color: muted), SizedBox(height: 10), Text('No drivers found', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 4), Text('Registered drivers will appear here.', style: TextStyle(color: muted, fontSize: 12))])),
            ...shown.map((d) => _DriverTile(driver: d, onEdit: () => _edit(d))),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.change, required this.icon, required this.colors});
  final String title, value, change;
  final IconData icon;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .94, end: 1), duration: const Duration(milliseconds: 420), curve: Curves.easeOutBack,
    builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors), borderRadius: BorderRadius.circular(21), boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .24), blurRadius: 16, offset: const Offset(0, 8))], border: Border.all(color: Colors.white.withValues(alpha: .13))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))), Icon(icon, color: Colors.white.withValues(alpha: .92), size: 21)]),
        const Spacer(),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.8))),
        const SizedBox(height: 4),
        Text(change, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .76), fontSize: 9.5)),
      ]),
    ),
  );
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.driver, required this.onEdit});
  final Map<String,dynamic> driver;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final p = driver['presence'] as Map<String,dynamic>?;
    final online = p?['online'] == true;
    final avatar = (driver['avatar_url'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: CircleAvatar(radius: 23, backgroundColor: const Color(0xff293958), backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null, child: avatar.startsWith('http') ? null : const Icon(Icons.person_rounded, color: Colors.white70)),
        title: Text((driver['full_name'] ?? 'Driver').toString().trim().isEmpty ? 'Driver' : driver['full_name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text('${driver['phone'] ?? 'No mobile'}  ·  ${p?['vehicle_name'] ?? 'Vehicle not added'}', maxLines: 2, style: const TextStyle(color: muted, fontSize: 11))),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? const Color(0xff36d6a0) : Colors.grey, shape: BoxShape.circle)),
          const SizedBox(height: 4),
          Text(online ? 'ONLINE' : 'OFFLINE', style: TextStyle(color: online ? const Color(0xff53d9ad) : muted, fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          IconButton(visualDensity: VisualDensity.compact, onPressed: onEdit, icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xff9db5ff)), tooltip: 'Edit driver'),
        ]),
      ),
    );
  }
}
