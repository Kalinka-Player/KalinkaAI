/// The accented letters offered when a Latin key is held down.
///
/// Every mobile keyboard hides its accents behind a long press rather than on
/// a separate page, because a French or Polish word needs one mid-sentence.
/// Keys are lowercase; the uppercase forms are derived when shift is on, so
/// only one table is maintained.
///
/// Pass your own map to `VirtualKeypad.accents` to change or extend this, or
/// an empty map to turn the popup off.
///
/// {@category Layouts}
const Map<String, List<String>> kLatinAccents = {
  'a': ['à', 'á', 'â', 'ä', 'ã', 'å', 'ą', 'æ', 'ā', 'ă'],
  'c': ['ç', 'ć', 'č'],
  'd': ['ď', 'đ', 'ð'],
  'e': ['è', 'é', 'ê', 'ë', 'ę', 'ě', 'ē', 'ė'],
  'g': ['ğ', 'ģ'],
  'i': ['ì', 'í', 'î', 'ï', 'ı', 'ī', 'į'],
  'k': ['ķ'],
  'l': ['ł', 'ļ'],
  'n': ['ñ', 'ń', 'ň', 'ņ'],
  'o': ['ò', 'ó', 'ô', 'ö', 'õ', 'ø', 'œ', 'ő'],
  'r': ['ř'],
  's': ['ß', 'ś', 'š', 'ş', 'ș'],
  't': ['ť', 'ț', 'þ'],
  'u': ['ù', 'ú', 'û', 'ü', 'ů', 'ű', 'ū', 'ų'],
  'y': ['ý', 'ÿ'],
  'z': ['ź', 'ż', 'ž'],
};
