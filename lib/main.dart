import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const apiOverride = String.fromEnvironment('SIAGANOW_API_URL');
const demoMode = bool.fromEnvironment('SIAGANOW_DEMO_MODE', defaultValue: true);

String get apiBase => apiOverride.isNotEmpty
    ? apiOverride
    : (kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api');

void main() => runApp(const SiagaNowApp());

class ApiService {
  ApiService(this.storage);
  final FlutterSecureStorage storage;
  final _client = http.Client();

  Future<Map<String, dynamic>> get(String path) async {
    final token = await storage.read(key: 'token');
    final response = await _client.get(Uri.parse('$apiBase/$path'), headers: {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 10));
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body is Map ? body['message'] ?? 'Permintaan gagal.' : 'Permintaan gagal.');
    }
    return Map<String, dynamic>.from(body as Map);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    final token = await storage.read(key: 'token');
    final response = await _client.post(Uri.parse('$apiBase/$path'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'},
      body: jsonEncode(data)).timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = body is Map ? body['message'] ?? 'Permintaan gagal.' : 'Permintaan gagal.';
      throw Exception(message);
    }
    return Map<String, dynamic>.from(body as Map);
  }
}

class SiagaNowApp extends StatefulWidget {
  const SiagaNowApp({super.key});
  @override State<SiagaNowApp> createState() => _SiagaNowAppState();
}

class _SiagaNowAppState extends State<SiagaNowApp> {
  final storage = const FlutterSecureStorage();
  late final api = ApiService(storage);
  int tab = 0;
  String? userName;
  bool booting = true;

  @override void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    String? token;
    try { token = await storage.read(key: 'token'); } catch (_) { token = null; }
    if (token != null) {
      try { final me = await api.get('user'); userName = me['data']?['name']?.toString(); }
      catch (_) { await storage.delete(key: 'token'); }
    }
    if (mounted) setState(() => booting = false);
  }
  Future<void> _auth() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, builder: (_) => AuthSheet(api: api));
    if (result != null && mounted) setState(() => userName = result['name']?.toString());
  }
  Future<void> _logout() async {
    try { await api.post('logout', {}); } catch (_) {}
    await storage.delete(key: 'token');
    if (mounted) setState(() => userName = null);
  }

  @override Widget build(BuildContext context) {
    const forest = Color(0xFF075B49);
    return MaterialApp(title: 'SiagaNow', debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: forest,
        surface: const Color(0xFFEFF8F2)), scaffoldBackgroundColor: const Color(0xFFD9EEE2),
        fontFamily: 'Roboto', appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFEFF8F2),
          foregroundColor: Color(0xFF15392F), elevation: 0), cardTheme: CardThemeData(
          color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7), side: const BorderSide(color: Color(0xFFCFE3D8))))),
      home: booting ? const Scaffold(body: Center(child: CircularProgressIndicator())) : Scaffold(
        appBar: AppBar(title: Row(children: [Container(width: 34, height: 34,
          decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.shield_moon_outlined, color: Colors.white, size: 20)),
          const SizedBox(width: 10), const Text('SiagaNow', style: TextStyle(fontWeight: FontWeight.w800))]),
          actions: [TextButton.icon(onPressed: userName == null ? _auth : _logout,
            icon: Icon(userName == null ? Icons.person_outline : Icons.logout, size: 18),
            label: Text(userName == null ? 'Masuk' : 'Keluar'))]),
        body: IndexedStack(index: tab, children: [HomePage(api: api), ShelterPage(api: api),
          ReportPage(api: api, loggedIn: userName != null, onLogin: _auth), const MorePage()]),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Peta'),
            NavigationDestination(icon: Icon(Icons.add_location_alt_outlined), selectedIcon: Icon(Icons.add_location_alt), label: 'Laporan'),
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Lainnya')])));
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api}); final ApiService api;
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? data; bool loading = true; String? error;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { setState(() { loading = true; error = null; });
    try { data = await widget.api.get('home'); }
    catch (e) { if (kDebugMode) debugPrint('SiagaNow home API failed: '); error = 'Server belum tersambung — menampilkan contoh lokal.'; if (demoMode) { data = {'data_type': 'simulation', 'weather': {'temperature': 28, 'condition': 'Contoh cuaca', 'source': 'Contoh lokal SiagaNow'}, 'statistics': {'regions': '—'}, 'warning': {'status': 'unknown', 'active': false, 'message': 'Informasi aktual tidak berhasil diambil. Tampilan cuaca adalah simulasi lokal.'}}; } }
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    final weather = data?['weather']; final stats = data?['statistics'];
    final isDemo = data?['data_type'] == 'simulation' || (data == null && demoMode);
    return RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [Text('SIAP MENGHADAPI HARI INI?', style: TextStyle(letterSpacing: 1.1,
          color: Colors.blueGrey.shade600, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 9), const Text('Kenali risiko.\nLindungi yang berarti.',
          style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w800, color: Color(0xFF183B31))),
        const SizedBox(height: 20), if (isDemo) const DemoBadge(),
        const SizedBox(height: 12), Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF075B49), Color(0xFF0B795D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.health_and_safety_outlined, color: Colors.white), SizedBox(width: 9),
              Text('Status kesiapsiagaan', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))]),
            const SizedBox(height: 18), Text(loading ? 'Memuat informasi…' : 'Tetap waspada, tetap terhubung',
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8), Text((data?['warning']?['message'] ?? error ?? 'Sumber informasi sedang diperiksa.').toString(),
              style: const TextStyle(color: Colors.white70, height: 1.4)),
            if (loading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
          ])),
        const SizedBox(height: 18), Row(children: [Expanded(child: _weatherTile(weather, isDemo)), const SizedBox(width: 12),
          Expanded(child: _metricTile('Wilayah dipantau', stats?['regions']?.toString() ?? '—', Icons.location_on_outlined))]),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: TextButton.icon(
          onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Coba muat kembali'))),
        const SizedBox(height: 22), const Text('Akses cepat', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12), const Row(children: [Expanded(child: QuickCard(icon: Icons.map_outlined, title: 'Peta & evakuasi', subtitle: 'Lihat titik contoh')), SizedBox(width: 10),
          Expanded(child: QuickCard(icon: Icons.add_location_alt_outlined, title: 'Kirim laporan', subtitle: 'Bagikan kondisi'))]),
        const SizedBox(height: 20), const Text('Informasi keselamatan', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10), Card(child: ListTile(leading: const Icon(Icons.info_outline, color: Color(0xFF145B45)),
          title: const Text('Periksa sumber sebelum bertindak', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Informasi simulasi bukan peringatan resmi. Ikuti arahan BPBD setempat.'), isThreeLine: true))]));
  }
  Widget _weatherTile(dynamic weather, bool demo) {
    final actual = weather is Map && weather['data_type'] == 'actual';
    final location = weather is Map ? weather['location']?.toString() : null;
    final condition = weather is Map ? weather['condition']?.toString() : null;
    return _metricTile('Prakiraan cuaca', weather is Map ? '${weather['temperature'] ?? '—'}°' : '—', Icons.wb_cloudy_outlined,
      caption: demo ? 'Contoh data' : actual ? 'BMKG · ${location ?? 'wilayah admin'}' : 'Sumber belum tersedia',
      detail: condition);
  }
  Widget _metricTile(String label, String value, IconData icon, {String? caption, String? detail}) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFFCFE3D8))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF397A60)), const SizedBox(height: 12),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), Text(label, style: TextStyle(color: Colors.blueGrey.shade600)),
      if (detail != null && detail.isNotEmpty) Text(detail, style: const TextStyle(color: Color(0xFF68756B), fontSize: 12)),
      if (caption != null) Text(caption, style: const TextStyle(color: Color(0xFF8A6720), fontSize: 11))]));
}

class ShelterPage extends StatefulWidget { const ShelterPage({super.key, required this.api}); final ApiService api;
 @override State<ShelterPage> createState() => _ShelterPageState(); }
class _ShelterPageState extends State<ShelterPage> {
  List<dynamic> places = []; bool loading = true; String? issue;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { setState(() { loading = true; issue = null; }); try {
    final result = await widget.api.get('shelters'); places = result['data'] is List ? result['data'] as List : [];
  } catch (_) { issue = 'Titik aktual belum berhasil dimuat. Tampilkan contoh hanya jika Mode Demo aktif.';
    if (demoMode) { places = [{'name':'Titik contoh — Lapangan Imam Bonjol','address':'Padang, Sumatera Barat','data_type':'simulation'},
      {'name':'Titik contoh — GOR H. Agus Salim','address':'Padang, Sumatera Barat','data_type':'simulation'}]; } }
    if (mounted) setState(() => loading = false); }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Peta evakuasi', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)), const SizedBox(height: 7),
    Text('Jelajahi titik informasi dan rencanakan kesiapsiagaan.', style: TextStyle(color: Colors.blueGrey.shade600)),
    const SizedBox(height: 16), Container(height: 190, decoration: BoxDecoration(color: const Color(0xFFE1EAE1), borderRadius: BorderRadius.circular(22)),
      child: Stack(children: [const Center(child: Icon(Icons.map_outlined, size: 54, color: Color(0xFF51846C))),
        Positioned(left: 14, top: 14, child: Chip(avatar: const Icon(Icons.science_outlined, size: 16), label: Text(demoMode ? 'Peta demo' : 'Peta'))),
        const Positioned(bottom: 14, left: 16, right: 16, child: Text('Peta dasar dan rute navigasi belum terhubung di aplikasi.', style: TextStyle(fontSize: 12))) ])),
    const SizedBox(height: 19), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Tempat evakuasi', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    if (loading) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
    else if (places.isEmpty) _EmptyState(text: issue ?? 'Belum ada tempat yang tercatat.' )
    else ...places.map((place) { final p = Map<String,dynamic>.from(place as Map); final simulated = p['data_type'] == 'simulation'; return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
      leading: const CircleAvatar(backgroundColor: Color(0xFFE7F1EA), child: Icon(Icons.place_outlined, color: Color(0xFF145B45))),
      title: Text((p['name'] ?? p['title'] ?? 'Titik informasi').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${p['address'] ?? p['description'] ?? 'Lokasi belum dijelaskan'}${simulated ? '\nContoh data — bukan shelter terverifikasi' : ''}'), isThreeLine: simulated,
      trailing: const Icon(Icons.chevron_right))); })]));
}

class ReportPage extends StatefulWidget { const ReportPage({super.key, required this.api, required this.loggedIn, required this.onLogin});
 final ApiService api; final bool loggedIn; final VoidCallback onLogin;
 @override State<ReportPage> createState() => _ReportPageState(); }
class _ReportPageState extends State<ReportPage> {
 final form = GlobalKey<FormState>(); final title = TextEditingController(); final description = TextEditingController();
 final lat = TextEditingController(text: '-0.9471'); final lng = TextEditingController(text: '100.4172');
 final injured = TextEditingController(); final deceased = TextEditingController();
 String eventType = 'Banjir', damage = 'Rendah'; bool sending = false;
 @override void dispose() { title.dispose(); description.dispose(); lat.dispose(); lng.dispose(); injured.dispose(); deceased.dispose(); super.dispose(); }
 Future<void> submit() async { if (!widget.loggedIn) { widget.onLogin(); return; } if (!form.currentState!.validate()) return;
  setState(() => sending = true); try { final now = DateTime.now(); await widget.api.post('reports', {'title': title.text.trim(), 'latitude': double.parse(lat.text),
    'longitude': double.parse(lng.text), 'event_date': '${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}',
    'event_time': '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}', 'event_type': eventType, 'damage_level': damage,
    'description': description.text.trim(), if (injured.text.isNotEmpty) 'injured': int.parse(injured.text), if (deceased.text.isNotEmpty) 'deceased': int.parse(deceased.text)});
   if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan terkirim dan menunggu pemeriksaan petugas.'))); title.clear(); description.clear(); }
  } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ','')))); }
  if (mounted) setState(() => sending = false); }
 @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
  const Text('Laporkan bencana', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)), const SizedBox(height: 8),
  Text('Bagikan informasi untuk ditinjau. Laporan tidak langsung menjadi peringatan resmi.', style: TextStyle(color: Colors.blueGrey.shade600, height: 1.45)),
  const SizedBox(height: 16), if (!widget.loggedIn) Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Masuk untuk mengirim laporan'), trailing: const Icon(Icons.chevron_right), onTap: widget.onLogin)),
  Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(18), child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
   const Text('Detail kejadian', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(height: 14),
   _field(title, 'Judul laporan', validator: (v) => (v == null || v.trim().length < 4) ? 'Masukkan judul minimal 4 karakter.' : null),
   const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: eventType, decoration: const InputDecoration(labelText: 'Jenis bencana', border: OutlineInputBorder()), items: ['Banjir','Tanah longsor'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(), onChanged: (v)=>setState(()=>eventType=v!)),
   const SizedBox(height: 12), Row(children: [Expanded(child: _field(lat, 'Latitude')), const SizedBox(width: 10), Expanded(child: _field(lng, 'Longitude'))]),
   const Padding(padding: EdgeInsets.only(top: 7), child: Text('Koordinat awal adalah contoh Padang. Pastikan ubah ke lokasi kejadian sebelum dikirim.', style: TextStyle(fontSize: 12, color: Color(0xFF85661B)))),
   const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: damage, decoration: const InputDecoration(labelText: 'Dampak yang terlihat', border: OutlineInputBorder()), items: ['Rendah','Sedang','Tinggi'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(), onChanged:(v)=>setState(()=>damage=v!)),
   const SizedBox(height: 12), Row(children: [Expanded(child: _field(injured, 'Luka-luka', validator: _wholeNumber)), const SizedBox(width: 10), Expanded(child: _field(deceased, 'Meninggal', validator: _wholeNumber))]),
   const Padding(padding: EdgeInsets.only(top: 7), child: Text('Kosongkan jumlah jika belum diketahui.', style: TextStyle(fontSize: 12, color: Colors.blueGrey))),
   const SizedBox(height: 12), _field(description, 'Ceritakan kondisi yang terlihat', maxLines: 4, validator: (v)=>(v==null||v.trim().length<10)?'Deskripsi minimal 10 karakter.':null),
   const SizedBox(height: 18), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: sending ? null : submit, icon: sending ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.send_outlined), label: Text(sending ? 'Mengirim…' : 'Kirim laporan'))),
  ]))))]);
 String? _wholeNumber(String? value) => value == null || value.isEmpty || (int.tryParse(value) != null && int.parse(value) >= 0) ? null : 'Masukkan bilangan bulat 0 atau lebih.';
 Widget _field(TextEditingController c, String label, {int maxLines=1, String? Function(String?)? validator}) => TextFormField(controller:c, maxLines:maxLines, keyboardType: maxLines == 1 && (label == 'Latitude' || label == 'Longitude' || label == 'Luka-luka' || label == 'Meninggal') ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.multiline, validator:validator,
  decoration: InputDecoration(labelText:label, alignLabelWithHint:maxLines>1, border: const OutlineInputBorder()));
}

class MorePage extends StatelessWidget { const MorePage({super.key});
 @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
  const Text('Layanan SiagaNow', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)), const SizedBox(height: 8),
  Text('Informasi kesiapsiagaan dalam satu tempat.', style: TextStyle(color: Colors.blueGrey.shade600)), const SizedBox(height: 18),
  const _ServiceCard(icon:Icons.volunteer_activism_outlined,title:'Donasi tanggap bencana',body:'Informasi kampanye dan pembayaran belum terhubung. Tidak ada transaksi nyata di aplikasi ini.'),
  _ServiceCard(icon:Icons.emergency_outlined,title:'PCC 112 · Kota Padang',body:'Panggilan gratis untuk keadaan darurat di Kota Padang. Ketuk untuk membuka dialer. Wilayah lain: hubungi BPBD kabupaten/kota setempat. Sumber: sigap.padang.go.id',onTap:() async { final opened=await launchUrl(Uri(scheme:'tel',path:'112')); if(!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Dialer tidak tersedia pada perangkat ini.'))); }),
  const _ServiceCard(icon:Icons.family_restroom_outlined,title:'Keluarga Siaga',body:'Fitur berbagi status dan anggota keluarga belum tersedia pada tahap ini.'),
  const SizedBox(height: 8), const DemoBadge()]);
}

class AuthSheet extends StatefulWidget { const AuthSheet({super.key, required this.api}); final ApiService api;
 @override State<AuthSheet> createState()=>_AuthSheetState(); }
class _AuthSheetState extends State<AuthSheet> {
 final form=GlobalKey<FormState>(); final identifier=TextEditingController(); final password=TextEditingController(); bool busy=false; String? error;
 @override void dispose(){identifier.dispose();password.dispose();super.dispose();}
 Future<void> submit() async { if(!form.currentState!.validate()) return; setState(()=>busy=true); try {
  final result=await widget.api.post('login',{'identifier':identifier.text.trim(),'password':password.text});
  final token=result['token']?.toString(); if(token==null) throw Exception('Server tidak mengembalikan token.');
  await widget.api.storage.write(key:'token',value:token);
  if(mounted) Navigator.pop(context, Map<String,dynamic>.from(result['data'] as Map));
 } catch(e){setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
 if(mounted)setState(()=>busy=false); }
 @override Widget build(BuildContext context)=>Padding(padding: EdgeInsets.fromLTRB(22,16,22,MediaQuery.viewInsetsOf(context).bottom+22), child: Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
  Center(child:Container(width:38,height:4,decoration:BoxDecoration(color:Colors.black26,borderRadius:BorderRadius.circular(4)))), const SizedBox(height:22),
  const Text('Selamat datang',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:6),const Text('Masuk dengan akun SiagaNow Anda.'),const SizedBox(height:20),
  TextFormField(controller:identifier,decoration:const InputDecoration(labelText:'Email atau nomor HP',border:OutlineInputBorder()),validator:(v)=>v==null||v.isEmpty?'Wajib diisi.':null),const SizedBox(height:12),
  TextFormField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Kata sandi',border:OutlineInputBorder()),validator:(v)=>v==null||v.isEmpty?'Wajib diisi.':null),
  if(error!=null) Padding(padding:const EdgeInsets.only(top:10),child:Text(error!,style:const TextStyle(color:Colors.red))),const SizedBox(height:16),
  SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:submit,child:Text(busy?'Memeriksa…':'Masuk'))),
  const SizedBox(height:6),const Text('Pendaftaran dapat dilakukan melalui website SiagaNow.',style:TextStyle(fontSize:12,color:Colors.blueGrey))
 ])));
}

class DemoBadge extends StatelessWidget { const DemoBadge({super.key});
 @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:8), decoration:BoxDecoration(color:const Color(0xFFFFF4D7),borderRadius:BorderRadius.circular(12)),
 child:const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.science_outlined,size:16,color:Color(0xFF85661B)),SizedBox(width:7),Flexible(child:Text('Data simulasi untuk demonstrasi — bukan informasi resmi',style:TextStyle(fontSize:11,color:Color(0xFF765B1C),fontWeight:FontWeight.w600)))]));
}
class QuickCard extends StatelessWidget { const QuickCard({super.key,required this.icon,required this.title,required this.subtitle}); final IconData icon;final String title,subtitle;
 @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:const Color(0xFF145B45)),const SizedBox(height:12),Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),Text(subtitle,style:TextStyle(color:Colors.blueGrey.shade600,fontSize:12))]))); }
class _ServiceCard extends StatelessWidget { const _ServiceCard({required this.icon,required this.title,required this.body,this.onTap});final IconData icon;final String title,body;final VoidCallback? onTap;
 @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:11),child:ListTile(contentPadding:const EdgeInsets.all(15),leading:CircleAvatar(backgroundColor:const Color(0xFFE7F1EA),child:Icon(icon,color:const Color(0xFF145B45))),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Text(body)),onTap:onTap,trailing:onTap==null?null:const Icon(Icons.call_outlined))); }
class _EmptyState extends StatelessWidget { const _EmptyState({required this.text});final String text;
 @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(28),child:Column(children:[const Icon(Icons.inbox_outlined,size:36,color:Colors.blueGrey),const SizedBox(height:8),Text(text,textAlign:TextAlign.center)])); }


