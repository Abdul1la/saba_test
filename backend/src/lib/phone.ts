// A port of the app's lib/core/utils/iraqi_phone.dart and Formatters.western:
// one number however it was typed (0770 123 4567, +964 770…, 00964…, Arabic
// digits), kept one way: +9647701234567 (BUGS 108).

/** Arabic-Indic (٠-٩) and Persian (۰-۹) digits as 0-9. */
export function westernDigits(text: string): string {
  return text.replace(/[٠-٩۰-۹]/g, (digit) => {
    const unit = digit.charCodeAt(0)
    return String(unit >= 0x06f0 ? unit - 0x06f0 : unit - 0x0660)
  })
}

/** The number in E.164, or null when it is not an Iraqi mobile: a 7 and nine more digits. */
export function normalizePhone(input: string): string | null {
  let digits = westernDigits(input).replace(/\D/g, '')
  if (digits.startsWith('00964')) digits = digits.slice(5)
  else if (digits.startsWith('964')) digits = digits.slice(3)
  if (digits.startsWith('0')) digits = digits.slice(1)
  return /^7\d{9}$/.test(digits) ? `+964${digits}` : null
}
