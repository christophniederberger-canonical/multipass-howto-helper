import 'dart:async';
import 'package:flutter/material.dart';
import '../agent/multipass_wrapper.dart';

class StatusWindow extends StatefulWidget {
  const StatusWindow({super.key});

  @override
  State<StatusWindow> createState() => _StatusWindowState();
}

class _StatusWindowState extends State<StatusWindow> {
  final MultipassWrapper _multipass = const MultipassWrapper();
  Timer? _refreshTimer;
  List<VmListEntry> _vms = [];
  int _connectionCount = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final vms = await _multipass.list();
      if (mounted) {
        setState(() {
          _vms = vms.where((vm) => vm.name.startsWith('lighthouse-')).toList();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openTutorial(String vmName) async {
    // In a real implementation, this would open the browser with the tutorial URL
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening tutorial for $vmName...')),
    );
  }

  Color _getStatusColor(String state) {
    return switch (state.toLowerCase()) {
      'running' => Colors.green,
      'starting' => Colors.orange,
      'stopped' => Colors.grey,
      'deleting' => Colors.red,
      _ => Colors.grey,
    };
  }

  IconData _getTrayIcon(String state) {
    return switch (state.toLowerCase()) {
      'running' => Icons.check_circle,
      'starting' => Icons.hourglass_empty,
      'stopped' => Icons.circle_outlined,
      'deleting' => Icons.delete,
      _ => Icons.circle_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lighthouse Agent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _vms.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No active VMs'),
                          SizedBox(height: 8),
                          Text(
                            'VMs will appear here when tutorials are running',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _vms.length,
                      itemBuilder: (context, index) {
                        final vm = _vms[index];
                        return _VmCard(
                          vmName: vm.name,
                          state: vm.state,
                          connectionCount: _connectionCount,
                          onOpenTutorial: () => _openTutorial(vm.name),
                          statusColor: _getStatusColor(vm.state),
                          trayIcon: _getTrayIcon(vm.state),
                        );
                      },
                    ),
    );
  }
}

class _VmCard extends StatelessWidget {
  final String vmName;
  final String state;
  final int connectionCount;
  final VoidCallback onOpenTutorial;
  final Color statusColor;
  final IconData trayIcon;

  const _VmCard({
    required this.vmName,
    required this.state,
    required this.connectionCount,
    required this.onOpenTutorial,
    required this.statusColor,
    required this.trayIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(trayIcon, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vmName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(state.toUpperCase()),
                  backgroundColor: statusColor.withValues(alpha: 0.2),
                  labelStyle: TextStyle(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.people, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Connections: $connectionCount'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenTutorial,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open Tutorial'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
