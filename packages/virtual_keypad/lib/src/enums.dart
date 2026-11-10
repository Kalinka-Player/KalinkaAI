/// Actions that can be performed by special keys on the keyboard.
enum KeyAction {
  /// Delete the character before the cursor.
  backSpace,

  /// Insert a newline character.
  enter,

  /// Toggle shift mode for uppercase letters.
  shift,

  /// Insert a space character.
  space,

  /// Switch between letter and symbol layouts.
  symbols,

  /// Switch between primary and alternate symbol layouts.
  symbolsAlt,

  /// Switch between the active keyboard page and the emoji keyboard.
  emoji,

  /// Open the keyboard language picker.
  switchLanguage,

  /// Done action (submit/close keyboard for single-line inputs).
  done,

  /// Go action (for URL inputs - navigate).
  go,

  /// Search action (for search inputs).
  search,

  /// Send action (for chat/messaging inputs).
  send,

  /// Next action (move to next field).
  next,

  /// Previous action (move to previous field).
  previous,

  /// Call action (for phone inputs).
  call,
}

/// The type of a virtual keyboard key.
enum KeyType {
  /// A key that performs an action (backspace, enter, shift, etc.).
  action,

  /// A key that inserts a character.
  character,
}

/// Keyboard input types that determine the layout shown.
///
/// These map closely to Flutter's [TextInputType] values.
enum KeyboardType {
  /// Standard text keyboard with QWERTY layout.
  text,

  /// Multiline text input (shows enter key for newlines).
  multiline,

  /// Numeric keypad / numpad (0-9 with decimal point).
  number,

  /// Signed number input (includes minus sign).
  numberSigned,

  /// Decimal number input.
  numberDecimal,

  /// Phone dialer layout.
  phone,

  /// Date/time input keyboard.
  datetime,

  /// Email address input (@ and . easily accessible).
  emailAddress,

  /// URL input (/, :, . easily accessible).
  url,

  /// Password and PIN entry input (same layout as text, but the action key
  /// may differ).
  visiblePassword,

  /// Person name input (similar to text).
  name,

  /// Street address input.
  streetAddress,

  /// No keyboard (hidden).
  none,

  /// Custom layout provided via [VirtualKeypad.customLayout], such as a PIN
  /// pad or OTP keypad.
  custom,
}

/// Current layout stage for keyboards with multiple pages.
enum LayoutStage {
  /// Primary layout (letters for text, main symbols for others).
  primary,

  /// Secondary layout (numbers and common symbols).
  secondary,

  /// Tertiary layout (additional symbols and special characters).
  tertiary,

  /// Emoji layout.
  emoji,
}

/// How a key press is confirmed to the user, beyond the visual key preview.
///
/// A touchscreen gives no tactile confirmation on its own, which is why every
/// system keyboard ships some form of this. On a kiosk or POS terminal it is
/// often the only signal that a tap registered at all.
///
/// Defaults to [sound], which is what the keyboard has always done: Material's
/// ink response plays the platform key click on Android. Setting this now also
/// covers D-pad activation, which the ink response never reached, so the
/// confirmation no longer depends on how the key was pressed.
///
/// Both effects are handled by the platform, so there is no asset to bundle and
/// nothing to configure. Where a platform has no vibration motor or no key
/// click the effect is skipped rather than failing, and both follow the user's
/// system settings including silent mode.
///
/// ```dart
/// VirtualKeypad(feedback: KeyFeedback.both)   // click and a light vibration
/// VirtualKeypad(feedback: KeyFeedback.none)   // silent and still
/// ```
enum KeyFeedback {
  /// No haptic and no sound.
  ///
  /// Worth choosing for a kiosk in a quiet room, or where the app plays its
  /// own confirmation sound and two would collide.
  none,

  /// A light vibration on each key press, and no sound.
  ///
  /// Android and iOS honour the user's system-wide haptics setting, so someone
  /// who has turned vibration off still gets what they asked for.
  haptic,

  /// The platform's key click sound, and no vibration. The default.
  sound,

  /// Both a light vibration and the key click sound.
  both,
}

/// When the digit keys change position, for PIN and payment entry.
///
/// A fixed keypad is predictable: someone watching the hand, or a camera above
/// the terminal, learns the PIN from finger positions alone. Shuffling the
/// digits removes that, at the cost of the muscle memory a regular user builds.
/// Off by default, because for most keyboards that trade is not worth it.
///
/// {@category Enums}
enum KeyShuffle {
  /// Digits keep their usual positions. The default.
  none,

  /// Digits are shuffled once each time the keypad becomes visible, so a
  /// watcher cannot carry knowledge from one entry to the next.
  ///
  /// This is what payment terminals do. Positions hold still while the user is
  /// typing, so entry stays usable.
  onShow,

  /// Digits are shuffled again after every keypress.
  ///
  /// Maximum resistance to shoulder surfing and to camera capture, and clearly
  /// harder to use: the key a user is reaching for moves before they land on
  /// it. Reserve it for high-value entry where that is an accepted cost.
  onEveryKey,
}
