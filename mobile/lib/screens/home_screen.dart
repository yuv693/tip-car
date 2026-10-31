import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final bool configured;
  const HomeScreen({super.key, required this.configured});
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final from=TextEditingController(text:'Porbandar'), to=TextEditingController();
  final phone=TextEditingController(), otp=TextEditingController(), name=TextEditingController();
  final vehicle=TextEditingController(), number=TextEditingController(), fare=TextEditingController(text:'300'), seats=TextEditingController(text:'3');
  DateTime departure=DateTime.now().add(const Duration(days:1));
  List<Map<String,dynamic>> rides=[]; String message=''; bool loading=false; int tab=0;
  SupabaseClient? get db=>widget.configured?Supabase.instance.client:null;
  Future<void> sendOtp() async {if(db==null){setState(()=>message='Configure Supabase keys to enable login.');return;}try{await db!.auth.signInWithOtp(phone:phone.text.trim());setState(()=>message='OTP sent by SMS.');}catch(e){setState(()=>message=e.toString());}}
  Future<void> verifyOtp() async {try{await db!.auth.verifyOTP(phone:phone.text.trim(),token:otp.text.trim(),type:OtpType.sms);final u=db!.auth.currentUser;if(u!=null){await db!.from('profiles').upsert({'id':u.id,'phone':u.phone,'full_name':name.text.trim(),'role':'passenger'});}setState(()=>message='Signed in');}catch(e){setState(()=>message=e.toString());}}
  Future<void> search() async {if(db==null)return;setState(()=>loading=true);try{final result=await db!.from('rides').select().inFilter('status',['active','full']).ilike('origin','%${from.text.trim()}%').ilike('destination','%${to.text.trim()}%').gte('departure_at',DateTime.now().toUtc().toIso8601String()).order('departure_at');setState(()=>rides=List<Map<String,dynamic>>.from(result));}catch(e){setState(()=>message=e.toString());}finally{setState(()=>loading=false);}}
  Future<void> publish() async {if(db?.auth.currentUser==null){setState(()=>message='Please login first.');return;}try{final p=await db!.from('profiles').select('role').eq('id',db!.auth.currentUser!.id).single();if(!['driver','admin'].contains(p['role'])){setState(()=>message='Set your role to driver in your profile.');return;}await db!.from('rides').insert({'driver_id':db!.auth.currentUser!.id,'vehicle_type':'car','vehicle_name':vehicle.text.trim(),'vehicle_number':number.text.trim(),'origin':from.text.trim(),'destination':to.text.trim(),'departure_at':departure.toUtc().toIso8601String(),'total_seats':int.parse(seats.text),'available_seats':int.parse(seats.text),'fare_per_seat':double.parse(fare.text)});setState(()=>message='Ride published');}catch(e){setState(()=>message=e.toString());}}
  Future<void> book(String id) async {try{await db!.rpc('create_booking',params:{'p_ride_id':id,'p_seats':1});setState(()=>message='Booking request created. Payment is not collected yet.');await search();}catch(e){setState(()=>message=e.toString());}}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('🚗 TIP CAR & BUS'),actions:[if(db?.auth.currentUser!=null)IconButton(onPressed:()=>db!.auth.signOut(),icon:const Icon(Icons.logout))]),
    body:!widget.configured?const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY using --dart-define, then run again.',textAlign:TextAlign.center))):ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[Color(0xff092b66),Color(0xff075de8)])),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('PAN-INDIA RIDE SHARING',style:TextStyle(color:Colors.white70,fontSize:11)),SizedBox(height:8),Text('Every journey starts together.',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:26)),Text('Find a seat. Share a ride.',style:TextStyle(color:Colors.white70))])),
      const SizedBox(height:16),
      if(db!.auth.currentSession==null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Full name')),TextField(controller:phone,decoration:const InputDecoration(labelText:'Mobile number with country code')),FilledButton(onPressed:sendOtp,child:const Text('Send OTP')),TextField(controller:otp,decoration:const InputDecoration(labelText:'SMS OTP')),FilledButton(onPressed:verifyOtp,child:const Text('Verify OTP'))]))),
      SegmentedButton<int>(segments:const [ButtonSegment(value:0,label:Text('Find rides')),ButtonSegment(value:1,label:Text('Publish ride'))],selected:{tab},onSelectionChanged:(s)=>setState(()=>tab=s.first)),
      const SizedBox(height:12),
      if(tab==0)...[
        TextField(controller:from,decoration:const InputDecoration(labelText:'From')),TextField(controller:to,decoration:const InputDecoration(labelText:'To')),
        FilledButton(onPressed:search,child:const Text('Search rides')),
        if(loading)const Center(child:CircularProgressIndicator()),
        ...rides.map((r)=>Card(child:ListTile(leading:const Icon(Icons.directions_car),title:Text('${r['origin']} → ${r['destination']}'),subtitle:Text('${r['vehicle_name']} · ${r['available_seats']} seats · ${DateFormat.yMMMd().add_jm().format(DateTime.parse(r['departure_at']).toLocal())}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('₹${r['fare_per_seat']}'),TextButton(onPressed:()=>book(r['id']),child:const Text('Book'))]))))
      ] else ...[
        TextField(controller:vehicle,decoration:const InputDecoration(labelText:'Vehicle name')),TextField(controller:number,decoration:const InputDecoration(labelText:'Vehicle number')),TextField(controller:fare,decoration:const InputDecoration(labelText:'Fare per seat')),TextField(controller:seats,decoration:const InputDecoration(labelText:'Total seats')),ListTile(title:Text('Departure: ${DateFormat.yMMMd().add_jm().format(departure)}'),trailing:IconButton(icon:const Icon(Icons.calendar_month),onPressed:()async{final d=await showDatePicker(context:context,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:365)),initialDate:departure);if(d!=null)setState(()=>departure=DateTime(d.year,d.month,d.day,departure.hour,departure.minute));})),FilledButton(onPressed:publish,child:const Text('Publish ride'))
      ],
      if(message.isNotEmpty)Padding(padding:const EdgeInsets.all(12),child:Text(message,style:const TextStyle(color:Colors.blue))),
    ]),
  );
}
