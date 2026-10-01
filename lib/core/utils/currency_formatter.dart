/// Central utility for formatting monetary values in FlexPOS.
/// Formats all currency amounts consistently using Indian Rupees (₹).
class CurrencyFormatter {
  static const String symbol = '₹';
  static const String code = 'INR';

  /// Formats a numeric amount into an INR string, e.g. `₹1,245.50` or `₹285.00`.
  static String format(num amount, {int decimalDigits = 2}) {
    final double doubleVal = amount.toDouble();
    final bool isNegative = doubleVal < 0;
    final double absVal = doubleVal.abs();

    final String fixedStr = absVal.toStringAsFixed(decimalDigits);
    final List<String> parts = fixedStr.split('.');
    final String intPart = parts[0];
    final String decPart = parts.length > 1 ? parts[1] : '';

    final String formattedInt = _formatIndianNumbering(intPart);
    final String result = '$symbol$formattedInt${decPart.isNotEmpty ? '.' : ''}$decPart';

    return isNegative ? '-$result' : result;
  }

  /// Formats integer string according to Indian Numbering System (last 3 digits, then 2 digits groups).
  static String _formatIndianNumbering(String numberStr) {
    if (numberStr.length <= 3) return numberStr;

    final String lastThree = numberStr.substring(numberStr.length - 3);
    String otherDigits = numberStr.substring(0, numberStr.length - 3);

    final RegExp regExp = RegExp(r'(\d+?)(?=(\d{2})+$)');
    otherDigits = otherDigits.replaceAllMapped(regExp, (Match m) => '${m[1]},');

    return '$otherDigits,$lastThree';
  }
}
