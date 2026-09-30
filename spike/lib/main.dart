import 'package:flutter/material.dart';

import 'spike_checks.dart';

void main() => runApp(const MaterialApp(home: SpikePage()));

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final List<CheckResult> _results = [];
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    await runSpikeChecks(onResult: (result) => setState(() => _results.add(result)));
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS 阻塞桥验证')),
      floatingActionButton: FloatingActionButton(
        onPressed: _running ? null : _run,
        child: _running ? const CircularProgressIndicator() : const Icon(Icons.play_arrow),
      ),
      body: ListView(
        children: [
          for (final result in _results)
            ListTile(
              leading: Icon(
                result.passed ? Icons.check_circle : Icons.error,
                color: result.passed ? Colors.green : Colors.red,
              ),
              title: Text(result.name),
              subtitle: Text('${result.elapsed.inMilliseconds}ms  ${result.detail}'),
            ),
        ],
      ),
    );
  }
}
