// The app's own search cases (mobile/test/core/search_text_test.dart), ported:
// "The real backend must fold the same way, or search changes on launch day."
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { fold, searchWords } from '../src/lib/fold.js'

/** SearchText.matches: every word of [query], folded, somewhere in [fields]. */
function matches(query: string, fields: (string | null)[]): boolean {
  const haystack = fold(fields.filter((f): f is string => f !== null).join(' '))
  return searchWords(query).every((word) => haystack.includes(word))
}

test('the ways Arabic is typed in Iraq fold into one', () => {
  // Hamza on or under the alef, madda, wasla.
  assert.equal(fold('أحمد'), fold('احمد'))
  assert.equal(fold('إسبريسو'), fold('اسبريسو'))
  assert.equal(fold('آلة'), fold('الة'))
  // Ta marbuta and ha, alef maqsura and ya.
  assert.equal(fold('مكتبة'), fold('مكتبه'))
  assert.equal(fold('مصطفى'), fold('مصطفي'))
  // Hamza on waw and on ya.
  assert.equal(fold('مؤسسة'), fold('موسسه'))
  assert.equal(fold('هيئة'), fold('هييه'))
  // Vowel marks and the tatweel that stretches a word.
  assert.equal(fold('مُصْطَفَى'), fold('مصطفى'))
  assert.equal(fold('منقّي'), fold('منقي'))
  assert.equal(fold('سـبـأ'), fold('سبا'))
  // A Persian or Kurdish keyboard's ya and kaf.
  assert.equal(fold('کامیرا'), fold('كاميرا'))
  // Arabic and Persian digits.
  assert.equal(fold('شاحن ٦٥ واط'), 'شاحن 65 واط')
  assert.equal(fold('۶۵'), '65')
  // Case and spaces.
  assert.equal(fold('  Nova   X5 '), 'nova x5')
})

test('every word must be found, in any order, and ال is optional', () => {
  const names = ['ساعة أطلس الذكية الإصدار 4', 'Atlas Smartwatch Series 4']
  assert.equal(matches('ساعه', names), true)
  assert.equal(matches('اطلس ساعة', names), true)
  assert.equal(matches('الساعة', names), true)
  assert.equal(matches('smartwatch atlas', names), true)
  assert.equal(matches('ساعة نوفا', names), false)
  assert.equal(matches('camera', names), false)
  // Nothing typed finds everything; a missing field is not an error.
  assert.equal(matches('  ', names), true)
  assert.equal(matches('atlas', [null, 'Atlas']), true)
})
