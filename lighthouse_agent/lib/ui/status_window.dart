import 'package:flutter/material.dart';

class StatusWindow extends StatelessWidget {
  const StatusWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lighthouse Agent')),
      body: const Center(
        child: Text('Active sessions will appear here in Day 6.'),
      ),
    );
  }
}
