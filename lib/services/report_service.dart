import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/punch.dart';
import '../models/weekly_summary.dart';
import 'report_file_saver.dart';

class ReportService {
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _date = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  Future<String> exportPdf({
    required String employeeName,
    required List<Punch> punches,
    required WeeklySummary summary,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Relatorio semanal - Lê Ponto', style: const pw.TextStyle(fontSize: 20)),
          pw.SizedBox(height: 8),
          pw.Text('Funcionario: $employeeName'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Data', 'Tipo', 'Distancia', 'Justificativa'],
            data: punches
                .map((p) => [
                      _date.format(p.serverTime),
                      p.type.label,
                      '${p.distanceMeters.toStringAsFixed(1)} m',
                      p.justification ?? '',
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Horas normais: ${_minutes(summary.normalMinutes)}'),
          pw.Text('Horas extras liquidas: ${_minutes(summary.overtimeMinutes)}'),
          pw.Text('Atrasos: ${_minutes(summary.lateMinutes)}'),
          pw.Text('Saidas antecipadas: ${_minutes(summary.earlyLeaveMinutes)}'),
          pw.Text('Valor das horas extras: ${_currency.format(summary.amountToPay)}'),
        ],
      ),
    );
    return saveReportBytes(
      name: 'relatorio_le_ponto.pdf',
      bytes: await doc.save(),
      mimeType: 'application/pdf',
    );
  }

  Future<String> exportExcel({
    required String employeeName,
    required List<Punch> punches,
    required WeeklySummary summary,
  }) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Semana';
    sheet.getRangeByName('A1').setText('Funcionario');
    sheet.getRangeByName('B1').setText(employeeName);
    sheet.getRangeByName('A3').setText('Data');
    sheet.getRangeByName('B3').setText('Tipo');
    sheet.getRangeByName('C3').setText('Distancia');
    sheet.getRangeByName('D3').setText('Justificativa');
    for (var i = 0; i < punches.length; i++) {
      final row = i + 4;
      final punch = punches[i];
      sheet.getRangeByIndex(row, 1).setText(_date.format(punch.serverTime));
      sheet.getRangeByIndex(row, 2).setText(punch.type.label);
      sheet.getRangeByIndex(row, 3).setNumber(punch.distanceMeters);
      sheet.getRangeByIndex(row, 4).setText(punch.justification ?? '');
    }
    final start = punches.length + 6;
    sheet.getRangeByIndex(start, 1).setText('Horas normais');
    sheet.getRangeByIndex(start, 2).setText(_minutes(summary.normalMinutes));
    sheet.getRangeByIndex(start + 1, 1).setText('Horas extras liquidas');
    sheet.getRangeByIndex(start + 1, 2).setText(_minutes(summary.overtimeMinutes));
    sheet.getRangeByIndex(start + 2, 1).setText('Valor das horas extras');
    sheet.getRangeByIndex(start + 2, 2).setText(_currency.format(summary.amountToPay));
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return saveReportBytes(
      name: 'relatorio_le_ponto.xlsx',
      bytes: bytes,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  String _minutes(int value) {
    final hours = value ~/ 60;
    final minutes = value % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }
}
