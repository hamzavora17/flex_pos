import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/utils/currency_formatter.dart';
import '../models/completed_sale_model.dart';
import '../models/return_model.dart';

class ReceiptPrinterService {
  /// Generates and triggers native printing for a return receipt.
  static Future<bool> printReturnReceipt(
    ReturnReceiptModel receipt, {
    String storeName = 'FLEXPOS',
    String? headerMessage,
  }) async {
    try {
      final shortReturnId = receipt.returnId.length > 8
          ? receipt.returnId.substring(0, 8).toUpperCase()
          : receipt.returnId;
      final formattedDate =
          '${receipt.returnDate.day.toString().padLeft(2, '0')}/${receipt.returnDate.month.toString().padLeft(2, '0')}/${receipt.returnDate.year} ${receipt.returnDate.hour.toString().padLeft(2, '0')}:${receipt.returnDate.minute.toString().padLeft(2, '0')}';

      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(12),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Store Brand Header
                pw.Text(
                  storeName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'RETURN & REFUND RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (headerMessage != null && headerMessage.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    headerMessage,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ] else ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Official Refund & Inventory Restoration Record',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
                pw.Divider(thickness: 1, height: 12),

                // Receipt Metadata
                _buildKeyValueRow('Return Receipt #:', '#$shortReturnId'),
                _buildKeyValueRow(
                  'Original Invoice #:',
                  '#${receipt.originalInvoiceNumber}',
                ),
                _buildKeyValueRow('Return Date:', formattedDate),
                _buildKeyValueRow(
                  'Refund Method:',
                  receipt.paymentMethod.toUpperCase(),
                ),
                pw.Divider(thickness: 1, height: 12),

                // Returned Products Section
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'RETURNED PRODUCTS',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),

                ...receipt.returnedItems.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                item.productName,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (item.sku != null && item.sku!.isNotEmpty)
                                pw.Text(
                                  'SKU: ${item.sku}',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              pw.Text(
                                '${item.selectedQuantity}x @ ${CurrencyFormatter.format(item.unitPrice)}',
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ],
                          ),
                        ),
                        pw.Text(
                          CurrencyFormatter.format(item.lineRefund),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.Divider(thickness: 1, height: 12),

                // Total Refund Issued
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL REFUND ISSUED:',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      CurrencyFormatter.format(receipt.refundAmount),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Status Badge Box
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 1),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'APPROVED & STOCK RESTORED',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Thank you for shopping with FlexPOS!',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            );
          },
        ),
      );

      return await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Return_Receipt_$shortReturnId',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Generates and triggers native printing for a sales receipt.
  static Future<bool> printSalesReceipt(
    CompletedSaleModel sale, {
    String storeName = 'FLEXPOS',
    String? headerMessage,
  }) async {
    try {
      final formattedDate =
          '${sale.createdAt.day.toString().padLeft(2, '0')}/${sale.createdAt.month.toString().padLeft(2, '0')}/${sale.createdAt.year} ${sale.createdAt.hour.toString().padLeft(2, '0')}:${sale.createdAt.minute.toString().padLeft(2, '0')}';

      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(12),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  storeName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'SALES RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (headerMessage != null && headerMessage.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    headerMessage,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                pw.Divider(thickness: 1, height: 12),

                _buildKeyValueRow('Invoice #:', sale.invoiceNumber),
                _buildKeyValueRow('Date:', formattedDate),
                _buildKeyValueRow(
                  'Payment Method:',
                  sale.paymentMethod.toUpperCase(),
                ),
                pw.Divider(thickness: 1, height: 12),

                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'PURCHASED ITEMS',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),

                ...sale.items.map((item) {
                  final name =
                      item.productNameSnapshot ?? item.productName ?? 'Product';
                  final sku = item.skuSnapshot ?? item.productSku ?? '';

                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                name,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (sku.isNotEmpty)
                                pw.Text(
                                  'SKU: $sku',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              pw.Text(
                                '${item.quantity}x @ ${CurrencyFormatter.format(item.unitPrice)}',
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ],
                          ),
                        ),
                        pw.Text(
                          CurrencyFormatter.format(item.lineTotal),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.Divider(thickness: 1, height: 12),

                _buildKeyValueRow(
                  'Subtotal:',
                  CurrencyFormatter.format(sale.subtotal),
                ),
                if (sale.discount > 0)
                  _buildKeyValueRow(
                    'Discount:',
                    '-${CurrencyFormatter.format(sale.discount)}',
                  ),
                if (sale.tax > 0)
                  _buildKeyValueRow(
                    'Tax:',
                    CurrencyFormatter.format(sale.tax),
                  ),

                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'GRAND TOTAL:',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      CurrencyFormatter.format(sale.total),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Thank you for your purchase!',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            );
          },
        ),
      );

      return await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Sales_Receipt_${sale.invoiceNumber}',
      );
    } catch (e) {
      rethrow;
    }
  }

  static pw.Widget _buildKeyValueRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
