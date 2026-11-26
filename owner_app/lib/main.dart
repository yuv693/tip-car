import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

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
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0b1530)), scaffoldBackgroundColor: const Color(0xfff4f6fa)),
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
  bool busy = false;
  bool activated = false;
  String error = '';
  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (db.auth.currentUser == null) await db.auth.signInAnonymously();
      final user = db.auth.currentUser;
      if (user == null) throw Exception('Owner session could not start.');
      final row = await db.from('profiles').select('role').eq('id', user.id).maybeSingle();
      if (mounted && row?['role'] == 'admin') setState(() => activated = true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _activate() async {
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
      appBar: AppBar(title: const Text('Tip Car Owner')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Card(
        margin: const EdgeInsets.all(20), child: Padding(padding: const EdgeInsets.all(22), child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.admin_panel_settings_rounded, size: 54, color: Color(0xff0b1530)),
            const SizedBox(height: 12),
            const Text('Private Owner Access', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enter your one-time owner activation code. This app is separate from the Customer and Driver app.', textAlign: TextAlign.center),
            const SizedBox(height: 18),
            TextField(controller: code, obscureText: true, decoration: const InputDecoration(labelText: 'Owner activation code', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : _activate, child: Text(busy ? 'Checking...' : 'Activate Owner App')),
            if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error, style: const TextStyle(color: Colors.red))),
          ],
        )),
      ))),
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
  SupabaseClient get db => Supabase.instance.client;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { busy = true; error = ''; });
    try {
      final rows = await db.from('profiles').select('id,full_name,phone,avatar_url,emergency_contact_phone,created_at').eq('role', 'driver').order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isNotEmpty) {
        final ids = list.map((e) => e['id'].toString()).toList();
        final presence = await db.from('driver_presence').select('driver_id,vehicle_type,vehicle_name,vehicle_number,online').inFilter('driver_id', ids);
        final byId = {for (final p in List<Map<String,dynamic>>.from(presence)) p['driver_id'].toString(): p};
        for (final d in list) { d['presence'] = byId[d['id'].toString()]; }
      }
      if (mounted) setState(() => drivers = list);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
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
      title: const Text('Update driver details'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Driver name')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'Mobile number'), keyboardType: TextInputType.phone),
        TextField(controller: emergency, decoration: const InputDecoration(labelText: 'Emergency contact'), keyboardType: TextInputType.phone),
        TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'Vehicle name / model')),
        TextField(controller: number, decoration: const InputDecoration(labelText: 'Vehicle registration')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Save'))],
    ));
    if (ok != true) return;
    try {
      await db.from('profiles').update({'full_name':name.text.trim(),'phone':phone.text.trim(),'emergency_contact_phone':emergency.text.trim()}).eq('id',d['id']);
      if (p != null) {
        await db.from('driver_presence').update({'vehicle_name':vehicle.text.trim(),'vehicle_number':number.text.trim()}).eq('driver_id',d['id']);
      }
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver details updated.')));
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.toLowerCase();
    final shown = drivers.where((d) => ('${d['full_name']} ${d['phone']}').toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tip Car Owner Dashboard'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: search, onChanged: (_) => setState((){}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search driver by name or phone'))),
        Padding(padding: const EdgeInsets.symmetric(horizontal:16), child: Row(children: [Text('Registered drivers: ${drivers.length}', style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), if(busy) const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))])),
        if(error.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(error,style:const TextStyle(color:Colors.red))),
        Expanded(child: RefreshIndicator(onRefresh:_load, child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: shown.length, itemBuilder:(ctx,i) {
          final d=shown[i]; final p=d['presence'] as Map<String,dynamic>?;
          return Card(child: ListTile(
            leading: CircleAvatar(backgroundImage: (d['avatar_url']??'').toString().startsWith('http') ? NetworkImage(d['avatar_url']) : null, child: (d['avatar_url']??'').toString().isEmpty ? const Icon(Icons.person) : null),
            title: Text(d['full_name']?.toString().isNotEmpty==true ? d['full_name'] : 'Driver'),
            subtitle: Text('${d['phone']??'No mobile'} • ${p?['vehicle_name']??'Vehicle not added'} • ${p?['online']==true?'Online':'Offline'}'),
            trailing: IconButton(onPressed:()=>_edit(d),icon:const Icon(Icons.edit_outlined)),
          ));
        }))),
      ]),
    );
  }
}
