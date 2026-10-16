/// Upper-case words that are part of bank message formats, not names.
const _keep = {
  'VCB',
  'MBVCB',
  'VND',
  'TK',
  'CT',
  'OTP',
  'IBFT',
  'FT',
  'NAPAS',
  'ATM',
  'POS',
  'QR',
  'REF',
};

final _letters = RegExp(r'\p{L}+', unicode: true);

/// Hides account numbers, amounts, balances, Ref codes and people's names in
/// a notification while keeping its shape, so a parser rule can still be
/// written from it: every digit becomes `9` (separators and group lengths
/// stay) and every all-caps word outside [_keep] becomes `XXXX` (`X` for a
/// single letter).
String maskSample(String text) {
  final noDigits = text.replaceAll(RegExp(r'\d'), '9');
  return noDigits.replaceAllMapped(_letters, (m) {
    final w = m.group(0)!;
    final isAllCaps = w == w.toUpperCase() && w != w.toLowerCase();
    if (!isAllCaps || _keep.contains(w)) return w;
    return w.length == 1 ? 'X' : 'XXXX';
  });
}
