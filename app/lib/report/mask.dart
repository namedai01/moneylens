/// Upper-case words that are part of bank message formats, not names.
const _keep = {
  'VCB',
  'MBVCB',
  'SHB',
  'SAHA',
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

final _hidden = RegExp(r'[^\S \n]|\p{Cf}|\p{M}', unicode: true);

/// Writes every character a rule could trip over but a person cannot see
/// (format marks, combining accents, spaces other than ' ' and '\n') as
/// `<U+XXXX>`, so a shared sample shows what the bank app really sent.
String revealHidden(String text) => text.replaceAllMapped(_hidden, (m) {
  final hex = m.group(0)!.runes.first.toRadixString(16).toUpperCase();
  return '<U+${hex.padLeft(4, '0')}>';
});
