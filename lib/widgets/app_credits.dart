import 'package:flutter/material.dart';

class AppCreditsLine extends StatelessWidget {
  const AppCreditsLine({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Text(
      'Desenvolvido por Ronaldo Junio - Neo Conect',
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

void showAppCreditsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Creditos'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Le Ponto',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          Text('Desenvolvido por Ronaldo Junio.'),
          SizedBox(height: 4),
          Text('Programador freelancer da Neo Conect.'),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Ok'),
        ),
      ],
    ),
  );
}
