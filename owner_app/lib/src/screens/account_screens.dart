import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/app_shell.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final username = TextEditingController(); bool sent = false;
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    IconButton(alignment: Alignment.centerLeft, onPressed: () => context.go('/login'), icon: const Icon(Icons.arrow_back)),
    Text('Forgot Password', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 8), const Text('Enter your registered email or mobile number. WhatsApp delivery can be enabled when a provider is configured.'),
    const SizedBox(height: 24), TextField(controller: username, decoration: const InputDecoration(labelText: 'Email or mobile number', prefixIcon: Icon(Icons.phone_outlined))),
    const SizedBox(height: 16), FilledButton(onPressed: sent ? null : () async { await context.read<AppState>().apiClient.post('/auth/password/forgot', {'username': username.text.trim()}); if (mounted) setState(() => sent = true); }, child: Text(sent ? 'Request recorded' : 'Send reset instructions')),
    if (sent) const Padding(padding: EdgeInsets.only(top: 12), child: Text('External delivery is not configured. Your administrator can enable the future WhatsApp adapter.', textAlign: TextAlign.center)),
  ]))))));
}

class ProfileScreen extends StatefulWidget { const ProfileScreen({super.key}); @override State<ProfileScreen> createState()=>_ProfileScreenState(); }
class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String,dynamic>> future; final name=TextEditingController(); final mobile=TextEditingController(); bool seeded=false;
  @override void initState(){super.initState(); future=context.read<AppState>().apiClient.get('/account/profile');}
  @override Widget build(BuildContext context)=>AppShell(title:'Profile Information',child:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,snapshot){
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator()); final data=snapshot.data!; if(!seeded){name.text='${data['fullName']??''}';mobile.text='${data['mobileNumber']??''}';seeded=true;}
    return ListView(children:[const CircleAvatar(radius:42,child:Icon(Icons.person,size:42)),const SizedBox(height:20),TextField(controller:name,decoration:const InputDecoration(labelText:'Full Name')),const SizedBox(height:12),TextField(controller:mobile,decoration:const InputDecoration(labelText:'Mobile Number')),const SizedBox(height:12),TextFormField(initialValue:'${data['email']??''}',enabled:false,decoration:const InputDecoration(labelText:'Email Address')),const SizedBox(height:12),TextFormField(initialValue:'${data['roleTypeId']??''}',enabled:false,decoration:const InputDecoration(labelText:'Role')),const SizedBox(height:20),FilledButton(onPressed:()async{await context.read<AppState>().apiClient.patch('/account/profile',{'fullName':name.text,'mobileNumber':mobile.text});if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Profile updated')));},child:const Text('Save Changes'))]);
  }));
}

class ChangePasswordScreen extends StatefulWidget { const ChangePasswordScreen({super.key}); @override State<ChangePasswordScreen> createState()=>_ChangePasswordScreenState(); }
class _ChangePasswordScreenState extends State<ChangePasswordScreen>{final current=TextEditingController(),next=TextEditingController(),confirm=TextEditingController();final key=GlobalKey<FormState>();
  @override Widget build(BuildContext context)=>AppShell(title:'Change Password',child:Form(key:key,child:ListView(children:[const Icon(Icons.shield_outlined,size:72),const SizedBox(height:18),for(final item in [(current,'Current Password'),(next,'New Password'),(confirm,'Confirm New Password')])Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(controller:item.$1,obscureText:true,decoration:InputDecoration(labelText:item.$2,prefixIcon:const Icon(Icons.lock_outline)),validator:(v)=>v==null||v.length<8?'Minimum 8 characters':null)),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('Use at least 8 characters with uppercase, lowercase, number, and special character.'))),const SizedBox(height:16),FilledButton(onPressed:()async{if(!key.currentState!.validate())return;await context.read<AppState>().apiClient.post('/account/change-password',{'currentPassword':current.text,'newPassword':next.text,'confirmPassword':confirm.text});if(context.mounted){await context.read<AppState>().logout();context.go('/login');}},child:const Text('Update Password'))])));
}
