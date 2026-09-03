import 'package:flutter/material.dart';

void main() {
  runApp(const LuumohWorkspaceApp());
}

class LuumohWorkspaceApp extends StatelessWidget {
  const LuumohWorkspaceApp({super.key});

  static const _apps = [
    _WorkspaceApp('Customer', 'apps/customer_app'),
    _WorkspaceApp('Store', 'apps/store_app'),
    _WorkspaceApp('Rider', 'apps/rider_app'),
    _WorkspaceApp('Admin', 'apps/admin_dashboard'),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luumoh Workspace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xfff6b01a)),
        useMaterial3: true,
      ),
      home: const _WorkspaceHome(),
    );
  }
}

class _WorkspaceHome extends StatelessWidget {
  const _WorkspaceHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Luumoh Workspace')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final app = LuumohWorkspaceApp._apps[index];
          return ListTile(
            leading: const Icon(Icons.apps),
            title: Text(app.name),
            subtitle: Text(app.path),
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: LuumohWorkspaceApp._apps.length,
      ),
    );
  }
}

class _WorkspaceApp {
  const _WorkspaceApp(this.name, this.path);

  final String name;
  final String path;
}
