import type { z } from 'zod'
import { isMessageKey } from '../lib/i18n.js'
import { AppError, type FieldMessage } from './errors.js'

type Issue = z.core.$ZodIssue

/**
 * [value] parsed by [schema], or a 422 VALIDATION_ERROR naming each field that
 * is wrong, in the contract's shape (`errors.{field}`).
 *
 * Messages are keys from lib/i18n.ts, never zod's English, so an Arabic
 * reader never gets an English field error. A schema may name its own key as
 * the message for a value that is wrong: z.string({ error: 'field.phone' }).
 */
export function parseInput<S extends z.ZodType>(schema: S, value: unknown, flatten: readonly string[] = []): z.output<S> {
  const result = schema.safeParse(value)
  if (result.success) return result.data
  const fields: Record<string, FieldMessage> = {}
  for (const issue of result.error.issues) {
    // A nested object in [flatten] names its fields on their own, as its form's boxes are named.
    const path = flatten.includes(String(issue.path[0])) ? issue.path.slice(1) : issue.path
    const field = path.map(String).join('.') || '_'
    fields[field] ??= messageFor(issue, valueAt(value, issue.path))
  }
  throw new AppError(422, 'VALIDATION_ERROR', 'error.validation', undefined, fields)
}

function messageFor(issue: Issue, actual: unknown): FieldMessage {
  // Missing is "Required" even when the schema names its own key: that key is
  // for a value that is there but wrong.
  if (actual === undefined || actual === null) return { key: 'field.required' }
  if (isMessageKey(issue.message)) return { key: issue.message }
  if (issue.code === 'too_big') {
    const max = Number(issue.maximum)
    return issue.origin === 'string'
      ? { key: 'field.tooLong', params: { max } }
      : { key: 'field.tooBig', params: { max } }
  }
  if (issue.code === 'too_small') {
    const min = Number(issue.minimum)
    return issue.origin === 'string'
      ? { key: 'field.tooShort', params: { min } }
      : { key: 'field.tooSmall', params: { min } }
  }
  return { key: 'field.invalid' }
}

function valueAt(value: unknown, path: readonly PropertyKey[]): unknown {
  let current = value
  for (const key of path) {
    if (current === null || typeof current !== 'object') return undefined
    current = (current as Record<PropertyKey, unknown>)[key]
  }
  return current
}
