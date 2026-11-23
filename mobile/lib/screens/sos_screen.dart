import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _contact = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _message = '';

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return;
      final row = await _db.from('profiles')
          .select('emergency_contact_phone')
          .eq('id', user.id).maybeSingle();
      _contact.text = row?['emergency_contact_phone']?.toString() ?? '';
    } catch (e) {
      _message = 'Could not load emergency contact: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveContact() async {
    final value = _contact.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10 || digits.length > 15) {
      setState(() => _message = 'Enter a valid emergency contact number.');
      return;
    }
    setState(() { _saving = true; _message = ''; });
    try {
      await _db.from('profiles').update({
        'emergency_contact_phone': value,
      }).eq('id', _db.auth.currentUser!.id);
      if (mounted) setState(() => _message = 'Emergency contact saved.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not save contact: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _message = 'Could not open phone dialer.');
    }
  }

  Future<void> _messageContact() async {
    final number = _contact.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) {
      setState(() => _message = 'Save an emergency contact number first.');
      return;
    }
    var body = 'I need help. Please contact me.';
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      if (await Geolocator.isLocationServiceEnabled()) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
        body += ' My location: https://maps.google.com/?q=${p.latitude},${p.longitude}';
      }
    } catch (_) {
      body += ' Location is unavailable.';
    }
    final uri = Uri(scheme: 'sms', path: number, queryParameters: {'body': body});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _message = 'Could not open SMS app. Call the contact instead.');
    }
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SOS Emergency Help')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xffffeeee),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.sos_rounded, color: Colors.red, size: 42),
            SizedBox(height: 8),
            Text('Need urgent help?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 5),
            Text('For immediate danger in India, call 112. Tip Car does not automatically dispatch police or ambulance.'),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _call('112'),
            icon: const Icon(Icons.call),
            label: const Text('CALL INDIA EMERGENCY 112'),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Your emergency contact', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 8),
        TextField(
          controller: _contact,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Contact mobile number',
            hintText: '98765 43210',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loading || _saving ? null : _saveContact,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save emergency contact'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _loading ? null : _messageContact,
          icon: const Icon(Icons.sms_outlined),
          label: const Text('Send SOS SMS with location'),
        ),
        OutlinedButton.icon(
          onPressed: _contact.text.trim().isEmpty ? null : () => _call(_contact.text.trim()),
          icon: const Icon(Icons.call_outlined),
          label: const Text('Call emergency contact'),
        ),
        if (_message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message, style: const TextStyle(color: Colors.blueGrey)),
          ),
        const SizedBox(height: 12),
        const Text('SMS is opened for your review; Tip Car does not send it silently. GPS permission is requested only when you choose the SOS SMS action.',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ],
    ),
  );
}
