import assert from 'node:assert/strict'
import { test } from 'node:test'
import { languageOf } from '../src/http/language.js'
import { dictionaries, t, type MessageKey } from '../src/lib/i18n.js'

const ARABIC_LETTER = /[؀-ۿ]/

test('every Arabic entry is Arabic, so English pasted in by mistake is caught', () => {
  for (const [key, text] of Object.entries(dictionaries.ar)) {
    assert.match(text, ARABIC_LETTER, `ar["${key}"] has no Arabic in it: "${text}"`)
  }
})

test('English and Arabic have exactly the same keys', () => {
  assert.deepEqual(Object.keys(dictionaries.ar).sort(), Object.keys(dictionaries.en).sort())
})

test('a missing translation shows as a marker, never as English', () => {
  assert.equal(t('ar', 'no.such.key' as MessageKey), '⟦no.such.key⟧')
  assert.equal(t('en', 'no.such.key' as MessageKey), '⟦no.such.key⟧')
})

test('placeholders are filled in; a missing value stays visible', () => {
  assert.equal(t('en', 'field.tooLong', { max: 50 }), 'Use at most 50 characters.')
  assert.equal(t('ar', 'field.tooLong', { max: 50 }), 'استخدم 50 حرفاً على الأكثر.')
  assert.equal(t('en', 'field.tooLong'), 'Use at most {max} characters.')
})

test("a value that ends its own sentence takes no second full stop (Saba's typed reasons)", () => {
  assert.equal(
    t('en', 'notify.productRejected.body', { reason: 'Show the case itself.' }),
    'Reason: Show the case itself. Change it and send it again.',
  )
  assert.equal(
    t('ar', 'notify.productRejected.body', { reason: 'صوّر الغطاء نفسه.' }),
    'السبب: صوّر الغطاء نفسه. عدّله وأرسله مرة أخرى.',
  )
  assert.equal(t('en', 'notify.productTakenDown.body', { reason: 'Is it genuine?' }), 'Reason: Is it genuine?')
  assert.equal(t('ar', 'notify.productTakenDown.body', { reason: 'هل هو أصلي؟' }), 'السبب: هل هو أصلي؟')
  // Without a stop of its own, the message still gives it one.
  assert.equal(t('en', 'notify.productTakenDown.body', { reason: 'Counterfeit' }), 'Reason: Counterfeit.')
})

test('the language is the first one asked for: Arabic, or else English', () => {
  assert.equal(languageOf('ar'), 'ar')
  assert.equal(languageOf('ar-IQ,ar;q=0.9,en;q=0.8'), 'ar')
  assert.equal(languageOf('AR'), 'ar')
  assert.equal(languageOf('en-US,ar;q=0.9'), 'en')
  assert.equal(languageOf('en'), 'en')
  assert.equal(languageOf(undefined), 'en')
  assert.equal(languageOf(''), 'en')
  // Mapudungun, not Arabic: a bare startsWith('ar') would get this wrong.
  assert.equal(languageOf('arn'), 'en')
})
