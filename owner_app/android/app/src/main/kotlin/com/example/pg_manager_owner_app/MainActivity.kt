package com.example.pg_manager_owner_app

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth requires the host Activity to be a FragmentActivity; the default
// FlutterActivity makes biometric authenticate() throw `no_fragment_activity`.
class MainActivity : FlutterFragmentActivity()
